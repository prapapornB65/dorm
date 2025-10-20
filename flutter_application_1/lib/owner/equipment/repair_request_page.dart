// lib/owner/equipment/repair_request_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/page_header_card.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

/// =======================================
///  RepairRequestPage (Owner)
///  - หน้าสำหรับ "เจ้าของ" ดูคำขอซ่อม + อัปเดตสถานะ
///  - รับ ownerId + buildingId
///  - ดึงรายการจาก:   GET  /api/owner/:ownerId/repairs?buildingId=...
///  - อัปเดตสถานะ:    PATCH /api/owner/:ownerId/repairs/:id/status {status}
///  สถานะ: NEW, IN_PROGRESS, DONE, REJECTED
/// =======================================
class RepairRequestPage extends StatefulWidget {
  final int ownerId;
  final int buildingId;

  const RepairRequestPage({
    super.key,
    required this.ownerId,
    required this.buildingId,
  });

  @override
  State<RepairRequestPage> createState() => _RepairRequestPageState();
}

class _RepairRequestPageState extends State<RepairRequestPage> {
  bool _loading = true;
  String? _error;

  // DEBUG info
  String? _lastUrl;
  int? _lastCode;
  int _lastBytes = 0;
  Duration _lastElapsed = Duration.zero;
  String? _lastBodyPreview;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];

  final _search = TextEditingController();
  String _statusFilter = 'ALL'; // ALL, NEW, IN_PROGRESS, DONE, REJECTED

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _log(Object? o) {
    if (kDebugMode) debugPrint('[OwnerRepairs] $o');
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    final masked = (token == null)
        ? '<null>'
        : '${token.substring(0, 12)}...(${token.length} chars)';

    _log('AUTH: user=${user?.uid ?? "-"} token=$masked');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  int _statusWeight(dynamic s) {
    final st = (s ?? '').toString().toUpperCase();
    switch (st) {
      case 'NEW':
        return 0;
      case 'IN_PROGRESS':
        return 1;
      case 'DONE':
        return 2;
      case 'REJECTED':
        return 3;
      default:
        return 9;
    }
  }

  String toApiStatus(String ui) {
    switch (ui.toUpperCase()) {
      case 'NEW':
        return 'new';
      case 'IN_PROGRESS':
        return 'in_progress';
      case 'DONE':
        return 'done';
      case 'REJECTED':
        return 'cancelled';
      default:
        return 'new';
    }
  }

  String toUiStatus(dynamic api) {
    final s = (api ?? '').toString().toLowerCase();
    switch (s) {
      case 'new':
        return 'NEW';
      case 'in_progress':
        return 'IN_PROGRESS';
      case 'done':
        return 'DONE';
      case 'cancelled':
        return 'REJECTED';
      default:
        return s.toUpperCase();
    }
  }

  void _applyFilter() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = _items.where((e) {
        final statusUi = toUiStatus(e['Status']);
        final okStatus =
            _statusFilter == 'ALL' ? true : statusUi == _statusFilter;

        final equip = (e['EquipmentName'] ?? e['Equipment'] ?? '').toString();
        final text = [
          e['RoomNumber'] ?? '',
          equip,
          e['IssueDetail'] ?? '',
          e['TenantName'] ?? '',
          e['RequestID']?.toString() ?? e['id']?.toString() ?? '',
        ].join(' ').toLowerCase();

        return okStatus && (q.isEmpty || text.contains(q));
      }).toList();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // NOTE: ใช้ route ตามตึก (ไม่ใช่ /owner/:id/repairs?buildingId=...)
      final url = Uri.parse(
          '$apiBaseUrl/api/owner/building/${widget.buildingId}/repairs'
          // ถ้าจะส่ง filter ไป backend ด้วย (ตามที่ routes รองรับ):
          // '?status=${toApiStatus(_statusFilter)}&q=${Uri.encodeQueryComponent(_search.text)}'
          );

      _lastUrl = url.toString();
      _log('GET $_lastUrl');
      final sw = Stopwatch()..start();

      final headers = await _authHeaders();
      final res = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));

      sw.stop();
      _lastCode = res.statusCode;
      _lastBytes = res.bodyBytes.length;
      _lastElapsed = sw.elapsed;
      _lastBodyPreview =
          res.body.length > 600 ? '${res.body.substring(0, 600)}…' : res.body;
      _log(
          'RES ${res.statusCode} in ${sw.elapsed.inMilliseconds}ms bytes=$_lastBytes');

      if (res.statusCode != 200) {
        String msg = 'HTTP ${res.statusCode}';
        try {
          final j = json.decode(res.body);
          msg = (j['error'] ?? j['message'] ?? msg).toString();
        } catch (_) {}
        throw msg;
      }

      final j = json.decode(res.body);
      final list = (j is List) ? j : (j['data'] ?? j['items'] ?? []);

      _items = List<Map<String, dynamic>>.from(
        list.map((e) => Map<String, dynamic>.from(e as Map)),
      )..sort((a, b) {
          // เรียงตามน้ำหนักสถานะ + เวลา
          final aw = _statusWeight(toUiStatus(a['Status']));
          final bw = _statusWeight(toUiStatus(b['Status']));
          if (aw != bw) return aw.compareTo(bw);
          final at = (a['CreatedAt'] ?? a['RequestDate'] ?? '').toString();
          final bt = (b['CreatedAt'] ?? b['RequestDate'] ?? '').toString();
          return bt.compareTo(at);
        });

      _applyFilter();
      if (mounted) setState(() => _loading = false);
    } on TimeoutException {
      _error = 'เชื่อมต่อช้าเกินไป (timeout)';
      if (mounted) setState(() => _loading = false);
      _log('TIMEOUT for $_lastUrl after ${_lastElapsed.inMilliseconds}ms');
    } catch (e) {
      _error = e.toString();
      if (mounted) setState(() => _loading = false);
      _log('LOAD ERROR: $e (url=$_lastUrl)');
    }
  }

  Future<void> _updateStatus(int id, String uiStatus) async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/owner/repairs/$id/status');
      final apiStatus = toApiStatus(uiStatus);
      _log('PATCH $url -> $uiStatus ($apiStatus)');

      final sw = Stopwatch()..start();
      final res = await http
          .patch(
            url,
            headers: await _authHeaders(),
            body: json.encode({'status': apiStatus}),
          )
          .timeout(const Duration(seconds: 12));
      sw.stop();

      final preview =
          res.body.length > 400 ? '${res.body.substring(0, 400)}…' : res.body;
      _log('PATCH RES ${res.statusCode} in ${sw.elapsed.inMilliseconds}ms '
          'bytes=${res.bodyBytes.length}');
      _log('PATCH BODY preview: $preview');

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('อัปเดตสถานะสำเร็จ')));
        await _load();
      } else {
        String msg = 'อัปเดตไม่สำเร็จ (${res.statusCode})';
        try {
          final j = json.decode(res.body);
          msg = (j['error'] ?? j['message'] ?? msg).toString();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตช้าเกินไป (timeout)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F6),

      // ❌ ไม่ใช้ AppBar gradient, ไม่ให้แสดงปุ่มย้อนกลับ
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ✅ หัวกล่องขาวมาตรฐาน
                  PageHeaderCard(
                    showBack: false, // ไม่มีปุ่มย้อนกลับ
                    leadingIcon: Icons.build,
                    title: 'งานแจ้งซ่อม (เจ้าของ)',
                    chipText: 'Building ID: ${widget.buildingId}',
                    actions: [
                      IconButton(
                        tooltip: 'รีเฟรช',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 🔍 แถวค้นหา + ตัวกรอง (คงโค้ดเดิม)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText:
                                'ค้นหา (#id/เลขห้อง/อุปกรณ์/รายละเอียด/ผู้เช่า)',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF6FAF9),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.primary),
                            ),
                            suffixIcon: (_search.text.isEmpty)
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _search.clear();
                                      _applyFilter();
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButton<String>(
                            value: _statusFilter,
                            items: const [
                              DropdownMenuItem(
                                  value: 'ALL', child: Text('ทั้งหมด')),
                              DropdownMenuItem(
                                  value: 'NEW',
                                  child: Text('ยังไม่ได้รับเรื่อง')),
                              DropdownMenuItem(
                                  value: 'IN_PROGRESS',
                                  child: Text('กำลังซ่อม')),
                              DropdownMenuItem(
                                  value: 'DONE', child: Text('ซ่อมแล้ว')),
                              DropdownMenuItem(
                                  value: 'REJECTED',
                                  child: Text('ยกเลิก/ไม่รับ')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _statusFilter = v);
                              _applyFilter();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 🔔 กล่อง error (เดิม)
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('$_error',
                                style: const TextStyle(color: Colors.red)),
                          ),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('ลองใหม่'),
                          )
                        ],
                      ),
                    ),

                  const SizedBox(height: 6),

                  // 📋 รายการ (เดิม)
                  Expanded(
                    child: _filtered.isEmpty
                        ? const Center(
                            child: Text('ไม่พบรายการแจ้งซ่อม',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          )
                        : ListView.separated(
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final e = _filtered[i];
                              final id = e['RequestID'] ?? e['id'];
                              final status =
                                  (e['Status'] ?? '').toString().toUpperCase();

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x14000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '#$id',
                                            style: const TextStyle(
                                              color: AppColors.primaryDark,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${e['RoomNumber'] ?? '-'} • ${(e['EquipmentName'] ?? '').toString()}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const Spacer(),
                                        _StatusPill(status: status),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${e['IssueDetail'] ?? '-'}',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                    if ((e['Images'] as List?)?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: (e['Images'] as List)
                                            .map((u) => ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.network(
                                                    u.toString(),
                                                    width: 84,
                                                    height: 84,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _StatusButton(
                                          label: 'ยังไม่ได้รับเรื่อง',
                                          selected: status == 'NEW',
                                          onTap: () =>
                                              _updateStatus(id as int, 'NEW'),
                                        ),
                                        _StatusButton(
                                          label: 'กำลังซ่อม',
                                          selected: status == 'IN_PROGRESS',
                                          onTap: () => _updateStatus(
                                              id as int, 'IN_PROGRESS'),
                                        ),
                                        _StatusButton(
                                          label: 'ซ่อมแล้ว',
                                          selected: status == 'DONE',
                                          onTap: () =>
                                              _updateStatus(id as int, 'DONE'),
                                        ),
                                        _StatusButton(
                                          label: 'ยกเลิก',
                                          selected: status == 'REJECTED',
                                          onTap: () => _updateStatus(
                                              id as int, 'REJECTED'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------- Small widgets ----------
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'NEW':
        c = Colors.orange;
        break;
      case 'IN_PROGRESS':
        c = Colors.blue;
        break;
      case 'DONE':
        c = Colors.green;
        break;
      case 'REJECTED':
        c = Colors.grey;
        break;
      default:
        c = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child:
          Text(status, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : AppColors.textPrimary,
        backgroundColor: selected ? AppColors.primary : Colors.white,
        side:
            BorderSide(color: selected ? AppColors.primary : AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}
