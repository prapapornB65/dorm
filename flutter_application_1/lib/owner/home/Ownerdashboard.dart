import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/owner/iot.dart/owner_meters_page.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

// PAGES
import 'package:flutter_application_1/auth/login_page.dart' hide AppColors;
import 'package:flutter_application_1/owner/money/monthly_income_page.dart';
import 'package:flutter_application_1/owner/building/building.dart'
    show BuildingSelectionScreen;
import 'package:flutter_application_1/owner/room/RoomListPage.dart';
import 'package:flutter_application_1/owner/iot.dart/owner_electric_page.dart';
import 'package:flutter_application_1/owner/tenant/tenant.dart';
import 'package:flutter_application_1/owner/money/payments_page.dart';
import 'package:flutter_application_1/owner/home/approval_page.dart'
    show OwnerApprovalsPage;
import 'package:flutter_application_1/owner/money/auto_billing_settings_page.dart';
import 'package:flutter_application_1/owner/money/monthly_expenses_page.dart';
import 'package:flutter_application_1/owner/equipment/equipment_catalog_page.dart';
import 'package:flutter_application_1/owner/equipment/repair_request_page.dart';
// THEME / CONFIG
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

// --- helpers: แปลงค่า dynamic -> double กันพังเวลาเป็น "0"/null ---
double asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

class OwnerDashboardScreen extends StatefulWidget {
  final String buildingName;
  final int buildingId;
  final int ownerId;

  const OwnerDashboardScreen({
    super.key,
    required this.buildingName,
    required this.buildingId,
    required this.ownerId,
  });

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  // ---- state ----
  bool isLoading = true;
  String? errorMessage;

  int tenantCount = 0;
  int roomCount = 0;
  double totalIncome = 0;
  int overdueRoomCount = 0;
  double totalElectric = 0;
  double totalWater = 0;
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  int selectedMenuIndex = 0; // 0: overview, 1: ผู้เช่า, 2: ชำระเงิน, 3: อนุมัติ
  List<dynamic> rooms = [];

  double currentMonthTotal = 0.0;
  List<Map<String, dynamic>> currentItems = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final url = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/monthly-income-detail'
        '?year=$selectedYear&month=$selectedMonth',
      );
      final res = await http.get(url, headers: await _authHeaders());
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (!mounted) return;
        setState(() {
          currentMonthTotal = (data['total'] as num?)?.toDouble() ?? 0.0;
          currentItems =
              List<Map<String, dynamic>>.from(data['items'] ?? const []);
        });
      } else {
        debugPrint('[DETAIL] HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[DETAIL] error: $e');
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await Future.wait([
        // ห้อง
        _fetchRoomData().timeout(const Duration(seconds: 12)).catchError((e) {
          debugPrint('[ROOMS] error: $e');
          errorMessage ??= 'โหลดข้อมูลห้องไม่สำเร็จ: $e';
        }),

        // รายรับเดือนนี้
        _fetchMonthlyIncome()
            .timeout(const Duration(seconds: 12))
            .catchError((e) {
          debugPrint('[INCOME] error: $e');
          errorMessage ??= 'โหลดข้อมูลรายรับไม่สำเร็จ: $e';
        }),

        // นับผู้เช่า (อิง /api/building/:id/tenant-count)
        fetchTenantCount().timeout(const Duration(seconds: 8)).catchError((e) {
          debugPrint('[TENANTS] error: $e'); // ไม่ต้องตั้ง errorMessage ก็ได้
        }),
      ]).timeout(const Duration(seconds: 18)); // timeout รวมทั้งชุด
    } on TimeoutException {
      errorMessage ??= 'โหลดข้อมูลช้าเกินไป (timeout 18s)';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchRoomData() async {
    final url = Uri.parse('$apiBaseUrl/api/owner/rooms/${widget.buildingId}');
    final sw = Stopwatch()..start();
    debugPrint('[ROOMS] GET $url');

    final res = await http
        .get(url, headers: await _authHeaders())
        .timeout(const Duration(seconds: 12));

    sw.stop();
    debugPrint(
        '[ROOMS] ${res.statusCode} in ${sw.elapsedMilliseconds}ms len=${res.body.length}');

    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final j = json.decode(res.body);
        final m = (j['error'] ?? j['message'])?.toString();
        if (m != null && m.isNotEmpty) msg = m;
      } catch (_) {}
      throw Exception(msg);
    }

    final decoded = json.decode(res.body);
    final list = (decoded is List) ? decoded : (decoded['data'] as List?) ?? [];
    rooms = List<Map<String, dynamic>>.from(
      list.map((e) => Map<String, dynamic>.from(e as Map)),
    );

    // นับเฉพาะจำนวนห้องจากรายการ
    roomCount = rooms.length;

    // ค่าอื่น ๆ ให้มาจาก endpoint เฉพาะ (เช่น tenant-count / summary)
    // หากยังไม่มีข้อมูล ก็ปล่อยค่าเริ่มต้นไว้
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _fetchMonthlyIncome() async {
    // ✅ ใช้ endpoint summary ที่ส่งเป็น { months: [{month, total}, ...] }
    final url = Uri.parse(
      '$apiBaseUrl/api/owner/building/${widget.buildingId}/monthly-income-summary?months=12',
    );
    final sw = Stopwatch()..start();
    debugPrint('[INCOME] GET $url');

    try {
      final res = await http
          .get(url, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));

      sw.stop();
      debugPrint(
          '[INCOME] ${res.statusCode} in ${sw.elapsedMilliseconds}ms len=${res.body.length}');

      if (res.statusCode != 200) {
        String msg = 'HTTP ${res.statusCode}';
        try {
          final j = json.decode(res.body);
          final m = (j['error'] ?? j['message'])?.toString();
          if (m != null && m.isNotEmpty) msg = m;
        } catch (_) {}
        throw Exception(msg);
      }

      // 👇 วาง 3 บรรทัดนี้ตรงนี้
      final data = json.decode(res.body);
      final months = (data['months'] as List?) ?? [];
      totalIncome = months.isNotEmpty ? asDouble(months.last['total']) : 0.0;
    } on TimeoutException {
      sw.stop();
      debugPrint('[INCOME] timeout in ${sw.elapsedMilliseconds}ms');
      totalIncome = 0;
      errorMessage ??= 'โหลดข้อมูลรายรับช้า (timeout)';
    } catch (e) {
      sw.stop();
      debugPrint('[INCOME] error: $e');
      totalIncome = 0;
      errorMessage ??= 'โหลดข้อมูลรายรับไม่สำเร็จ: $e';
    }
  }

  Future<void> fetchTenantCount() async {
    final url = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/tenant-count');

    try {
      final resp = await http
          .get(url, headers: await _authHeaders())
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (mounted) setState(() => tenantCount = (data['count'] ?? 0) as int);
      } else {
        // เงียบไว้ ใช้ค่าจาก rooms ต่อ
        debugPrint('[TENANT-COUNT] HTTP ${resp.statusCode}: ${resp.body}');
      }
    } on TimeoutException {
      debugPrint('[TENANT-COUNT] timeout');
    } catch (e) {
      debugPrint('[TENANT-COUNT] error: $e');
    }
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: isWide
          ? null
          : Drawer(
              child: _SidebarContent(
              buildingName: widget.buildingName,
              onSelectIndex: (i) => setState(() => selectedMenuIndex = i),
              onChooseBuilding: _goChooseBuilding,
              onGoApprovals: _goApprovalPage,
            )),
      appBar: AppBar(
        automaticallyImplyLeading: !isWide,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        title: const Text('แดชบอร์ดเจ้าของ',
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
            onPressed: _loadAll,
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
                buildingName: widget.buildingName,
                onSelectIndex: (i) => setState(() => selectedMenuIndex = i),
                onChooseBuilding: _goChooseBuilding,
                onGoApprovals: _goApprovalPage,
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: SizedBox.expand(
                // 👈 ให้ child มีขนาดเต็มพื้นที่เสมอ
                key: ValueKey(selectedMenuIndex),
                child: isLoading
                    ? const _Skeleton()
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: _ContentArea(
                          selectedIndex: selectedMenuIndex,
                          buildingName: widget.buildingName,
                          buildingId: widget.buildingId,
                          ownerId: widget.ownerId,
                          summary: _Summary(
                            tenantCount: tenantCount,
                            roomCount: roomCount,
                            totalIncome: totalIncome,
                            overdueRoomCount: overdueRoomCount,
                            totalElectric: totalElectric,
                            totalWater: totalWater,
                          ),
                          errorMessage: errorMessage,
                          onSeeRooms: () =>
                              setState(() => selectedMenuIndex = 1),
                          onSeeIncome: () =>
                              setState(() => selectedMenuIndex = 2),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goChooseBuilding() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => BuildingSelectionScreen(ownerId: widget.ownerId)),
    );
  }

  void _goApprovalPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerApprovalsPage(
          buildingId: widget.buildingId,
          ownerId: widget.ownerId,
          buildingName: widget.buildingName,
        ),
      ),
    );
  }
}

// ---------- Sidebar ----------
class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.buildingName,
    required this.onSelectIndex,
    required this.onChooseBuilding,
    required this.onGoApprovals,
  });

  final String buildingName;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onChooseBuilding;
  final VoidCallback onGoApprovals;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.dashboard_rounded, 'ภาพรวม'),
      (Icons.people_outline_rounded, 'ผู้ใช้ & ห้องพัก'),
      (Icons.account_balance_wallet, 'การเงิน'),
      (Icons.sensors_rounded, 'อุปกรณ์ & มิเตอร์'),
      (Icons.build_circle_rounded, 'งาน & ซ่อมบำรุง'),
      (Icons.settings_rounded, 'ตั้งค่า'),
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
            // Building card
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

            // Menu
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemBuilder: (context, i) {
                  final (icon, label) = items[i];
                  return _SideItem(
                    icon: icon,
                    label: label,
                    onTap: () {
                      if (label == 'เลือกตึก') {
                        onChooseBuilding();
                      } else {
                        onSelectIndex(i); // รวม 'อนุมัติ' ด้วย
                      }
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: items.length,
              ),
            ),

            // Logout
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
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => LoginPage()),
                    (route) => false,
                  );
                },
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

class _SideItem extends StatelessWidget {
  const _SideItem(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Content Area ----------
class _ContentArea extends StatelessWidget {
  const _ContentArea({
    required this.selectedIndex,
    required this.buildingName,
    required this.buildingId,
    required this.ownerId,
    required this.summary,
    required this.errorMessage,
    required this.onSeeRooms,
    required this.onSeeIncome,
  });

  final int selectedIndex;
  final String buildingName;
  final int buildingId;
  final int ownerId;
  final _Summary summary;
  final String? errorMessage;
  final VoidCallback onSeeRooms;
  final VoidCallback onSeeIncome;

  @override
  Widget build(BuildContext context) {
    final pages = [
      // 0) ภาพรวม
      _Overview(
        buildingName: buildingName,
        buildingId: buildingId,
        summary: summary,
        errorMessage: errorMessage,
        onSeeRooms: onSeeRooms,
        onSeeIncome: onSeeIncome,
      ),

      // 1) ผู้ใช้ & ห้องพัก  (แท็บ: ผู้เช่า / ห้องพัก / อนุมัติ)
      UsersRoomsHubPage(
        buildingId: buildingId,
        ownerId: ownerId,
        buildingName: buildingName,
      ),

      // 2) การเงิน (แท็บ: รายรับ / รายจ่าย / ชำระเงิน / ตัดยอดอัตโนมัติ)
      FinanceHubPage(
        buildingId: buildingId,
        ownerId: ownerId,
        buildingName: buildingName,
      ),

      // 3) อุปกรณ์ & มิเตอร์ (แท็บ: มิเตอร์ทั้งหมด/ค่าน้ำไฟ, คลังอุปกรณ์)
      DevicesHubPage(
        ownerId: ownerId,
        buildingId: buildingId,
        buildingName: buildingName,
      ),

      // 4) งาน & ซ่อมบำรุง (แท็บ: แจ้งซ่อม, ประวัติงาน)
      MaintenanceHubPage(
        ownerId: ownerId,
        buildingId: buildingId,
      ),

      // 5) ตั้งค่า (แท็บ: สลับตึก, เกณฑ์/อัตราค่าไฟน้ำ)
      SettingsHubPage(
        buildingId: buildingId,
        ownerId: ownerId,
        buildingName: buildingName,
        onChooseBuilding: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BuildingSelectionScreen(ownerId: ownerId),
            ),
          );
        },
      ),
    ];

    return pages[selectedIndex];
  }
}

class UsersRoomsHubPage extends StatelessWidget {
  const UsersRoomsHubPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    required this.buildingName,
  });
  final int buildingId, ownerId;
  final String buildingName;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: const [
          _HubHeader(
              icon: Icons.people_outline_rounded, title: 'ผู้ใช้ & ห้องพัก'),
          TabBar(tabs: [
            Tab(text: 'ผู้เช่า'),
            Tab(text: 'ห้องพัก'),
            Tab(text: 'อนุมัติ'),
          ]),
          SizedBox(height: 8),
          Expanded(
            child: _UsersRoomsTabs(),
          ),
        ],
      ),
    );
  }
}

class FinanceHubPage extends StatelessWidget {
  const FinanceHubPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    required this.buildingName,
  });
  final int buildingId, ownerId;
  final String buildingName;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: const [
          _HubHeader(icon: Icons.account_balance_wallet, title: 'การเงิน'),
          TabBar(tabs: [
            Tab(text: 'รายรับ/เดือน'),
            Tab(text: 'รายจ่าย/เดือน'),
            Tab(text: 'ชำระเงิน'),
            Tab(text: 'ตัดยอดอัตโนมัติ'),
          ]),
          SizedBox(height: 8),
          Expanded(child: _FinanceTabs()),
        ],
      ),
    );
  }
}

class _FinanceTabs extends StatelessWidget {
  const _FinanceTabs();

  @override
  Widget build(BuildContext context) {
    final args = context.findAncestorWidgetOfExactType<FinanceHubPage>()!;
    return TabBarView(
      children: [
        MonthlyIncomePage(
            buildingId: args.buildingId, buildingName: args.buildingName),
        MonthlyExpensesPage(
            buildingId: args.buildingId,
            ownerId: args.ownerId,
            buildingName: args.buildingName),
        PaymentsPage(
            buildingId: args.buildingId,
            ownerId: args.ownerId,
            buildingName: args.buildingName),
        AutoBillingSettingsPage(buildingId: args.buildingId),
      ],
    );
  }
}

class DevicesHubPage extends StatelessWidget {
  const DevicesHubPage({
    super.key,
    required this.ownerId,
    required this.buildingId,
    required this.buildingName,
  });
  final int ownerId, buildingId;
  final String buildingName;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const _HubHeader(
              icon: Icons.sensors_rounded, title: 'อุปกรณ์ & มิเตอร์'),
          const TabBar(tabs: [
            Tab(text: 'ค่าน้ำ-ค่าไฟ'),
            Tab(text: 'มิเตอร์'),
            Tab(text: 'คลังอุปกรณ์'),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                OwnerElectricPage(
                  ownerId: ownerId,
                  buildingId: buildingId,
                  buildingName: buildingName,
                ),
                OwnerMetersPage(
                  buildingId: buildingId,
                ),
                OwnerEquipmentPage(ownerId: ownerId, buildingId: buildingId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MaintenanceHubPage extends StatelessWidget {
  const MaintenanceHubPage(
      {super.key, required this.ownerId, required this.buildingId});
  final int ownerId, buildingId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          _HubHeader(
              icon: Icons.build_circle_rounded, title: 'งาน & ซ่อมบำรุง'),
          TabBar(tabs: [
            Tab(text: 'แจ้งซ่อม'),
            Tab(text: 'ประวัติงาน'),
          ]),
          SizedBox(height: 8),
          Expanded(child: _MaintenanceTabs()),
        ],
      ),
    );
  }
}

class _MaintenanceTabs extends StatelessWidget {
  const _MaintenanceTabs();

  @override
  Widget build(BuildContext context) {
    final args = context.findAncestorWidgetOfExactType<MaintenanceHubPage>()!;
    return TabBarView(
      children: [
        RepairRequestPage(ownerId: args.ownerId, buildingId: args.buildingId),
        // Placeholder ประวัติ (เติมภายหลัง)
        Center(child: Text('ประวัติงาน (เร็ว ๆ นี้)')),
      ],
    );
  }
}

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    required this.buildingName,
    required this.onChooseBuilding,
  });
  final int buildingId, ownerId;
  final String buildingName;
  final VoidCallback onChooseBuilding;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          _HubHeader(icon: Icons.settings_rounded, title: 'ตั้งค่า'),
          TabBar(tabs: [
            Tab(text: 'สลับตึก'),
            Tab(text: 'อัตรา/เกณฑ์ไฟ-น้ำ'),
          ]),
          SizedBox(height: 8),
          Expanded(child: _SettingsTabs()),
        ],
      ),
    );
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs();

  @override
  Widget build(BuildContext context) {
    final args = context.findAncestorWidgetOfExactType<SettingsHubPage>()!;
    return TabBarView(children: [
      BuildingSelectionScreen(ownerId: args.ownerId),
      AutoBillingSettingsPage(buildingId: args.buildingId),
    ]);
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontSize: 18)),
        ],
      ),
    );
  }
}

class _UsersRoomsTabs extends StatelessWidget {
  const _UsersRoomsTabs();

  @override
  Widget build(BuildContext context) {
    final args = context.findAncestorWidgetOfExactType<UsersRoomsHubPage>()!;
    return TabBarView(
      children: [
        TenantListPage(
          buildingId: args.buildingId,
          ownerId: args.ownerId,
          buildingName: args.buildingName,
        ),
        RoomListPage(buildingId: args.buildingId),
        OwnerApprovalsPage(
          ownerId: args.ownerId,
          buildingId: args.buildingId,
          buildingName: args.buildingName,
          embedded: true,
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.buildingName,
    required this.buildingId,
    required this.summary,
    required this.errorMessage,
    required this.onSeeRooms,
    required this.onSeeIncome,
  });

  final String buildingName;
  final int buildingId;
  final _Summary summary;
  final String? errorMessage;
  final VoidCallback onSeeRooms;
  final VoidCallback onSeeIncome;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
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
                    const Icon(Icons.dashboard_customize_rounded,
                        color: AppColors.primaryDark),
                    const SizedBox(width: 10),
                    Text('ภาพรวม • $buildingName',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            fontSize: 18)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Building ID: $buildingId',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (errorMessage != null) _ErrorBanner(message: errorMessage!),

              // KPI
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _KpiCard(
                      value: '${summary.tenantCount}',
                      label: 'ผู้เช่าทั้งหมด',
                      icon: Icons.people_alt_rounded),
                  _KpiCard(
                      value: '${summary.roomCount}',
                      label: 'ห้องทั้งหมด',
                      icon: Icons.meeting_room_rounded,
                      onTap: onSeeRooms),
                  _KpiCard(
                      value: summary.totalIncome.toStringAsFixed(2),
                      label: 'รายรับ/เดือน',
                      icon: Icons.attach_money_rounded,
                      onTap: onSeeIncome),
                  _KpiCard(
                      value: '${summary.overdueRoomCount}',
                      label: 'ค้างชำระ/ห้อง',
                      icon: Icons.warning_amber_rounded),
                  _KpiCard(
                      value: summary.totalElectric.toStringAsFixed(2),
                      label: 'ค่าไฟ/เดือน',
                      icon: Icons.bolt_rounded),
                  _KpiCard(
                      value: summary.totalWater.toStringAsFixed(2),
                      label: 'ค่าน้ำ/เดือน',
                      icon: Icons.opacity_rounded),
                ],
              ),

              const SizedBox(height: 22),

              // Analytics row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Flexible(
                      child: _AnalyticsCard(
                          title: 'สถิติรายสัปดาห์',
                          subtitle: 'ภาพรวมการเงิน',
                          icon: Icons.show_chart_rounded)),
                  SizedBox(width: 18),
                  Flexible(
                      child: _AnalyticsCard(
                          title: 'ประวัติธุรกรรม',
                          subtitle: 'เดือนปัจจุบัน',
                          icon: Icons.pie_chart_rounded)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.value, required this.label, this.onTap, this.icon});
  final String value;
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 214,
      height: 124,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: Stack(
        children: [
          // bubble
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd]),
              ),
              child: Icon(icon ?? Icons.insights_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.0)),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 8,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.primary]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return onTap != null
        ? InkWell(
            borderRadius: BorderRadius.circular(18), onTap: onTap, child: card)
        : card;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

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
            child: Text(message,
                style: const TextStyle(color: Colors.red, height: 1.2)),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _AnalyticsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 👈 สำคัญ: อย่าบังคับให้สูงสุด
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.primaryDark, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 🔧 แทน Expanded ด้วยกล่องสูงคงที่แบบยืดหยุ่นหลวม ๆ
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryLight, Colors.white],
                ),
              ),
              child: const Text(
                '(Mock Graph Placeholder)',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderCenter extends StatelessWidget {
  const _PlaceholderCenter({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget box({double h = 18, double w = double.infinity, double r = 10}) =>
        Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.04),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          box(h: 56, r: 16),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: List.generate(6, (_) => box(h: 124, w: 214, r: 18)),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: Row(
              children: [
                Expanded(child: box(r: 20)),
                const SizedBox(width: 18),
                Expanded(child: box(r: 20)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------- small data holder ----------
class _Summary {
  final int tenantCount;
  final int roomCount;
  final double totalIncome;
  final int overdueRoomCount;
  final double totalElectric;
  final double totalWater;

  const _Summary({
    required this.tenantCount,
    required this.roomCount,
    required this.totalIncome,
    required this.overdueRoomCount,
    required this.totalElectric,
    required this.totalWater,
  });
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
