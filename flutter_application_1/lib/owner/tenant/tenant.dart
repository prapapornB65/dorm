import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'package:flutter_application_1/widgets/page_header_card.dart';
import 'package:http/http.dart' as http;

enum TenantStatusFilter { all, active, ended }

class TenantListPage extends StatefulWidget {
  final int buildingId;
  final int ownerId;
  final String? buildingName;

  const TenantListPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    this.buildingName,
  });

  @override
  State<TenantListPage> createState() => _TenantListPageState();
}

class _TenantListPageState extends State<TenantListPage> {
  bool isLoading = true;
  String? errorMessage;

  List<dynamic> tenants = [];

  TenantStatusFilter _statusFilter = TenantStatusFilter.all;
  final TextEditingController _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTenants();
    _fetchTenantCount();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  int? _tenantCount;

  Future<void> _fetchTenantCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final uri = Uri.parse(
          '$apiBaseUrl/api/owner/building/${widget.buildingId}/tenant-count');
      
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _tenantCount = (j['count'] as num?)?.toInt());
    } catch (_) {
      if (!mounted) return;
      setState(() => _tenantCount = null);
    }
  }

  Future<void> _fetchTenants() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('กรุณาเข้าสู่ระบบก่อน');
      }
      
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('ไม่สามารถดึง Token ได้');
      }

      final params = <String>[];
      switch (_statusFilter) {
        case TenantStatusFilter.active:
          params.add('status=active');
          break;
        case TenantStatusFilter.ended:
          params.add('status=ended');
          break;
        case TenantStatusFilter.all:
          break;
      }
      final q = _searchCtl.text.trim();
      if (q.isNotEmpty) params.add('q=${Uri.encodeComponent(q)}');
      final qStr = params.isEmpty ? '' : '?${params.join('&')}';

      final tenantsUri = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/tenants$qStr',
      );

      final res = await http.get(
        tenantsUri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final raw = jsonDecode(res.body);
      
      // ✅ แก้ตรงนี้: เช็ค items, rows, หรือ array ตรงๆ
      final List<dynamic> list = (raw is List)
          ? raw
          : (raw is Map && raw['items'] is List)
              ? raw['items']
              : (raw is Map && raw['rows'] is List)
                  ? raw['rows']
                  : <dynamic>[];

      if (!mounted) return;
      setState(() => tenants = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _openEditDates(Map tenant) async {
    final tenantId = tenant['TenantID'] ?? tenant['tenantId'] ?? tenant['id'];
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบรหัสผู้เช่า')),
      );
      return;
    }

    DateTime? start = _parseDate(tenant['Start']);
    DateTime? end = _parseDate(tenant['End']);

    final result = await showDialog<(DateTime?, DateTime?)>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('แก้ไขช่วงสัญญาเช่า'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('เริ่มเช่า')),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: start ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setLocal(() => start = d);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(start == null ? 'เลือกวันที่' : _fmt(start)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('สิ้นสุด')),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: end ?? (start ?? DateTime.now()),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setLocal(() => end = d);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(end == null ? 'ไม่มีกำหนด' : _fmt(end)),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setLocal(() => end = null),
                  child: const Text('ลบวันสิ้นสุด'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                if (start == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('กรุณาเลือกวันเริ่มเช่า')),
                  );
                  return;
                }
                if (end != null && end!.isBefore(start!)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('วันสิ้นสุดต้องหลังวันเริ่ม')),
                  );
                  return;
                }
                Navigator.pop(ctx, (start, end));
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final (newStart, newEnd) = result;

    await _saveDates(tenantId, newStart!, newEnd);
    await _fetchTenants();
  }

  Future<void> _confirmEndTenancy(Map tenant) async {
    final tenantId = tenant['TenantID'] ?? tenant['tenantId'] ?? tenant['id'];
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบรหัสผู้เช่า')),
      );
      return;
    }

    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'เลือกวันย้ายออก',
    );
    if (chosen == null) return;

    await _endTenancy(tenantId, chosen);
    await _fetchTenants();
  }

  Future<void> _endTenancy(dynamic tenantId, DateTime endDate) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('กรุณาเข้าสู่ระบบก่อน');
      }
      
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('ไม่สามารถดึง Token ได้');
      }

      final url = Uri.parse('$apiBaseUrl/api/owner/tenants/$tenantId/end');
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'end': _fmt(endDate)}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('สิ้นสุดการเช่าสำเร็จ (ห้องถูกคืนเป็นว่าง)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ย้ายออกไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _saveDates(
      dynamic tenantId, DateTime start, DateTime? end) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('กรุณาเข้าสู่ระบบก่อน');
      }
      
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('ไม่สามารถดึง Token ได้');
      }

      final url = Uri.parse('$apiBaseUrl/api/owner/tenants/$tenantId/dates');
      final res = await http.patch(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'start': _fmt(start),
          'end': end == null ? null : _fmt(end),
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปเดตวันเช่าสำเร็จ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _fetchTenants,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            PageHeaderCard(
              leadingIcon: Icons.people_alt_rounded,
              title: 'ผู้เช่า ',
              chipText: '${tenants.length} คน',
              actions: [
                IconButton(
                  tooltip: 'รีโหลด',
                  onPressed: _fetchTenants,
                  icon: const Icon(Icons.refresh, color: AppColors.primaryDark),
                ),
              ],
            ),

            if (isLoading) ...[
              const SizedBox(height: 120),
              const _CenteredProgress(),
              const SizedBox(height: 300),
            ] else if (errorMessage != null) ...[
              _IllustratedMessage(
                icon: Icons.error_outline_rounded,
                iconColor: Colors.red,
                title: 'โหลดรายชื่อผู้เช่าไม่สำเร็จ',
                message: errorMessage!,
                action: TextButton.icon(
                  onPressed: _fetchTenants,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  DropdownButton<TenantStatusFilter>(
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem(
                          value: TenantStatusFilter.all,
                          child: Text('ทั้งหมด')),
                      DropdownMenuItem(
                          value: TenantStatusFilter.active,
                          child: Text('กำลังเช่า')),
                      DropdownMenuItem(
                          value: TenantStatusFilter.ended,
                          child: Text('สิ้นสุดการเช่า')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _statusFilter = v);
                      _fetchTenants();
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchCtl,
                      decoration: const InputDecoration(
                        hintText: 'ค้นหา (ชื่อ/อีเมล/เบอร์/เลขห้อง)',
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _fetchTenants(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() => _statusFilter = TenantStatusFilter.all);
                      _fetchTenants();
                    },
                    child: const Text('ล้างตัวกรอง'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (tenants.isEmpty)
                const NeumorphicCard(
                  padding: EdgeInsets.all(16),
                  child: Text('ยังไม่มีผู้เช่า',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                NeumorphicCard(
                  padding: const EdgeInsets.all(12),
                  child: _ApprovedTable(
                    items: tenants,
                    onEditDates: (t) => _openEditDates(t),
                    onEndTenancy: (t) => _confirmEndTenancy(t),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class _IllustratedMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Widget? action;

  const _IllustratedMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: iconColor),
          const SizedBox(height: 10),
          Text(title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _ApprovedTable extends StatelessWidget {
  final List items;
  final void Function(Map tenant) onEditDates;
  final void Function(Map tenant) onEndTenancy;
  const _ApprovedTable({
    required this.items,
    required this.onEditDates,
    required this.onEndTenancy,
  });

  bool _isActive(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    return s == 'active' || s == 'กำลังเช่า' || s == 'approved';
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '-';
    final d = (v is DateTime) ? v : DateTime.tryParse(v.toString());
    if (d == null) return '-';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  (String, Color) _tenantStatus(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    switch (s) {
      case 'active':
      case 'approved':
      case 'กำลังเช่า':
        return ('กำลังเช่า', Colors.green);
      case 'ended':
      case 'สิ้นสุดการเช่า':
        return ('สิ้นสุดการเช่า', Colors.redAccent);
      default:
        return (s.isEmpty ? '-' : s, Colors.blueGrey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 20,
              horizontalMargin: 12,
              headingRowColor: MaterialStateProperty.all(
                  AppColors.primary.withOpacity(0.06)),
              columns: const [
                DataColumn(label: Text('ห้อง')),
                DataColumn(label: Text('ชื่อ-สกุล')),
                DataColumn(label: Text('เบอร์โทร')),
                DataColumn(label: Text('อีเมล')),
                DataColumn(label: Text('เริ่มเช่า')),
                DataColumn(label: Text('สิ้นสุด')),
                DataColumn(label: Text('สถานะผู้เช่า')),
                DataColumn(label: Text('การจัดการ'))
              ],
              rows: items.map((t) {
                final room = t['RoomNumber']?.toString() ?? '-';
                final name = t['FullName'] ?? '-';
                final phone = t['Phone'] ?? '-';
                final email = t['Email'] ?? '-';

                final start = _fmtDate(t['Start']);
                final end =
                    t['End'] == null ? 'ไม่มีกำหนด' : _fmtDate(t['End']);
                final (label, color) = _tenantStatus(t['TenantStatus']);
                final isActive = _isActive(t['TenantStatus']);

                final underline =
                    const TextStyle(decoration: TextDecoration.underline);

                return DataRow(cells: [
                  DataCell(Text(room)),
                  DataCell(Text(name)),
                  DataCell(Text(phone)),
                  DataCell(Text(email)),
                  DataCell(
                    Text(start, style: underline),
                    onTap: () => onEditDates(Map<String, dynamic>.from(t)),
                  ),
                  DataCell(
                    Text(end, style: underline),
                    onTap: () => onEditDates(Map<String, dynamic>.from(t)),
                  ),
                  DataCell(_StatusChip(label: label, color: color)),
                  DataCell(
                    isActive
                        ? ElevatedButton.icon(
                            onPressed: () =>
                                onEndTenancy(Map<String, dynamic>.from(t)),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('ย้ายออก'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                          )
                        : const Text('-'),
                  ),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}