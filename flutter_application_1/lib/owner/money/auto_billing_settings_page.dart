import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'package:flutter_application_1/color_app.dart';
import 'dart:async';
import 'package:flutter_application_1/widgets/page_header_card.dart';

class AutoBillingSettingsPage extends StatefulWidget {
  final int buildingId;
  const AutoBillingSettingsPage({super.key, required this.buildingId});

  @override
  State<AutoBillingSettingsPage> createState() =>
      _AutoBillingSettingsPageState();
}

class _AutoBillingSettingsPageState extends State<AutoBillingSettingsPage> {
  // --- form state ---
  int _cutDay = 1;
  TimeOfDay _runAt = const TimeOfDay(hour: 2, minute: 0);
  bool _prepayRequired = true;
  bool _cutoffWhenInsufficient = true;
  bool _cutPower = true;
  bool _cutWater = true;
  int _notifyDaysBefore = 3;
  int _graceDays = 0;
  bool _cutRoom = true;
  DateTime? _nextRunAt;

  bool _loading = false;

  String _mode = 'combined';

  int _cutDayRoom = 1, _cutDayWater = 1, _cutDayElec = 1;
  TimeOfDay _runAtRoom = const TimeOfDay(hour: 2, minute: 0);
  TimeOfDay _runAtWater = const TimeOfDay(hour: 2, minute: 0);
  TimeOfDay _runAtElec = const TimeOfDay(hour: 2, minute: 0);

  @override
  void initState() {
    super.initState();
    _fetchConfig();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _fmtNextRun(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year + 543).toString().substring(2);
    final hh = d.hour.toString().padLeft(2, '0');
    final mn = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$mn';
  }

  // รีทรายแบบ backoff 2 ครั้ง (รวม 3 รอบ: 0s, 2s, 4s)
  Future<T> _retry<T>(Future<T> Function() fn, {int times = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        if (++attempt > times) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

// กัน body ว่าง/ไม่ใช่ JSON object → คืน Map ว่าง
  // เพิ่ม/แทนที่ของเดิม
  Map<String, dynamic> _safeJsonObject(String body) {
    try {
      if (body.isEmpty || body == 'null') return <String, dynamic>{};
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<String?> _getIdToken() async {
    final u = FirebaseAuth.instance.currentUser;
    return await u?.getIdToken();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _fetchConfig() async {
    setState(() => _loading = true);
    TimeOfDay _parseHHmm(dynamic v, TimeOfDay fb) {
      final s = (v ?? '').toString();
      if (s.isEmpty) return fb;
      final p = s.split(':');
      final h = int.tryParse(p[0]) ?? fb.hour;
      final m = int.tryParse(p.length > 1 ? p[1] : '') ?? fb.minute;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }

    try {
      final token = await _getIdToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อน')),
          );
          setState(() => _loading = false); // <<< ปิดสปินก่อนออก
        }
        return;
      }

      final uri = Uri.parse(
          '$apiBaseUrl/api/owner/${widget.buildingId}/auto-billing/config');
      final resp = await _retry(() => http.get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 12), onTimeout: () {
            throw TimeoutException('GET $uri timed out');
          }));

      // ignore: avoid_print
      print('[CFG] GET $uri -> ${resp.statusCode}, len=${resp.body.length}');

      if (resp.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('โหลดการตั้งค่าไม่สำเร็จ (${resp.statusCode})')),
          );
          setState(() => _loading = false); // <<< ปิดสปินก่อนออก
        }
        return;
      }

      final data = _safeJsonObject(resp.body);
      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            _mode = 'combined'; // default
            _loading = false; // <<< ปิดสปิน
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _prepayRequired = (data['prepay_required'] ?? true) as bool;
        _cutoffWhenInsufficient =
            (data['cutoff_when_insufficient'] ?? true) as bool;

        final ct = (data['cut_targets'] ??
            {'room': true, 'power': true, 'water': true}) as Map;
        _cutRoom = (ct['room'] ?? true) as bool;
        _cutPower = (ct['power'] ?? true) as bool;
        _cutWater = (ct['water'] ?? true) as bool;

        _notifyDaysBefore =
            int.tryParse('${data['notify_days_before'] ?? 3}') ?? 3;
        _graceDays = int.tryParse('${data['grace_days'] ?? 0}') ?? 0;

        // ไม่ต้องอ่าน _minBalanceCtrl แล้ว
        // _minBalanceCtrl.text = '${data['min_balance'] ?? 0}';

        _nextRunAt = data['next_run_at'] != null
            ? DateTime.tryParse('${data['next_run_at']}')
            : null;

        final mode = (data['mode'] ?? 'combined').toString();
        if (mode == 'split') {
          _mode = 'split';
          final schedules = (data['schedules'] ?? {}) as Map;
          final room = (schedules['room'] ?? {}) as Map;
          final water = (schedules['water'] ?? {}) as Map;
          final elec =
              (schedules['electric'] ?? schedules['elec'] ?? {}) as Map;

          _cutDayRoom =
              int.tryParse('${room['cut_day'] ?? _cutDayRoom}') ?? _cutDayRoom;
          _runAtRoom = _parseHHmm(room['time'], _runAtRoom);
          _cutDayWater = int.tryParse('${water['cut_day'] ?? _cutDayWater}') ??
              _cutDayWater;
          _runAtWater = _parseHHmm(water['time'], _runAtWater);
          _cutDayElec =
              int.tryParse('${elec['cut_day'] ?? _cutDayElec}') ?? _cutDayElec;
          _runAtElec = _parseHHmm(elec['time'], _runAtElec);
        } else {
          _mode = 'combined';
          _cutDay = int.tryParse('${data['cut_day'] ?? _cutDay}') ?? _cutDay;
          _runAt = _parseHHmm(data['run_at_time'] ?? data['time'], _runAt);
        }
        _loading = false; // <<< ปิดสปินตอนจบปกติ
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
        setState(() => _loading = false); // <<< ปิดสปินแม้ catch
      }
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final token = await _getIdToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อน')),
          );
        }
        return;
      }

      String fmt(TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final payload = <String, dynamic>{
        'mode': _mode,
        'timezone': 'Asia/Bangkok',
        'prepay_required': _prepayRequired,
        'cutoff_when_insufficient': _cutoffWhenInsufficient,
        'cut_targets': {
          'room': _cutRoom,
          'power': _cutPower,
          'water': _cutWater
        },
        'notify_days_before': _notifyDaysBefore,
        'grace_days': _graceDays,
      };

      if (_mode == 'combined') {
        payload['cut_day'] = _cutDay;
        payload['run_at_time'] = fmt(_runAt);
      } else {
        payload['schedules'] = {
          'room': {'cut_day': _cutDayRoom, 'time': fmt(_runAtRoom)},
          'water': {'cut_day': _cutDayWater, 'time': fmt(_runAtWater)},
          'electric': {'cut_day': _cutDayElec, 'time': fmt(_runAtElec)},
        };
      }

      final uri = Uri.parse(
          '$apiBaseUrl/api/owner/${widget.buildingId}/auto-billing/config');

      final resp = await _retry(() => http
              .put(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(payload),
          )
              .timeout(const Duration(seconds: 12), onTimeout: () {
            throw TimeoutException('PUT $uri timed out');
          }));

      // ignore: avoid_print
      print('[CFG] PUT $uri -> ${resp.statusCode}, len=${resp.body.length}');

      if (resp.statusCode == 200) {
        final m = _safeJsonObject(resp.body);
        final cfg = (m['config'] ?? {}) as Map<String, dynamic>;
        setState(() {
          _nextRunAt = cfg['next_run_at'] != null
              ? DateTime.tryParse('${cfg['next_run_at']}')
              : null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกสำเร็จ')),
          );
        }
      } else {
        String msg = 'บันทึกไม่สำเร็จ (${resp.statusCode})';
        try {
          final m = jsonDecode(resp.body);
          if (m is Map && m['error'] != null) msg = '$msg: ${m['error']}';
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _simulate() async {
    setState(() => _loading = true);
    try {
      final token = await _getIdToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อน')),
          );
        }
        return;
      }

      final uri = Uri.parse(
          '$apiBaseUrl/api/owner/${widget.buildingId}/auto-billing/simulate');

      final resp = await _retry(() => http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
          ).timeout(const Duration(seconds: 20), onTimeout: () {
            throw TimeoutException('POST $uri timed out');
          }));

      // ignore: avoid_print
      print(
          '[CFG] POST simulate -> ${resp.statusCode}, len=${resp.body.length}');

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = _safeJsonObject(resp.body);
        final result = data['result'];
        final count = result is List ? result.length : (result?['length'] ?? 0);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('จำลองรอบตัดยอด'),
            content: Text(
                'สร้าง/อัปเดตใบแจ้งหนี้ให้ผู้เช่า $count ราย (ยังไม่หักเงินจริง ไม่ตัดน้ำ/ไฟ)'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ปิด'))
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('จำลองไม่สำเร็จ (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _runAt);
    if (t != null) setState(() => _runAt = t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = AppColors.primary;

    return Scaffold(
      // ไม่ให้มีปุ่ม Back อัตโนมัติ และไม่ใช้ AppBar สีเขียว
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ── หัวกล่องสีขาวแบบเดียวกับหน้าอื่น ──
              PageHeaderCard(
                showBack: false,
                leadingIcon: Icons.schedule_rounded,
                title: 'ตัดยอดอัตโนมัติ • Building ${widget.buildingId}',
                chipText: 'รอบถัดไป: ${_fmtNextRun(_nextRunAt)}',
                actions: [
                  IconButton(
                    tooltip: 'จำลองรอบตัดยอด',
                    onPressed: _loading ? null : _simulate,
                    icon: const Icon(Icons.play_circle_outline,
                        color: AppColors.primaryDark),
                  ),
                  IconButton(
                    tooltip: 'บันทึกการตั้งค่า',
                    onPressed: _loading ? null : _save,
                    icon: const Icon(Icons.save, color: AppColors.primaryDark),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── การ์ด: รอบตัดยอด ──
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('รอบตัดยอด',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          const Text('วัน:'),
                          DropdownButton<int>(
                            value: _cutDay,
                            items: List.generate(31, (i) => i + 1)
                                .map((d) => DropdownMenuItem(
                                    value: d, child: Text('$d')))
                                .toList(),
                            onChanged: (v) => setState(() => _cutDay = v ?? 1),
                          ),
                          const SizedBox(width: 8),
                          const Text('เวลา:'),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(_fmtTime(_runAt)),
                            onPressed: _pickTime,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('รอบถัดไป: ${_fmtNextRun(_nextRunAt)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── การ์ด: นโยบาย ──
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('นโยบาย',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      SwitchListTile(
                        title: const Text(
                            'ต้องเติมเงินล่วงหน้าก่อนตัดยอด (Prepay Required)'),
                        value: _prepayRequired,
                        onChanged: (v) => setState(() => _prepayRequired = v),
                      ),
                      SwitchListTile(
                        title: const Text('เงินไม่พอ → ตัดอัตโนมัติ'),
                        value: _cutoffWhenInsufficient,
                        onChanged: (v) =>
                            setState(() => _cutoffWhenInsufficient = v),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const Text('ตัด:'),
                          FilterChip(
                            label: const Text('ค่าห้อง'),
                            selected: _cutRoom,
                            onSelected: (v) => setState(() => _cutRoom = v),
                            selectedColor: AppColors.primaryLight,
                            checkmarkColor: AppColors.primaryDark,
                          ),
                          FilterChip(
                            label: const Text('ไฟฟ้า'),
                            selected: _cutPower,
                            onSelected: (v) => setState(() => _cutPower = v),
                            selectedColor: AppColors.primaryLight,
                            checkmarkColor: AppColors.primaryDark,
                          ),
                          FilterChip(
                            label: const Text('น้ำ'),
                            selected: _cutWater,
                            onSelected: (v) => setState(() => _cutWater = v),
                            selectedColor: AppColors.primaryLight,
                            checkmarkColor: AppColors.primaryDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('แจ้งเตือนล่วงหน้า (วัน): '),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 7,
                              divisions: 7,
                              value: _notifyDaysBefore.toDouble(),
                              label: '$_notifyDaysBefore',
                              onChanged: (v) =>
                                  setState(() => _notifyDaysBefore = v.toInt()),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('ผ่อนผัน (วัน): '),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 7,
                              divisions: 7,
                              value: _graceDays.toDouble(),
                              label: '$_graceDays',
                              onChanged: (v) =>
                                  setState(() => _graceDays = v.toInt()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── ปุ่มบันทึก+จำลอง (ซ้ำ action บนหัว — เผื่อจบหน้า) ──
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('บันทึกการตั้งค่า'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _loading ? null : _save,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('จำลองรอบตัดยอด'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _loading ? null : _simulate,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.05),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
