import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/owner/room/RoomSettingsPage.dart';
import 'package:flutter_application_1/owner/room/room_images_page.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'AddRoomPage.dart';
import 'dart:async';
import 'package:flutter_application_1/widgets/page_header_card.dart'; // NEW
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/config/api_config.dart'
    show apiBaseUrl; // ← ใส่คืน

// ---------- เพิ่ม helper สำหรับ auth header ----------
Future<Map<String, String>> _authHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  final token = await user?.getIdToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

class RoomListPage extends StatefulWidget {
  final int buildingId;
  final String? buildingName; // NEW (optional)

  const RoomListPage({super.key, required this.buildingId, this.buildingName});

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  bool isLoading = true;
  List<Map<String, dynamic>> rooms = [];
  String? errorMessage;

  // NEW: เก็บชื่ออาคาร
  String? _buildingName;

  @override
  void initState() {
    super.initState();
    _buildingName = widget.buildingName;
    if (_buildingName == null) _fetchBuildingName(); // ดึงจาก DB ถ้ายังไม่มี
    fetchRooms();
  }

  bool _busy = false;

  Future<void> fetchRooms() async {
    if (_busy) return; // ✅ กันยิงซ้ำ (เช่น เรียกจากหลายจุดพร้อมกัน)
    _busy = true;

    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final url = Uri.parse('$apiBaseUrl/api/rooms/${widget.buildingId}');
      final res =
          await http.get(url).timeout(const Duration(seconds: 10)); // ✅ กันค้าง

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final decoded = jsonDecode(res.body);

      final List list =
          decoded is List ? decoded : (decoded['data'] as List? ?? const []);
      final mapped = list
          .map<Map<String, dynamic>>((e) => {
                'roomNumber': e['roomNumber'] ?? e['RoomNumber'] ?? '',
                'address': e['address'] ?? e['Address'] ?? '',
                'status': e['status'] ?? e['Status'] ?? 'unknown',
                'size': (e['size'] ?? e['Size'] ?? 0).toString(),
                'capacity': e['capacity'] ?? e['Capacity'] ?? 0,
                'roomType': e['roomType'] ?? e['TypeName'] ?? '-',
                'price': e['price'] ?? e['PricePerMonth'] ?? 0,
                'deviceId': e['deviceId'] ?? e['DeviceID'],
              })
          .toList();

      if (!mounted) return;
      setState(() {
        rooms = mapped;
        errorMessage = null;
      });
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'การเชื่อมต่อช้า หรือเซิร์ฟเวอร์ตอบช้า (timeout)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      if (mounted)
        setState(() {
          isLoading = false;
        }); // ✅ ปิดโหลดเสมอ
      _busy = false;
    }
  }

  void showRoomImages(String roomNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomImagesPage(roomNumber: roomNumber),
      ),
    );
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.replaceAll(',', '').trim(); // กัน "3,000"
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.replaceAll(',', '').trim()) ?? 0;
    return 0;
  }

  // ใส่ใน _RoomListPageState
  final Map<String, String?> _thumbCache = {};
  final Map<String, Future<String?>> _thumbFutures = {};

  Future<String?> _fetchRoomThumb(String rn) {
    if (_thumbCache.containsKey(rn)) return Future.value(_thumbCache[rn]);
    if (_thumbFutures.containsKey(rn)) return _thumbFutures[rn]!;

    final fut = () async {
      try {
        final u =
            Uri.parse('$apiBaseUrl/api/room-images/${Uri.encodeComponent(rn)}');
        final res = await http.get(u).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return null;
        final data = jsonDecode(res.body);
        if (data is List && data.isNotEmpty) {
          // รองรับหลายคีย์ที่ backend อาจส่งมา
          final first = data.first;
          final url = (first['ImageURL'] ?? first['imageUrl'] ?? first['url'])
              ?.toString();
          _thumbCache[rn] = url;
          return url;
        }
        _thumbCache[rn] = null;
        return null;
      } catch (_) {
        _thumbCache[rn] = null;
        return null;
      } finally {
        _thumbFutures.remove(rn);
      }
    }();
    _thumbFutures[rn] = fut;
    return fut;
  }

  Future<bool> _confirmDelete(String rn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบห้อง $rn ใช่ไหม?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _fetchBuildingName() async {
    try {
      final u = Uri.parse('$apiBaseUrl/api/building/${widget.buildingId}');
      final r = await http.get(u).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      // รองรับหลายฟิลด์
      final name = (j['buildingName'] ??
              j['BuildingName'] ??
              j['name'] ??
              j['Name'] ??
              (j['data']?['buildingName']) ??
              (j['data']?['name']))
          ?.toString();
      if (name != null && name.isNotEmpty && mounted) {
        setState(() => _buildingName = name);
      }
    } catch (_) {/* เงียบ ๆ พอ */}
  }

  Future<void> openRoomSettings(String roomNumber) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomSettingsPage(roomNumber: roomNumber),
      ),
    );
    // Reload room list after returning from settings
    fetchRooms();
  }

  // ---------- แก้ฟังก์ชันลบให้แนบ token + encode ห้อง ----------
  Future<void> deleteRoom(String roomNumber) async {
    final encoded = Uri.encodeComponent(roomNumber.trim());
    final url = Uri.parse('$apiBaseUrl/api/rooms/$encoded'); // DELETE API

    try {
      final res = await http
          .delete(url, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 204) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบห้องเรียบร้อย')),
        );
        await fetchRooms();
        return;
      }

      // ดึงข้อความ error จาก backend ถ้ามี
      String detail = 'ลบห้องไม่สำเร็จ (HTTP ${res.statusCode})';
      try {
        final j = jsonDecode(res.body);
        final msg = (j['error'] ?? j['message'] ?? '').toString();
        if (msg.isNotEmpty) detail = msg;
      } catch (_) {}
      throw Exception(detail);
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('การเชื่อมต่อช้า (timeout)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: fetchRooms,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // กล่องหัวข้อสีขาว (ไม่มีปุ่มย้อนกลับ)
            PageHeaderCard(
              showBack: false, // <-- เอาปุ่มย้อนกลับออก
              leadingIcon: Icons.meeting_room_rounded,
              title: 'ห้องพัก ',
              chipText: '${rooms.length} ห้อง',
              actions: [
                IconButton(
                  tooltip: 'เพิ่มห้องพัก',
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddRoomPage(buildingId: widget.buildingId),
                      ),
                    );
                    if (result == true) {
                      await fetchRooms();
                    }
                  },
                  icon: const Icon(Icons.add, color: AppColors.primaryDark),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // เนื้อหาหลังหัวข้อ
            if (isLoading) ...[
              const _CenteredProgress(),
            ] else if (errorMessage != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: _IllustratedMessage(
                  icon: Icons.error_outline_rounded,
                  iconColor: Colors.red,
                  title: 'โหลดรายการห้องไม่สำเร็จ',
                  message: errorMessage!,
                  action: TextButton.icon(
                    onPressed: fetchRooms,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองอีกครั้ง'),
                  ),
                ),
              ),
            ] else if (rooms.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: _IllustratedMessage(
                  icon: Icons.meeting_room_outlined,
                  iconColor: AppColors.textSecondary,
                  title: 'ยังไม่มีข้อมูลห้องพัก',
                  message: 'กดปุ่ม + มุมขวาบนเพื่อเพิ่มห้องใหม่',
                ),
              ),
            ] else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  int cross = 2;
                  if (w >= 1200)
                    cross = 5;
                  else if (w >= 1024)
                    cross = 4;
                  else if (w >= 768) cross = 3;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: GridView.builder(
                      physics:
                          const NeverScrollableScrollPhysics(), // เลื่อนด้วย ListView แทน
                      shrinkWrap: true, // ให้ Grid อยู่ภายใน ListView
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: rooms.length,
                      itemBuilder: (_, i) {
                        final room = rooms[i];
                        final rn = (room['roomNumber'] ?? '').toString().trim();

                        bool isAvailable = false;
                        final st = room['status'];
                        if (st is bool) {
                          isAvailable = st;
                        } else {
                          final s = st.toString().trim().toLowerCase();
                          isAvailable = (s == 'ว่าง') ||
                              (s == 'available') ||
                              (s == 'true');
                        }
                        final statusText = isAvailable ? 'ว่าง' : 'ไม่ว่าง';
                        final statusColor =
                            isAvailable ? Colors.orange : AppColors.primary;

                        return _RoomCard(
                          roomNumber: rn.isEmpty ? '-' : rn,
                          statusText: statusText,
                          statusColor: statusColor,
                          thumbLoader:
                              rn.isEmpty ? null : () => _fetchRoomThumb(rn),
                          pricePerMonth:
                              _asDouble(room['price'] ?? room['PricePerMonth']),
                          roomType:
                              (room['roomType'] ?? room['TypeName'] ?? '-')
                                  .toString(),
                          sizeSqm: _asDouble(room['size'] ?? room['Size']),
                          capacity:
                              _asInt(room['capacity'] ?? room['Capacity']),
                          specialBadge:
                              (room['isOverdue'] == true) ? 'ค้างชำระ' : null,
                          onViewImages:
                              rn.isEmpty ? null : () => showRoomImages(rn),
                          onEdit:
                              rn.isEmpty ? null : () => openRoomSettings(rn),
                          onDelete: rn.isEmpty
                              ? null
                              : () async {
                                  if (await _confirmDelete(rn)) {
                                    await deleteRoom(rn);
                                  }
                                },
                        );
                      },
                    ),
                  );
                },
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
          Text(message,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.roomNumber,
    required this.statusText,
    required this.statusColor,
    this.thumbLoader,
    // NEW
    required this.pricePerMonth,
    required this.roomType,
    required this.sizeSqm,
    required this.capacity,
    this.specialBadge, // e.g. 'ค้างชำระ' | 'รอเข้าพัก' | 'ซ่อมบำรุง'
    // actions
    this.onViewImages,
    this.onEdit,
    this.onDelete,
  });

  final String roomNumber;
  final String statusText;
  final Color statusColor;
  final Future<String?> Function()? thumbLoader;

  // NEW fields
  final double pricePerMonth;
  final String roomType;
  final double sizeSqm;
  final int capacity;
  final String? specialBadge;

  final VoidCallback? onViewImages;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final priceStr =
        pricePerMonth <= 0 ? '—' : '฿${pricePerMonth.toStringAsFixed(0)}/เดือน';
    final typeStr = roomType.isEmpty ? '-' : roomType;
    final sizeStr = sizeSqm <= 0
        ? '—'
        : '${sizeSqm.toStringAsFixed(sizeSqm % 1 == 0 ? 0 : 1)} m²';
    final capStr = capacity <= 0 ? '—' : '$capacity คน';

    return NeumorphicCard(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          if (specialBadge != null && specialBadge!.isNotEmpty)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 6,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Text(
                  specialBadge!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
            ),

          // ───────────── การ์ดหลัก ─────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              color: Colors.white,
            ),
            child: Column(
              children: [
                // header
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        roomNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(.18),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: statusColor.withOpacity(.35)),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                              color: statusColor, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),

                // เนื้อหาที่เหลือให้ยืด/หดตามพื้นที่
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // รูป (ยืด-หดได้)
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: FutureBuilder<String?>(
                              future: thumbLoader?.call(),
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return Container(
                                    alignment: Alignment.center,
                                    color: Colors.black.withOpacity(.04),
                                    child: const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  );
                                }
                                final url = snap.data;
                                if (url == null || url.isEmpty) {
                                  return Container(
                                    color: Colors.black.withOpacity(.04),
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.image_not_supported_outlined,
                                            color: AppColors.textSecondary,
                                            size: 36),
                                        SizedBox(height: 6),
                                        Text('ยังไม่มีรูปห้อง',
                                            style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  );
                                }
                                return Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.black.withOpacity(.04),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textSecondary),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // chips: ราคา + ประเภท (เตี้ยลง และห่อคำได้)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(.7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                priceStr,
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(.06),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  typeStr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // meta + เมนู ⋮
                        Row(
                          children: [
                            const Icon(Icons.square_foot,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(sizeStr,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                            const SizedBox(width: 10),
                            const Icon(Icons.group,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text('รองรับ $capStr',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary)),
                            ),
                            const Spacer(),
                            _MoreMenu(
                              onViewImages: onViewImages,
                              onEdit: onEdit,
                              onDelete: onDelete,
                            ),
                          ],
                        ),
                      ],
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

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({this.onViewImages, this.onEdit, this.onDelete});
  final VoidCallback? onViewImages;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'เมนู',
      onSelected: (v) {
        switch (v) {
          case 'images':
            onViewImages?.call();
            break;
          case 'edit':
            onEdit?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
            value: 'images',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.image),
                title: Text('ดูรูปห้อง'))),
        const PopupMenuItem(
            value: 'edit',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.edit),
                title: Text('แก้ไขห้อง'))),
        const PopupMenuItem(
            value: 'delete',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('ลบห้อง'))),
      ],
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      ),
    );
  }
}
