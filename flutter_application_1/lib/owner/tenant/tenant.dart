import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'package:flutter_application_1/owner/home/approval_page.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

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

  // ทั้งหมด / กลุ่มรออนุมัติ / กลุ่มอนุมัติแล้ว
  List<dynamic> tenants = [];
  List<dynamic> pendingTenants = [];
  List<dynamic> approvedTenants = [];

  @override
  void initState() {
    super.initState();
    _fetchTenants();
  }

  Future<void> _fetchTenants() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final tenantsUri =
        Uri.parse('$apiBaseUrl/api/building/${widget.buildingId}/tenants');
    final pendingUri = Uri.parse(
      '$apiBaseUrl/api/owner/${widget.ownerId}/approvals'
      '?status=pending&buildingId=${widget.buildingId}&limit=50',
    );

    List _safeParseList(dynamic raw) {
      if (raw is List) return raw;
      if (raw is Map) {
        final rows = raw['rows'] ?? raw['data'] ?? raw['items'];
        return rows is List ? rows : const [];
      }
      return const [];
    }

    http.Response? tenantsRes;
    http.Response? pendingRes;

    try {
      debugPrint('[TENANT] GET $tenantsUri');
      debugPrint('[PENDING] GET $pendingUri');

      // ยิงพร้อมกัน + ใส่ timeout
      final tenantsF =
          http.get(tenantsUri).timeout(const Duration(seconds: 10));
      final pendingF = http.get(pendingUri).timeout(const Duration(seconds: 3));

      try {
        tenantsRes = await tenantsF;
      } catch (e) {
        debugPrint('[TENANT] $e');
      }
      try {
        pendingRes = await pendingF;
      } catch (e) {
        debugPrint('[PENDING] $e');
      }

      List allTenants = [];
      if (tenantsRes != null && tenantsRes!.statusCode == 200) {
        allTenants = _safeParseList(jsonDecode(tenantsRes!.body));
        debugPrint('[TENANT] 200 items=${allTenants.length}');
      } else if (tenantsRes != null) {
        debugPrint(
            '[TENANT] HTTP ${tenantsRes!.statusCode}: ${tenantsRes!.body}');
      }

      List pendings = [];
      if (pendingRes != null && pendingRes!.statusCode == 200) {
        pendings = _safeParseList(jsonDecode(pendingRes!.body));
        debugPrint('[PENDING] 200 items=${pendings.length}');
      } else if (pendingRes != null) {
        debugPrint(
            '[PENDING] HTTP ${pendingRes!.statusCode}: ${pendingRes!.body}');
      }

      if (!mounted) return;
      setState(() {
        tenants = allTenants;
        approvedTenants = allTenants;
        pendingTenants = pendings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted)
        setState(() => isLoading = false); // ✅ ปิดโหลดไม่ว่าอะไรจะเกิดขึ้น
      debugPrint(
          'TenantList build: loading=$isLoading, error=$errorMessage, all=${tenants.length}, pending=${pendingTenants.length}');
    }
  }

  // ====== Navigation ไปหน้าอนุมัติทั้งหมด ======
  void _goToApprovals() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerApprovalsPage(
          ownerId: widget.ownerId,
          buildingId: widget.buildingId, // ถ้า constructor รองรับ
          buildingName: widget.buildingName, // ถ้า constructor รองรับ
        ),
      ),
    );
  }

  // ====== อนุมัติ / ปฏิเสธ จากลิสต์บนสุด (รออนุมัติ) ======
  Future<void> _approveFromList(Map t) async {
    try {
      final approvalId = t['ApprovalID'];
      if (approvalId == null) throw Exception('ไม่พบรหัสคำขอ');

      final url = Uri.parse(
        '$apiBaseUrl/api/owner/${widget.ownerId}/approvals/$approvalId/approve',
      );

      final resp = await http.put(url);
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติแล้ว')),
        );
        _fetchTenants();
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  Future<void> _rejectFromList(Map t) async {
    try {
      final approvalId = t['ApprovalID'];
      if (approvalId == null) throw Exception('ไม่พบรหัสคำขอ');

      final url = Uri.parse(
        '$apiBaseUrl/api/owner/${widget.ownerId}/approvals/$approvalId/reject',
      );

      // ใส่เหตุผลเพิ่มได้
      final resp = await http.put(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'reason': 'ไม่ผ่านการตรวจสอบข้อมูล'}));

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ปฏิเสธแล้ว')),
        );
        _fetchTenants();
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'TenantList build: loading=$isLoading, error=$errorMessage, all=${tenants.length}, pending=${pendingTenants.length}');
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('รายชื่อผู้เช่า'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีโหลด',
            onPressed: _fetchTenants,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _fetchTenants,
        child: Builder(builder: (_) {
          if (isLoading) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                _CenteredProgress(),
                SizedBox(height: 400),
              ],
            );
          }
          if (errorMessage != null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                _IllustratedMessage(
                  icon: Icons.error_outline_rounded,
                  iconColor: Colors.red,
                  title: 'โหลดรายชื่อผู้เช่าไม่สำเร็จ',
                  message: errorMessage!,
                ),
                SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _fetchTenants,
                  icon: Icon(Icons.refresh),
                  label: Text('ลองอีกครั้ง'),
                ),
              ],
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              // ====== คำขอรออนุมัติ ======
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _SectionTitle(title: 'คำขอรออนุมัติ'),
                  TextButton.icon(
                    onPressed: _goToApprovals,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('ดูทั้งหมด'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (pendingTenants.isEmpty)
                const NeumorphicCard(
                  padding: EdgeInsets.all(16),
                  child: Text('ไม่มีคำขอใหม่',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                Column(
                  children: pendingTenants.take(5).map((t) {
                    final name = (t['FullName'] ??
                            '${t['FirstName'] ?? ''} ${t['LastName'] ?? ''}')
                        .toString()
                        .trim();
                    return _PendingTenantTile(
                      name: name.isEmpty ? 'ไม่ทราบชื่อ' : name,
                      room: t['RoomNumber']?.toString() ?? '-',
                      phone: t['Phone']?.toString() ?? '-',
                      onApprove: () => _approveFromList(t as Map),
                      onReject: () => _rejectFromList(t as Map),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 22),

              // ====== ผู้เช่าทั้งหมด ======
              const _SectionTitle(title: 'ผู้เช่าทั้งหมด'),
              const SizedBox(height: 10),

              if (approvedTenants.isEmpty)
                const NeumorphicCard(
                  padding: EdgeInsets.all(16),
                  child: Text('ยังไม่มีผู้เช่าที่อนุมัติแล้ว',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                NeumorphicCard(
                  padding: const EdgeInsets.all(12),
                  child: _ApprovedTable(items: approvedTenants),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/* ===================== Widgets ย่อย ===================== */

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

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.people_alt_rounded,
              color: AppColors.primaryDark, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _PendingTenantTile extends StatelessWidget {
  final String name;
  final String room;
  final String phone;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingTenantTile({
    required this.name,
    required this.room,
    required this.phone,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), // 👈 ใช้ตรงนี้แทน margin
      child: NeumorphicCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('ห้อง $room • $phone',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text('ปฏิเสธ',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: onApprove,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.check_circle),
              label: const Text('อนุมัติ',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedTable extends StatelessWidget {
  final List items;
  const _ApprovedTable({required this.items});

  (String, Color) _roomStatus(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    switch (s) {
      case 'occupied':
      case 'ไม่ว่าง':
      case 'มีผู้เข้าพัก':
        return ('มีผู้เข้าพัก', Colors.green);
      case 'vacant':
      case 'ว่าง':
        return ('ว่าง', Colors.orange);
      case 'repair':
      case 'ซ่อมบำรุง':
        return ('ซ่อมบำรุง', Colors.redAccent);
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
              headingRowColor:
                  MaterialStateProperty.all(AppColors.primaryLight),
              columns: const [
                DataColumn(label: Text('ชื่อ-สกุล')),
                DataColumn(label: Text('ห้อง')),
                DataColumn(label: Text('เบอร์โทร')),
                DataColumn(label: Text('อีเมล')),
                DataColumn(label: Text('สถานะห้อง')),
              ],
              rows: items.map((t) {
                final name = t['FullName'] ?? '-';
                final room = t['RoomNumber']?.toString() ?? '-';
                final phone = t['Phone'] ?? '-';
                final email = t['Email'] ?? '-';
                final (label, color) = _roomStatus(t['Status']);

                return DataRow(cells: [
                  DataCell(Text(name)),
                  DataCell(Text(room)),
                  DataCell(Text(phone)),
                  DataCell(Text(email)),
                  DataCell(_StatusChip(label: label, color: color)),
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
