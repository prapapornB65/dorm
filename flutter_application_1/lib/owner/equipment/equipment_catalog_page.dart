// lib/owner/equipment/owner_equipment_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'package:flutter_application_1/widgets/page_header_card.dart';

void _d(String tag, String msg) {
  final now = DateTime.now().toIso8601String();
  debugPrint('[$now][$tag] $msg');
}

Future<http.Response> _fetchGet({
  required String tag,
  required String url,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final sw = Stopwatch()..start();
  _d(tag, '-> GET $url');
  try {
    final r = await http.get(Uri.parse(url), headers: headers).timeout(timeout);
    _d(tag,
        '<- ${r.statusCode} in ${sw.elapsedMilliseconds}ms (len=${r.body.length})');
    return r;
  } on TimeoutException {
    _d(tag, '!! TIMEOUT after ${sw.elapsedMilliseconds}ms');
    rethrow;
  } on SocketException catch (e) {
    _d(tag,
        '!! SOCKET ${e.osError} (${e.message}) after ${sw.elapsedMilliseconds}ms');
    rethrow;
  } catch (e) {
    _d(tag, '!! ERROR $e after ${sw.elapsedMilliseconds}ms');
    rethrow;
  }
}

Future<http.Response> _fetchPost({
  required String tag,
  required String url,
  Map<String, String>? headers,
  Object? body,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final sw = Stopwatch()..start();
  _d(tag, '-> POST $url body=${body is String ? body : jsonEncode(body)}');
  try {
    final r = await http
        .post(Uri.parse(url), headers: headers, body: body)
        .timeout(timeout);
    _d(tag,
        '<- ${r.statusCode} in ${sw.elapsedMilliseconds}ms (len=${r.body.length})');
    return r;
  } on TimeoutException {
    _d(tag, '!! TIMEOUT after ${sw.elapsedMilliseconds}ms');
    rethrow;
  } on SocketException catch (e) {
    _d(tag,
        '!! SOCKET ${e.osError} (${e.message}) after ${sw.elapsedMilliseconds}ms');
    rethrow;
  } catch (e) {
    _d(tag, '!! ERROR $e after ${sw.elapsedMilliseconds}ms');
    rethrow;
  }
}

List<Map<String, dynamic>> _jsonToListMaps(String body) {
  try {
    final decoded = json.decode(body);
    final List raw = (decoded is List)
        ? decoded
        : (decoded['data'] ?? decoded['items'] ?? const []);
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  } catch (e) {
    _d('json',
        '!! decode error: $e, body sample: ${body.substring(0, body.length.clamp(0, 200))}');
    return const [];
  }
}

class OwnerEquipmentPage extends StatefulWidget {
  final int ownerId;
  final int? buildingId;

  const OwnerEquipmentPage({
    super.key,
    required this.ownerId,
    this.buildingId,
  });

  @override
  State<OwnerEquipmentPage> createState() => _OwnerEquipmentPageState();
}

class _OwnerEquipmentPageState extends State<OwnerEquipmentPage> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _allEquipments = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<int> _selectedIds = {};

  final _search = TextEditingController();

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  void _applyFilter() {
    final q = _normalize(_search.text);
    setState(() {
      if (q.isEmpty) {
        _filtered = List.of(_allEquipments);
      } else {
        _filtered = _allEquipments.where((e) {
          final name = (e['EquipmentName'] ?? '').toString();
          return _normalize(name).contains(q);
        }).toList();
      }
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final headers = await _authHeaders();
      _d('cfg',
          'apiBaseUrl=$apiBaseUrl ownerId=${widget.ownerId} buildingId=${widget.buildingId}');

      // 1) Catalog
      http.Response rAll;
      try {
        rAll = await _fetchGet(
          tag: 'catalog',
          url: '$apiBaseUrl/api/equipment',
          headers: headers,
          timeout: const Duration(seconds: 8),
        );
      } on TimeoutException {
        _error = 'โหลดรายการอุปกรณ์ (catalog) ช้าเกินไป (timeout)';
        setState(() => _loading = false);
        return;
      }

      if (rAll.statusCode == 401) {
        _error = 'ไม่ได้รับอนุญาต (401) กรุณาเข้าสู่ระบบใหม่';
        setState(() => _loading = false);
        return;
      }
      if (rAll.statusCode != 200) {
        _error = 'catalog HTTP ${rAll.statusCode}';
        setState(() => _loading = false);
        return;
      }

      _allEquipments = _jsonToListMaps(rAll.body)
        ..sort((a, b) {
          final an = _normalize((a['EquipmentName'] ?? '').toString());
          final bn = _normalize((b['EquipmentName'] ?? '').toString());
          return an.compareTo(bn);
        });

      // 2) Owner selected
      try {
        final rSel = await _fetchGet(
          tag: 'ownerSel',
          url: '$apiBaseUrl/api/owner/${widget.ownerId}/equipments',
          headers: headers,
          timeout: const Duration(seconds: 8),
        );
        if (rSel.statusCode == 200) {
          final sj = json.decode(rSel.body);
          final List list =
              (sj is List) ? sj : (sj['data'] ?? sj['items'] ?? []);
          _selectedIds
            ..clear()
            ..addAll(list.map<int>((e) {
              if (e is int) return e;
              if (e is Map && e['EquipmentID'] != null)
                return int.tryParse(e['EquipmentID'].toString()) ?? -1;
              return int.tryParse(e.toString()) ?? -1;
            }).where((id) => id > 0));
        } else if (rSel.statusCode == 401) {
          _error = 'ไม่ได้รับอนุญาต (401) สำหรับ ownerSel';
        } else {
          _error = 'ownerSel HTTP ${rSel.statusCode}';
        }
      } on TimeoutException {
        _error = 'โหลดรายการที่เลือกของเจ้าของช้าเกินไป (ownerSel timeout)';
      } catch (e) {
        _error = 'ownerSel error: $e';
      }

      _applyFilter();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final headers = await _authHeaders();
    try {
      final resp = await http
          .post(
            Uri.parse('$apiBaseUrl/api/owner/${widget.ownerId}/equipments'),
            headers: headers,
            body: json.encode({'equipmentIds': _selectedIds.toList()}),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกอุปกรณ์สำเร็จ')));
      } else {
        String msg = 'บันทึกไม่สำเร็จ (${resp.statusCode})';
        try {
          final j = json.decode(resp.body);
          msg = (j['error'] ?? j['message'] ?? msg).toString();
        } catch (_) {}
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกช้าเกินไป (timeout)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  Future<void> _addEquipmentDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: const Text('เพิ่มชนิดอุปกรณ์',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ชื่ออุปกรณ์',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('เพิ่ม'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final resp = await http
          .post(
            Uri.parse('$apiBaseUrl/api/equipment'),
            headers: await _authHeaders(),
            body: json.encode({'EquipmentName': name}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        await _loadAll();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('เพิ่ม "$name" สำเร็จ')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เพิ่มไม่สำเร็จ (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  void _toggleAll(bool check) {
    setState(() {
      if (check) {
        _selectedIds.addAll(
          _filtered
              .map((e) => int.tryParse(e['EquipmentID'].toString()) ?? -1)
              .where((id) => id > 0),
        );
      } else {
        final idsInView = _filtered
            .map((e) => int.tryParse(e['EquipmentID'].toString()) ?? -1)
            .where((id) => id > 0)
            .toSet();
        _selectedIds.removeWhere(idsInView.contains);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedIds.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'เลือกแล้ว: $selectedCount',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('บันทึก'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                PageHeaderCard(
                  showBack: false,
                  leadingIcon: Icons.inventory_2_rounded,
                  title: 'คลังอุปกรณ์',
                  chipText:
                      'ทั้งหมด ${_allEquipments.length} • เลือก ${_selectedIds.length}',
                  actions: [
                    IconButton(
                      tooltip: 'เพิ่มชนิดอุปกรณ์',
                      onPressed: _addEquipmentDialog,
                      icon: const Icon(Icons.add_rounded,
                          color: AppColors.primaryDark),
                    ),
                    IconButton(
                      tooltip: 'รีเฟรช',
                      onPressed: _loadAll,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.primaryDark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.list_alt_rounded,
                                  color: AppColors.primaryDark, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text('รายการอุปกรณ์ทั้งหมด',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _toggleAll(true),
                              icon: const Icon(Icons.select_all_rounded),
                              label: const Text('เลือกทั้งหมด'),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              onPressed: () => _toggleAll(false),
                              icon: const Icon(Icons.deselect_rounded),
                              label: const Text('ไม่เลือก'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'ค้นหาอุปกรณ์...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: const Color(0xFFF6FAF9),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.primary),
                            ),
                            suffixIcon: (_search.text.isEmpty)
                                ? null
                                : IconButton(
                                    tooltip: 'ล้าง',
                                    onPressed: () {
                                      _search.clear();
                                      _applyFilter();
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_error!,
                                      style:
                                          const TextStyle(color: Colors.red))),
                              TextButton.icon(
                                onPressed: _loadAll,
                                icon: const Icon(Icons.refresh),
                                label: const Text('ลองใหม่'),
                              )
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      // ✅ แก้ตรงนี้ - ใช้ Flexible + ConstrainedBox แทน LayoutBuilder
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 300,
                            maxHeight: 600,
                          ),
                          child: _filtered.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('ไม่พบรายการอุปกรณ์',
                                        style: TextStyle(
                                            color: AppColors.textSecondary)),
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 12, 12, 16),
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: _filtered.map((e) {
                                      final id = int.tryParse(
                                              e['EquipmentID']?.toString() ??
                                                  '') ??
                                          -1;
                                      final name =
                                          (e['EquipmentName'] ?? '').toString();
                                      final selected =
                                          _selectedIds.contains(id);

                                      return FilterChip(
                                        selected: selected,
                                        onSelected: (v) {
                                          setState(() {
                                            if (v) {
                                              _selectedIds.add(id);
                                            } else {
                                              _selectedIds.remove(id);
                                            }
                                          });
                                        },
                                        label: Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? Colors.white
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        avatar: Icon(
                                          selected
                                              ? Icons.check_circle_rounded
                                              : Icons.chair_alt_rounded,
                                          size: 18,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.primary,
                                        ),
                                        showCheckmark: false,
                                        selectedColor: AppColors.primary,
                                        backgroundColor:
                                            const Color(0xFFF3F8F6),
                                        pressElevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          side: BorderSide(
                                            color: selected
                                                ? AppColors.primary
                                                : AppColors.border,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                      );
                                    }).toList(),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}