import 'package:flutter/material.dart';
import 'package:flutter_application_1/owner/home/OwnerDashboard.dart';
import 'package:flutter_application_1/owner/building/AddBuilding.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart';

class BuildingSelectionScreen extends StatefulWidget {
  final int ownerId;

  const BuildingSelectionScreen({super.key, required this.ownerId});

  @override
  State<BuildingSelectionScreen> createState() =>
      _BuildingSelectionScreenState();
}

class _BuildingSelectionScreenState extends State<BuildingSelectionScreen> {
  List<Map<String, dynamic>> buildingList = [];
  bool isLoading = true;
  String? errorMessage; // <- ✨ เก็บข้อความ error ล่าสุด

  // ===== Helpers (debug) =====
  String _short(String s, [int max = 1200]) =>
      s.length <= max ? s : (s.substring(0, max) + '…(truncated)');

  String _platformHint() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  // ===== Lifecycle =====
  @override
  void initState() {
    super.initState();
    fetchBuildings();
  }

  Future<void> fetchBuildings() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final sw = Stopwatch()..start();
    final uid = FirebaseAuth.instance.currentUser;
    final token = await uid?.getIdToken(true); // ต่ออายุ token อัตโนมัติ

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // ลองยิงแบบ query ก่อน แล้วค่อย fallback เป็น path
    final uriPrimary =
        Uri.parse('$apiBaseUrl/api/buildings?ownerId=${widget.ownerId}');
    final uriFallback =
        Uri.parse('$apiBaseUrl/api/owners/${widget.ownerId}/buildings');

    Uri? usedUri;
    http.Response? resp;

    debugPrint(
        '🏁 [BUILDINGS] START fetch @${DateTime.now().toIso8601String()}');
    debugPrint('🧭 Platform: ${_platformHint()}   kIsWeb=$kIsWeb');
    debugPrint('⚙️  ownerId: ${widget.ownerId}');
    debugPrint('🔗 Try 1: $uriPrimary');

    try {
      // ===== Try #1
      usedUri = uriPrimary;
      resp = await http
          .get(usedUri, headers: headers)
          .timeout(const Duration(seconds: 12));

      // ถ้า 404/405/501 ลองเส้นทางสำรอง
      if (resp.statusCode == 404 ||
          resp.statusCode == 405 ||
          resp.statusCode == 501) {
        debugPrint('↪️  Fallback to $uriFallback (status=${resp.statusCode})');
        usedUri = uriFallback;
        resp = await http
            .get(usedUri, headers: headers)
            .timeout(const Duration(seconds: 12));
      }

      sw.stop();
      debugPrint('⏱️  DONE in ${sw.elapsedMilliseconds} ms');
      debugPrint('📥 status=${resp.statusCode}');
      debugPrint('📥 headers=${resp.headers}');
      debugPrint('📦 body.length=${resp.body.length}');
      debugPrint('📦 body.sample=${_short(resp.body)}');

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        setState(() {
          errorMessage = 'ไม่ได้รับอนุญาต (HTTP ${resp!.statusCode}).\n'
              '- ตรวจสอบการล็อกอินและสิทธิ์ owner\n'
              '- Token อาจหมดอายุ ลองออกเข้าใหม่';
          isLoading = false;
        });
        return;
      }

      if (resp.statusCode != 200) {
        setState(() {
          errorMessage =
              'HTTP ${resp!.statusCode}: ${resp.reasonPhrase ?? 'Unknown'}\nURL: $usedUri';
          isLoading = false;
        });
        return;
      }

      // ===== Parse JSON: รองรับ [{...}] หรือ {data:[...]}
      final dynamic decoded = jsonDecode(resp.body);
      final List<dynamic> rawList =
          (decoded is List) ? decoded : (decoded['data'] as List?) ?? [];

      // ===== Normalize keys
      final normalized = rawList.map<Map<String, dynamic>>((item) {
        final m = Map<String, dynamic>.from(item as Map);
        int? buildingId = m['buildingId'] ??
            m['BuildingID'] ??
            m['id'] ??
            int.tryParse('${m['BuildingID'] ?? ''}');
        String? buildingName =
            m['buildingName'] ?? m['BuildingName'] ?? m['name'];
        String? address = m['address'] ?? m['Address'];
        int? floors = m['floors'] ?? m['Floors'];
        int? rooms = m['rooms'] ?? m['Rooms'] ?? m['TotalRooms'];
        var ownerId = m['ownerId'] ?? m['OwnerID'] ?? m['owner'];
        String? qr = m['qrCodeUrl'] ?? m['QRCodeUrl'] ?? m['qr'];

        return {
          'buildingId': buildingId,
          'buildingName': buildingName,
          'address': address,
          'floors': floors,
          'rooms': rooms,
          'ownerId': ownerId,
          'icon': Icons.apartment,
          'qrCodeUrl': qr,
        };
      }).toList();

      // ===== ถ้า backend ยังไม่ filter → filter client-side เหมือนเดิม
      final filtered = normalized.where((item) {
        final a = '${item['ownerId']}';
        final b = '${widget.ownerId}';
        final keep = a == b;
        debugPrint('🔎 filter owner: item=$a vs required=$b -> $keep');
        return keep;
      }).toList();

      setState(() {
        buildingList = filtered;
        isLoading = false;
      });

      debugPrint('✅ RESULT count=${filtered.length}');
      debugPrint(
          '✅ RESULT sample=${filtered.isNotEmpty ? filtered.first : "<empty>"}');
    } on TimeoutException catch (e) {
      sw.stop();
      debugPrint('⛔ Timeout after ${sw.elapsedMilliseconds} ms: $e');
      setState(() {
        errorMessage =
            'เชื่อมต่อช้า/ไม่ตอบกลับ (timeout ${sw.elapsed.inSeconds}s)\n'
            '- ตรวจสอบว่าเซิร์ฟเวอร์รันอยู่ไหม\n'
            '- IP/พอร์ต $apiBaseUrl ถูกต้องไหม\n'
            '${kIsWeb ? "- ถ้าเป็นเว็บ อาจติด CORS ที่ backend\n" : ""}'
            'URL: ${usedUri ?? uriPrimary}';
        isLoading = false;
      });
    } on SocketException catch (e) {
      sw.stop();
      debugPrint('⛔ Network error: $e');
      setState(() {
        errorMessage =
            'เข้าถึง $apiBaseUrl ไม่ได้ (Network)\nURL: ${usedUri ?? uriPrimary}\nรายละเอียด: $e';
        isLoading = false;
      });
    } on FormatException catch (e) {
      sw.stop();
      debugPrint('⛔ JSON format error: $e');
      setState(() {
        errorMessage =
            'รูปแบบ JSON ไม่ถูกต้อง/ไม่ตรงที่คาด\nURL: ${usedUri ?? uriPrimary}\nลองดู log body.sample ด้านล่าง';
        isLoading = false;
      });
    } catch (e, st) {
      sw.stop();
      debugPrint('⛔ Unexpected error: $e');
      debugPrintStack(stackTrace: st);
      setState(() {
        errorMessage =
            'เกิดข้อผิดพลาดไม่ทราบสาเหตุ: $e\nURL: ${usedUri ?? uriPrimary}';
        isLoading = false;
      });
    }
  }

  void _editBuilding(Map<String, dynamic> building) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddBuildingScreen(
          ownerId: widget.ownerId,
          buildingToEdit: building,
        ),
      ),
    );
    if (result == true) {
      fetchBuildings();
    }
  }

  // ✅ ไปหน้าเพิ่มตึก และ refresh ถ้ามีการเพิ่มสำเร็จ
  Future<void> _navigateToAddBuilding() async {
    debugPrint('📥 Navigating to AddBuildingScreen...');
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AddBuildingScreen(ownerId: widget.ownerId)),
    );
    debugPrint('🔙 Returned from AddBuildingScreen with result: $result');

    if (result == true) {
      await fetchBuildings();
    }
  }

  void _goToDashboard(Map<String, dynamic> building) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerDashboardScreen(
          buildingName: building['buildingName'],
          buildingId: building['buildingId'],
          ownerId: widget.ownerId,
        ),
      ),
    );
  }

  // ===== Debug Info banner =====
  Widget _debugInfo() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber),
      ),
    );
  }

  // ===== UI =====
// ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        title: const Text(
          'เลือกตึก',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
        ),
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
            onPressed: fetchBuildings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.home_work_rounded,
                                color: AppColors.primaryDark, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'เลือกตึกของคุณ',
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Error state
                      if (errorMessage != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x11000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 8)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('เกิดข้อผิดพลาด',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(errorMessage!,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: fetchBuildings,
                                icon: const Icon(Icons.refresh),
                                label: const Text('ลองอีกครั้ง'),
                              ),
                            ],
                          ),
                        ),

                      // Empty
                      if (buildingList.isEmpty && errorMessage == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 8)),
                            ],
                          ),
                          child: Column(
                            children: const [
                              Text(
                                'ยังไม่มีตึกในระบบ',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 12),
                            ],
                          ),
                        ),

                      // Grid (ใช้ Wrap เช่นเดิม แต่ spacing ใหม่)
                      if (buildingList.isNotEmpty) ...[
                        Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            ...buildingList.map(
                              (b) => _BuildingTile(
                                name: b['buildingName'] ?? '-',
                                icon: b['icon'] as IconData? ?? Icons.apartment,
                                onTap: () => _goToDashboard(b),
                                onEdit: () => _editBuilding(b),
                              ),
                            ),
                            _AddTile(onTap: _navigateToAddBuilding),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// ---------------------- UI Pieces (design เท่านั้น) ----------------------

class _BuildingTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _BuildingTile({
    required this.name,
    required this.icon,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 180,
          height: 180,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // bubble gradient มุมขวาบน
              Positioned(
                right: -10,
                top: -10,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                    ),
                  ),
                ),
              ),
              // ปุ่มแก้ไข
              Positioned(
                right: 0,
                top: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.edit,
                        size: 16, color: AppColors.primaryDark),
                  ),
                ),
              ),
              // เนื้อหาไอคอน + ชื่อ
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.gradientStart,
                          AppColors.gradientEnd
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 180,
          height: 180,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _PlusBadge(),
              SizedBox(height: 12),
              Text(
                'เพิ่มตึก',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlusBadge extends StatelessWidget {
  const _PlusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.accent, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.add, color: Colors.white, size: 36),
    );
  }
}
