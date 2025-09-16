// owner/home/approval_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// THEME / CONFIG
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

// ใช้เฉพาะโหมดหน้าเต็ม (ไม่ใช้ตอน embedded)
import 'package:flutter_application_1/auth/login_page.dart' hide AppColors;
import 'package:flutter_application_1/owner/building/building.dart'
    show BuildingSelectionScreen;

/// หน้าคำขอ/อนุมัติผู้เช่า
/// - ใช้ใน Dashboard: `embedded: true` (จะคืนเฉพาะเนื้อหา ไม่สร้าง Scaffold)
/// - ใช้แบบหน้าเต็ม:  `embedded: false` (ค่าดีฟอลต์)
class OwnerApprovalsPage extends StatefulWidget {
  final int ownerId;
  final int? buildingId;
  final String? buildingName;

  /// ถ้า true จะคืนเฉพาะเนื้อหา (ฝังในหน้าอื่น)
  final bool embedded;

  const OwnerApprovalsPage({
    super.key,
    required this.ownerId,
    this.buildingId,
    this.buildingName,
    this.embedded = false,
  });

  @override
  State<OwnerApprovalsPage> createState() => _OwnerApprovalsPageState();
}

class _OwnerApprovalsPageState extends State<OwnerApprovalsPage> {
  // ---------- state ----------
  String status = 'pending'; // pending | approved | rejected
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];
  String q = '';

  // ---------- helpers ----------
  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String _fmtDT(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$d/$m/$y $hh:$mm';
    } catch (_) {
      return '-';
    }
  }

  Uri _listUrl() {
    final qp = <String, String>{
      'status': status,
      'limit': '50',
      'offset': '0',
    };
    if (widget.buildingId != null) qp['buildingId'] = '${widget.buildingId}';
    if (q.isNotEmpty) qp['q'] = q;
    // ⬇️ ตัด ownerId ออก
    return Uri.parse('$apiBaseUrl/api/owner/approvals')
        .replace(queryParameters: qp);
  }

// (แนะนำ) แยก URL สำหรับ action ชัดๆ
  Uri _approveUrl(int id) =>
      Uri.parse('$apiBaseUrl/api/owner/approvals/$id/approve');
  Uri _rejectUrl(int id) =>
      Uri.parse('$apiBaseUrl/api/owner/approvals/$id/reject');

  Future<void> _fetch() async {
    safeSetState(() {
      loading = true;
      error = null;
    });
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final resp = await http
          .get(
            _listUrl(),
            headers: token == null ? {} : {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 401) {
        // token ไม่ผ่าน/หมดอายุ → กลับหน้า login
        if (!mounted) return;
        _logout();
        return;
      }

      if (resp.statusCode != 200) {
        safeSetState(() {
          error = 'HTTP ${resp.statusCode}: ${resp.reasonPhrase ?? "Unknown"}';
          loading = false;
        });
        return;
      }

      final decoded = jsonDecode(resp.body);
      final List list = decoded is List
          ? decoded
          : (decoded['items'] ?? decoded['data'] ?? const []);

      items = list.map<Map<String, dynamic>>((raw) {
        final m = Map<String, dynamic>.from(raw as Map);

        // ✅ เผื่อ Payload เป็น String JSON หรือเป็น Map อยู่แล้ว
        Map<String, dynamic> payload = {};
        final p = m['Payload'] ?? m['payload'];
        if (p is String) {
          try {
            payload = Map<String, dynamic>.from(jsonDecode(p));
          } catch (_) {}
        } else if (p is Map) {
          payload = Map<String, dynamic>.from(p);
        }

        // ✅ เลขห้อง: รองรับทุกชื่อ key และ fallback ไปที่ Payload
        final roomVal = m['roomNumber'] ??
            m['RoomNumber'] ??
            m['room'] ??
            payload['roomNumber'] ??
            payload['RoomNumber'] ??
            '-';

        // ✅ วันที่ยื่นคำขอ (เดิมใช้ requestedAt/createdAt แต่ฝั่ง DB ใช้ RequestDate)
        final requestedAtVal = m['requestedAt'] ??
            m['createdAt'] ??
            m['CreatedAt'] ??
            m['RequestDate'] ??
            m['requestDate'];

        // ✅ วันที่เข้าอยู่: รองรับหลายชื่อ และ fallback ไปที่ Payload
        final moveInVal = m['moveInDate'] ??
            m['MoveInDate'] ??
            m['startDate'] ??
            m['StartDate'] ??
            m['Start'] ??
            m['checkInDate'] ??
            payload['moveInDate'] ??
            payload['MoveInDate'] ??
            payload['startDate'] ??
            payload['StartDate'] ??
            payload['Start'] ??
            payload['checkInDate'];

        return {
          'id': m['id'] ?? m['ApprovalID'] ?? m['approvalId'],
          'tenantName': m['tenantName'] ??
              m['FullName'] ??
              '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim(),
          'room': roomVal,
          'building': m['buildingName'] ?? m['building'] ?? '-',
          'requestedAt': requestedAtVal,
          'moveInDate': moveInVal, // ✅ เก็บเพิ่ม
          'status': (m['status'] ?? status).toString().toLowerCase(),

          // สำหรับ popup รายละเอียด
          'approvedAt': m['ApprovedAt'] ?? m['approvedAt'] ?? m['approved_at'],
          'approverName': m['ApproverName'] ??
              m['approvedByName'] ??
              m['ApprovedByName'] ??
              m['approver'] ??
              m['ApprovedBy'],
          'approvalNote': m['Reason'] ?? m['approvalNote'] ?? m['note'],
        };
      }).toList();

      safeSetState(() => loading = false);
    } on TimeoutException {
      safeSetState(() {
        error = 'เชื่อมต่อช้า/ไม่ตอบกลับ (timeout)';
        loading = false;
      });
    } on SocketException catch (e) {
      safeSetState(() {
        error = 'เครือข่ายผิดพลาด: $e';
        loading = false;
      });
    } catch (e) {
      safeSetState(() {
        error = 'เกิดข้อผิดพลาด: $e';
        loading = false;
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ยืนยันอนุมัติ'),
        content:
            Text('อนุมัติคำขอของ ${item['tenantName']} ห้อง ${item['room']} ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('อนุมัติ')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken(true);
      final resp = await http.post(
        _approveUrl(item['id']),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติสำเร็จ')),
        );
        _fetch();
      } else if (resp.statusCode == 401) {
        _logout();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('อนุมัติไม่สำเร็จ: ${resp.statusCode} ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e')),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ปฏิเสธคำขอ'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'ใส่เหตุผล (เช่น เอกสารไม่ครบ / เลขห้องไม่ถูกต้อง)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, reasonController.text.trim()),
              child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (reason == null) return;

    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken(true);
      final resp = await http
          .post(
            _rejectUrl(item['id']),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'reason': reason}),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบคำขอแล้ว')),
        );
        _fetch();
      } else if (resp.statusCode == 401) {
        _logout();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('ปฏิเสธไม่สำเร็จ: ${resp.statusCode} ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e')),
      );
    }
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  // ---------- CONTENT ONLY (ใช้ทั้ง embedded/standalone) ----------
  Widget _content() {
    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header กล่องขาว
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: AppColors.primaryDark),
                      const SizedBox(width: 10),
                      Text(
                        'คำขอเข้าพัก • ${widget.buildingName ?? '—'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      if (widget.buildingId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Building ID: ${widget.buildingId}',
                            style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (error != null) _ErrorBanner(message: error!),

                // Tabs + Search
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(
                      label: 'รออนุมัติ',
                      selected: status == 'pending',
                      onTap: () => setState(() {
                        status = 'pending';
                        _fetch();
                      }),
                    ),
                    _StatusChip(
                      label: 'อนุมัติแล้ว',
                      selected: status == 'approved',
                      onTap: () => setState(() {
                        status = 'approved';
                        _fetch();
                      }),
                    ),
                    _StatusChip(
                      label: 'ปฏิเสธแล้ว',
                      selected: status == 'rejected',
                      onTap: () => setState(() {
                        status = 'rejected';
                        _fetch();
                      }),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => q = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'ค้นหา ชื่อ/ห้อง/ตึก',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),

                if (!loading && error == null)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: _filtered(items, q).map((e) {
                      final s = (e['status'] ?? '').toString();
                      return _ApprovalCard(
                        name: e['tenantName'] ?? '-',
                        room: e['room'] ?? '-',
                        building: e['building'] ?? '-',
                        requestedAt: _fmtDT(
                            e['requestedAt']?.toString()), // ✅ ฟอร์แมตแล้ว
                        moveIn: _fmtDT(
                            e['moveInDate']?.toString()), // ✅ เพิ่มบรรทัดนี้
                        status: s,
                        onApprove: s == 'pending' ? () => _approve(e) : null,
                        onReject: s == 'pending' ? () => _reject(e) : null,
                        onView: s != 'pending'
                            ? () => _showApprovalDetail(e)
                            : null,
                      );
                    }).toList(),
                  ),

                if (!loading && error == null && _filtered(items, q).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text('ไม่พบรายการ',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // โหมดฝังใน Dashboard: ไม่สร้าง Scaffold/Drawer/AppBar
      return _content();
    }

    // โหมดหน้าเต็ม (ถ้าเปิดตรง ๆ)
    final isWide = MediaQuery.of(context).size.width >= 1024;
    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: isWide
          ? null
          : Drawer(
              child: _SidebarContent(
                buildingName: widget.buildingName ?? 'หอของฉัน',
                selectedIndex: 4,
                onChooseBuilding: _goChooseBuilding,
                onLogout: _logout,
              ),
            ),
      appBar: AppBar(
        automaticallyImplyLeading: !isWide,
        centerTitle: true,
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        title: const Text('คำขอเข้าพัก / อนุมัติ',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            SizedBox(
              width: 250,
              child: _SidebarContent(
                buildingName: widget.buildingName ?? 'หอของฉัน',
                selectedIndex: 4,
                onChooseBuilding: _goChooseBuilding,
                onLogout: _logout,
              ),
            ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  // ---------- small utils ----------
  List<Map<String, dynamic>> _filtered(
      List<Map<String, dynamic>> data, String q) {
    if (q.isEmpty) return data;
    return data.where((m) {
      final hay =
          '${m['tenantName']} ${m['room']} ${m['building']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _showApprovalDetail(Map<String, dynamic> it) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('รายละเอียดการอนุมัติ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('ผู้เช่า', it['tenantName']?.toString() ?? '-'),
            _kv('ห้อง', it['room']?.toString() ?? '-'),
            _kv('สถานะ', it['status']?.toString() ?? '-'),
            _kv('วันที่ยื่น', _fmtDT(it['requestedAt']?.toString())),
            _kv('วันที่อนุมัติ', _fmtDT(it['approvedAt']?.toString())),
            _kv('ผู้อนุมัติ', it['approverName']?.toString() ?? '-'),
            if ((it['approvalNote'] ?? '').toString().isNotEmpty)
              _kv('หมายเหตุ', it['approvalNote'].toString()),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text('$k :',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  // nav helpers (ใช้เฉพาะโหมดหน้าเต็ม)
  void _goChooseBuilding() {
    if (widget.ownerId == 0) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => BuildingSelectionScreen(ownerId: widget.ownerId)),
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
      (_) => false,
    );
  }
}

/* -------------------- Sidebar / Chips / Cards / Error banner -------------------- */

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.buildingName,
    required this.selectedIndex, // 0..5
    required this.onChooseBuilding,
    required this.onLogout,
  });

  final String buildingName;
  final int selectedIndex;
  final VoidCallback onChooseBuilding;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.dashboard_rounded, 'ภาพรวม'),
      (Icons.people_alt_rounded, 'ผู้เช่า'),
      (Icons.payments_rounded, 'ชำระเงิน'),
      (Icons.tungsten_rounded, 'ค่าน้ำ/ไฟ'),
      (Icons.verified_rounded, 'อนุมัติ'),
      (Icons.home_work_rounded, 'เลือกตึก'),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.domain, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      buildingName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final (icon, label) = items[i];
                  final selected = i == selectedIndex;
                  return Material(
                    color: Colors.white.withOpacity(selected ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (label == 'เลือกตึก') {
                          onChooseBuilding();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'เมนู "$label" (กำลังอยู่ระหว่างเชื่อมโยง)')),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(icon, color: Colors.white),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(label,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (selected)
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  backgroundColor: Colors.white.withOpacity(.16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('ออกจากระบบ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final String name, room, building, requestedAt, status;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onView;
  final String? moveIn;

  const _ApprovalCard({
    required this.name,
    required this.room,
    required this.building,
    required this.requestedAt,
    required this.status,
    this.onApprove,
    this.onReject,
    this.onView,
    this.moveIn,
  });

  @override
  Widget build(BuildContext context) {
    final color = status == 'approved'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : AppColors.primary;

    final card = Container(
      width: 520,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd]),
            ),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text('ห้อง $room • $building',
                    style: const TextStyle(color: AppColors.textSecondary)),
                Text(
                  'ขอเมื่อ: $requestedAt',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                if ((moveIn ?? '').isNotEmpty) // ✅ แสดงวันที่เข้าอยู่ถ้ามี
                  Text(
                    'เข้าอยู่: ${moveIn!}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onApprove != null && onReject != null) ...[
            IconButton(
              tooltip: 'ปฏิเสธ',
              onPressed: onReject,
              icon: const Icon(Icons.close_rounded, color: Colors.red),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: onApprove,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(Icons.check_rounded),
              label: const Text('อนุมัติ'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withOpacity(.3)),
              ),
              child: Text(
                status == 'approved'
                    ? 'อนุมัติแล้ว'
                    : status == 'rejected'
                        ? 'ปฏิเสธแล้ว'
                        : status,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            if (onView != null)
              TextButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.info_outline),
                label: const Text('รายละเอียด'),
              ),
          ],
        ],
      ),
    );

    return onView == null
        ? card
        : InkWell(
            onTap: onView,
            borderRadius: BorderRadius.circular(16),
            child: card);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}
