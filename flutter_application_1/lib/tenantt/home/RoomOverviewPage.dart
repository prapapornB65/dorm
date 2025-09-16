import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../home/room_detail_page.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/utils/shared_prefs_helper.dart';
import 'package:flutter_application_1/config/api_config.dart';

/// ---------- Palette ----------
class AppColors {
  static const gradientStart = Color(0xFF0F6B54);
  static const gradientEnd = Color(0xFF57D2A3);

  static const primary = Color(0xFF2AAE84);
  static const primaryDark = Color(0xFF0E7A60);
  static const primaryLight = Color(0xFFE8F7F2);

  static const surface = Color(0xFFF2FAF7);
  static const card = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF10443B);
  static const textSecondary = Color(0xFF6A8F86);

  static const border = Color(0xFFE1F1EB);
  static const accent = Color(0xFFA7EAD8);
}

/// ---------- ViewModel จาก /api/tenant-room-detail/:tenantId ----------
class TenantRoomOverview {
  final String roomNumber;
  final String buildingName;
  final String tenantFullName;
  final String? startDate;
  final String? price;
  final String? maintenanceCost;
  final double? size;
  final String? status;
  final String? qrCodeUrl;

  TenantRoomOverview({
    required this.roomNumber,
    required this.buildingName,
    required this.tenantFullName,
    this.startDate,
    this.price,
    this.maintenanceCost,
    this.size,
    this.status,
    this.qrCodeUrl,
  });

  factory TenantRoomOverview.fromJson(Map<String, dynamic> j) {
    final t = j['tenant'] ?? {};
    // พาร์ส Size ให้เป็น double
    final rawSize = t['Size'];
    final parsedSize = (rawSize is num)
        ? rawSize.toDouble()
        : double.tryParse(rawSize?.toString() ?? '');

    return TenantRoomOverview(
      roomNumber: t['RoomNumber']?.toString() ?? '',
      buildingName: t['BuildingName']?.toString() ?? '-',
      tenantFullName: '${t['FirstName'] ?? ''} ${t['LastName'] ?? ''}'.trim(),
      startDate: t['Start']?.toString(),
      size: parsedSize, // << ใช้ double
      status: t['room_status']?.toString(),
      qrCodeUrl: t['QrCodeUrl']?.toString(),
      price: j['price']?.toString(),
      maintenanceCost: j['maintenanceCost']?.toString(),
    );
  }
}

/// ---------- Utils ----------
String formatDateOnly(String? rawDate) {
  if (rawDate == null) return '-';
  try {
    final date = DateTime.parse(rawDate);
    return DateFormat('dd MMM yyyy', 'th_TH').format(date);
  } catch (_) {
    return '-';
  }
}

Future<int?> _fallbackGetTenantIdFromUID() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final resp = await http
        .get(Uri.parse('$apiBaseUrl/api/user-role-by-uid/$uid'))
        .timeout(const Duration(seconds: 10));

    debugPrint(
        '[FALLBACK] /user-role-by-uid status=${resp.statusCode} body=${resp.body}');
    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['role'] == 'tenant' && j['userId'] != null) {
        final id = (j['userId'] as num).toInt();
        await SharedPrefsHelper.saveTenantId(id);
        return id;
      }
    }
  } catch (e) {
    debugPrint('[FALLBACK] error: $e');
  }
  return null;
}

/// ---------- Page ----------
class RoomOverviewPage extends StatefulWidget {
  const RoomOverviewPage({super.key});
  @override
  State<RoomOverviewPage> createState() => _RoomOverviewPageState();
}

class TenantMeter {
  final int id;
  final String deviceId;
  final String? name;
  final double creditKwh;
  final bool isCut;
  final double? thresholdLow;
  final double? thresholdCritical;

  TenantMeter({
    required this.id,
    required this.deviceId,
    this.name,
    required this.creditKwh,
    required this.isCut,
    this.thresholdLow,
    this.thresholdCritical,
  });

  factory TenantMeter.fromJson(Map<String, dynamic> j) => TenantMeter(
        id: (j['id'] ?? j['meter_id'] ?? j['MeterID']) is num
            ? (j['id'] ?? j['meter_id'] ?? j['MeterID']).toInt()
            : int.parse((j['id'] ?? j['meter_id'] ?? j['MeterID']).toString()),
        deviceId: (j['deviceId'] ?? j['DeviceID'] ?? j['tuya_device_id'] ?? '')
            .toString(),
        name: (j['name'] ?? j['display_name'] ?? j['room_no'])?.toString(),
        creditKwh:
            (j['credit_kwh'] ?? j['creditKwh'] ?? j['credit'] ?? 0).toDouble(),
        isCut: (j['is_cut'] ?? j['isCut'] ?? false) == true,
        thresholdLow: (j['threshold_low_kwh'] ?? j['thresholdLow']) == null
            ? null
            : (j['threshold_low_kwh'] ?? j['thresholdLow'] as num).toDouble(),
        thresholdCritical:
            (j['threshold_critical_kwh'] ?? j['thresholdCritical']) == null
                ? null
                : (j['threshold_critical_kwh'] ?? j['thresholdCritical'] as num)
                    .toDouble(),
      );

  String get stateLabel {
    if (isCut) return 'CUT';
    final low = thresholdLow ?? double.infinity;
    final crit = thresholdCritical ?? double.infinity;
    if (creditKwh <= (crit.isFinite ? crit : -1)) return 'CRITICAL';
    if (creditKwh <= (low.isFinite ? low : -1)) return 'LOW';
    return 'OK';
  }
}

class _RoomOverviewPageState extends State<RoomOverviewPage> {
  int? tenantId;
  int? ownerId;
  String? tenantName;

  TenantRoomOverview? overview; // ใช้แทน roomData เดิม
  String? roomNumber; // สำหรับโหลดรูป
  List<String> roomImages = [];

  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;
  bool isLoadingNotifications = true;

  List<TenantMeter> meters = [];
  bool isLoadingMeters = true;
  String? metersError;

  @override
  void initState() {
    super.initState();
    _loadTenantData();
  }

  // ===== Load tenant meters =====
  Future<void> fetchTenantMeters() async {
    setState(() {
      isLoadingMeters = true;
      metersError = null;
    });

    // เตรียม endpoint ที่จะลองเรียก
    final List<Uri> candidates = [];
    if (tenantId != null) {
      candidates
          .add(Uri.parse('$apiBaseUrl/tenant/meters')); // อ่านจาก JWT ก็ได้
      candidates.add(
          Uri.parse('$apiBaseUrl/tenant-meters/$tenantId')); // ระบุ tenantId
    }
    if (roomNumber != null && roomNumber!.isNotEmpty) {
      candidates.add(Uri.parse('$apiBaseUrl/room-meters/$roomNumber'));
      candidates.add(Uri.parse('$apiBaseUrl/meters?roomNumber=$roomNumber'));
    }
    if (candidates.isEmpty) {
      setState(() {
        isLoadingMeters = false;
        meters = [];
      });
      return;
    }

    // ถ้าต้องส่ง JWT header
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    final headers = idToken == null
        ? <String, String>{}
        : {'Authorization': 'Bearer $idToken'};

    List<dynamic>? rawList;
    for (final u in candidates) {
      try {
        final r = await http
            .get(u, headers: headers)
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body);
          if (body is List) {
            rawList = body;
            break;
          }
          if (body is Map && body['items'] is List) {
            rawList = body['items'];
            break;
          }
          if (body is Map && body['data'] is List) {
            rawList = body['data'];
            break;
          }
        }
      } catch (_) {/* ลอง endpoint ถัดไป */}
    }

    if (!mounted) return;

    if (rawList == null) {
      setState(() {
        isLoadingMeters = false;
        metersError = 'โหลดรายการมิเตอร์ไม่สำเร็จ';
        meters = [];
      });
      return;
    }

    final parsed = <TenantMeter>[];
    for (final e in rawList) {
      try {
        parsed.add(TenantMeter.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }

    setState(() {
      meters = parsed;
      isLoadingMeters = false;
    });
  }

  Future<void> _loadTenantData() async {
    final prefsId = await SharedPrefsHelper.getTenantId();
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('tenantName');
    final oid = prefs.getInt('ownerId') ?? 0;

    int? tenantIdLocal = prefsId;
    if (tenantIdLocal == null) {
      tenantIdLocal = await _fallbackGetTenantIdFromUID(); // fallback จาก UID
    }

    setState(() {
      tenantId = tenantIdLocal;
      tenantName = name;
      ownerId = oid;
    });

    debugPrint('🔎 tenantId=$tenantId tenantName=$tenantName ownerId=$ownerId');

    if (tenantId != null) {
      await fetchRoomOverviewByTenant();
      await fetchNotifications();
      await fetchRoomImages(); // ต้องได้ roomNumber มาก่อน
    }

    if (!mounted) return;
    setState(() {
      isLoading = false;
      isLoadingNotifications = false;
    });
  }

  // เรียกหลังได้ overview สำเร็จเท่านั้น
  Future<void> fetchRoomOverviewByTenant() async {
    if (tenantId == null) return;
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/tenant-room-detail/$tenantId'))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final vm = TenantRoomOverview.fromJson(j);
        setState(() {
          overview = vm;
          roomNumber = (vm.roomNumber).isNotEmpty ? vm.roomNumber : null;
        });

        // ✅ โหลดรูปเฉพาะเมื่อ roomNumber พร้อม
        if (roomNumber != null && roomNumber!.isNotEmpty) {
          // ไม่ await เพื่อไม่ให้ UI ค้าง
          unawaited(fetchTenantMeters());
          // แต่ถ้าอยาก await ก็ได้ จะเห็น loading นานหน่อย
          unawaited(fetchRoomImages());
        }
      } else {
        setState(() => overview = null);
      }
    } catch (e) {
      debugPrint('❌ fetchRoomOverviewByTenant error: $e');
      setState(() => overview = null);
    }
  }

  Future<void> fetchNotifications() async {
    if (tenantId == null) return;
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/notifications/$tenantId'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      } else {
        debugPrint('❌ Notification error: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ fetchNotifications error: $e');
    }
  }

  // Robust image fetch: guard + short timeout + retry + ไม่ทับ UI ถ้า widget dispose
  Future<void> fetchRoomImages() async {
    final rn = roomNumber;
    if (rn == null || rn.isEmpty) return;

    // ป้องกันยิงซ้ำ
    if (!mounted) return;

    // ลอง 2 ครั้ง ครั้งละ 5 วิ
    const tries = 2;
    for (int i = 1; i <= tries; i++) {
      try {
        final r = await http
            .get(Uri.parse('$apiBaseUrl/api/room-images/$rn'))
            .timeout(const Duration(seconds: 5));

        if (!mounted) return;

        if (r.statusCode == 200) {
          final List<dynamic> data = jsonDecode(r.body);
          final urls = List<String>.from(data.map((it) {
            final raw = (it['ImageURL'] as String? ?? '');
            if (raw.startsWith('http://localhost:3000')) {
              // แทน localhost ด้วย apiBaseUrl เพื่อให้มือถือเอื้อมถึง
              return raw.replaceFirst('http://localhost:3000', apiBaseUrl);
            }
            return raw;
          }).where((e) => e.isNotEmpty));

          setState(() => roomImages = urls);
          return; // ✅ สำเร็จ ออกเลย
        } else {
          debugPrint('❌ room-images $rn status=${r.statusCode}');
        }
      } on TimeoutException {
        debugPrint('⏱️ room-images $rn timeout (try $i/$tries)');
      } catch (e) {
        debugPrint('❌ room-images $rn error (try $i/$tries): $e');
      }
    }

    // มาถึงตรงนี้คือไม่สำเร็จ: ไม่ต้อง throw เพื่อไม่ทำให้หน้า Error — แสดง placeholder แทน
    if (mounted && roomImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('โหลดรูปไม่สำเร็จ จะแสดง placeholder แทน')),
      );
    }
  }

  /// ---------- Small UI helpers ----------
  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            "$label: ",
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const _GradientAppBar(title: 'ข้อมูลห้องพัก'),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : overview == null
              ? const _EmptyBox(text: 'ไม่พบข้อมูลห้องพัก')
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await fetchRoomOverviewByTenant(); // โหลด overview ใหม่
                    await fetchRoomImages(); // โหลดรูป (ต้องพึ่ง roomNumber)
                    await fetchNotifications(); // โหลดแจ้งเตือน
                    await fetchTenantMeters();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ชื่อหอพัก
                        Center(
                          child: Text(
                            overview!.buildingName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: .3,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // การ์ด: ข้อมูลผู้เช่า + ห้อง
                        _Card(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: AppColors.primaryLight,
                                child: const Icon(Icons.meeting_room,
                                    size: 26, color: AppColors.primaryDark),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "ห้อง ${overview!.roomNumber}",
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "ชื่อ ${overview!.tenantFullName}",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "เข้าเมื่อ ${formatDateOnly(overview!.startDate)}",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // การ์ด: รายละเอียดห้อง
                        _Card(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _CardTitle(
                                icon: Icons.info_outline,
                                title: 'รายละเอียดห้อง',
                              ),
                              const SizedBox(height: 16),

                              // รูปห้อง
                              SizedBox(
                                height: 190,
                                child: roomImages.isEmpty
                                    ? _ImagePlaceholder()
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: PageView.builder(
                                          itemCount: roomImages.length,
                                          itemBuilder: (context, i) =>
                                              Image.network(
                                            roomImages[i],
                                            fit: BoxFit.cover,
                                            loadingBuilder: (_, child, p) => p ==
                                                    null
                                                ? child
                                                : const Center(
                                                    child:
                                                        CircularProgressIndicator()),
                                            errorBuilder: (_, __, ___) =>
                                                _ImagePlaceholder(),
                                          ),
                                        ),
                                      ),
                              ),

                              const SizedBox(height: 16),

                              _detailRow(
                                  Icons.attach_money,
                                  "ค่าห้อง",
                                  overview!.price != null
                                      ? "${overview!.price} บาท"
                                      : "-"),
                              if (overview!.maintenanceCost != null)
                                _detailRow(Icons.settings, "ค่าส่วนกลาง",
                                    "${overview!.maintenanceCost} บาท"),
                              _detailRow(
                                  Icons.square_foot,
                                  "พื้นที่",
                                  overview!.size != null
                                      ? "${overview!.size} ตร.ม."
                                      : "-"),

                              const SizedBox(height: 16),

                              Align(
                                alignment: Alignment.centerRight,
                                child: _PrimaryButton(
                                  text: 'ดูเพิ่มเติม',
                                  onTap: () async {
                                    if (overview!.roomNumber.isEmpty) return;
                                    await SharedPrefsHelper.saveRoomNumber(
                                        overview!.roomNumber);
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        transitionDuration:
                                            const Duration(milliseconds: 240),
                                        pageBuilder: (_, a1, __) =>
                                            FadeTransition(
                                          opacity: a1,
                                          child: RoomDetailPage(
                                            roomNumber: overview!.roomNumber,
                                            // ให้หน้า detail โหลดเอง ไม่ต้องส่ง data
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // หัวข้อ
                        const SizedBox(height: 24),
                        const _SectionHeader(text: 'มิเตอร์ของห้อง'),
                        const SizedBox(height: 12),

// การ์ดรายการมิเตอร์
                        _Card(
                          padding: const EdgeInsets.all(20),
                          child: isLoadingMeters
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary))
                              : (metersError != null)
                                  ? Text(metersError!,
                                      style: const TextStyle(color: Colors.red))
                                  : (meters.isEmpty)
                                      ? const Text(
                                          'ยังไม่มีมิเตอร์ที่ผูกกับห้องนี้',
                                          style: TextStyle(
                                              color: AppColors.textSecondary))
                                      : Column(
                                          children: meters
                                              .map((m) => ListTile(
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            vertical: 6,
                                                            horizontal: 4),
                                                    leading: CircleAvatar(
                                                      backgroundColor: AppColors
                                                          .primaryLight,
                                                      child: Icon(
                                                          m.isCut
                                                              ? Icons.power_off
                                                              : Icons
                                                                  .electric_bolt,
                                                          color: AppColors
                                                              .primaryDark),
                                                    ),
                                                    title: Text(
                                                        m.name ?? m.deviceId,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    subtitle: Text(
                                                        'เครดิต ${m.creditKwh.toStringAsFixed(2)} kWh'),
                                                    trailing: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: m.isCut
                                                            ? Colors
                                                                .red.shade700
                                                            : (m.thresholdCritical !=
                                                                        null &&
                                                                    m.creditKwh <=
                                                                        m
                                                                            .thresholdCritical!)
                                                                ? Colors.orange
                                                                    .shade800
                                                                : (m.thresholdLow !=
                                                                            null &&
                                                                        m.creditKwh <=
                                                                            m
                                                                                .thresholdLow!)
                                                                    ? Colors
                                                                        .orange
                                                                        .shade600
                                                                    : AppColors
                                                                        .primary,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(m.stateLabel,
                                                          style:
                                                              const TextStyle(
                                                                  color: Colors
                                                                      .white)),
                                                    ),
                                                    onTap: () {
                                                      Navigator.pushNamed(
                                                          context,
                                                          '/tenant/purchase',
                                                          arguments: {
                                                            'meterId': m.id
                                                          });
                                                    },
                                                  ))
                                              .toList(),
                                        ),
                        ),

                        // การ์ด: แจ้งเตือน
                        const _SectionHeader(text: 'แจ้งเตือน'),
                        const SizedBox(height: 12),
                        if (isLoadingNotifications)
                          const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary))
                        else if (notifications.isEmpty)
                          const _EmptyBox(text: 'ไม่มีการแจ้งเตือน')
                        else
                          Column(
                            children: notifications.map((n) {
                              final unread = n['IsRead'] != true;
                              return _Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: const Icon(Icons.notifications,
                                        color: AppColors.primaryDark),
                                  ),
                                  title: Text(
                                    n['Title'] ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: (n['Message'] ?? '')
                                          .toString()
                                          .isEmpty
                                      ? null
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            n['Message'] ?? '',
                                            style: const TextStyle(
                                                color: AppColors.textSecondary),
                                          ),
                                        ),
                                  trailing: unread ? const _UnreadDot() : null,
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => _DialogCard(
                                        title: 'รายละเอียดแจ้งเตือน',
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n['Title'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              n['Message'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

/// ======================= Styled widgets =======================
class _GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _GradientAppBar({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
      ),
      backgroundColor: Colors.transparent,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryDark),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  const _Card({required this.child, this.padding, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  const _PrimaryButton({required this.text, required this.onTap});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: _down
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(.12),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
        ),
        child: Text(
          widget.text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Icon(Icons.image_not_supported,
            size: 48, color: AppColors.textSecondary),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Colors.redAccent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;
  const _EmptyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DialogCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _DialogCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.card,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          const Icon(Icons.notifications, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: child,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('ปิด', style: TextStyle(color: AppColors.primaryDark)),
        ),
      ],
    );
  }
}
