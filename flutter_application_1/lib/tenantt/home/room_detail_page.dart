import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/tenantt/models/room_item.dart';
import 'package:flutter_application_1/tenantt/service/ContactOwnerPage.dart';
import 'package:flutter_application_1/utils/shared_prefs_helper.dart'; // ถ้ายังไม่มี import นี้

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

class RoomDetail {
  final String roomNumber;
  final String buildingName;
  final String status;
  final String roomType;
  final String price;
  final double size;
  final int capacity;
  final String address;
  final String? imageUrl;
  final List<String> equipments;

  RoomDetail({
    required this.roomNumber,
    required this.buildingName,
    required this.status,
    required this.roomType,
    required this.price,
    required this.size,
    required this.capacity,
    required this.address,
    required this.equipments,
    this.imageUrl,
  });

  factory RoomDetail.fromJson(Map<String, dynamic> j) {
    // Size robust
    final rawSize = j['Size'];
    final parsedSize = (rawSize is num)
        ? rawSize.toDouble()
        : double.tryParse(rawSize?.toString() ?? '0') ?? 0.0;

    // Equipments robust (strings หรือ list ของ map)
    List<String> parseEquipments() {
      final candidates = [
        j['EquipmentList'], // จาก /room-detail
        j['equipments'], // กันเคสอื่น
        j['equipmentList'], // กันพิมพ์เล็ก
      ];
      for (final c in candidates) {
        if (c is List) {
          return c
              .map<String>((e) {
                if (e is String) return e.trim();
                if (e is Map) {
                  final n = e['EquipmentName'] ??
                      e['equipmentName'] ??
                      e['name'] ??
                      e['equipment'];
                  return (n ?? '').toString().trim();
                }
                return '';
              })
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
      return const <String>[];
    }

    return RoomDetail(
      roomNumber: j['RoomNumber']?.toString() ?? '',
      buildingName: j['BuildingName']?.toString() ?? '-',
      status: j['Status']?.toString() ?? '-',
      roomType: (j['RoomType'] ?? j['TypeName'])?.toString() ?? '',
      price: (j['Price'] ?? j['PricePerMonth'])?.toString() ?? '0',
      size: parsedSize,
      capacity: int.tryParse('${j['Capacity'] ?? 0}') ?? 0,
      address: j['Address']?.toString() ?? '',
      imageUrl: j['FirstImageURL'] ?? j['ImageURL'],
      equipments: parseEquipments(),
    );
  }
}

class RoomDetailPage extends StatefulWidget {
  final String roomNumber;

  /// ✅ ทำให้ `data` ไม่บังคับ เพื่อแก้ error "required data"
  final RoomItem? data;

  const RoomDetailPage({
    super.key,
    required this.roomNumber,
    this.data,
  });

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  late Future<RoomDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<RoomDetail> _load() async {
    final uri = Uri.parse('$apiBaseUrl/api/room-detail01/${widget.roomNumber}');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));

      // 🔎 DEBUG: status / headers / body บางส่วน
      debugPrint('[ROOM-DETAIL] GET $uri -> ${res.statusCode}');
      debugPrint('[ROOM-DETAIL] headers: ${res.headers}');
      // ตัด body ให้สั้นลงถ้ายาว
      final bodyPreview =
          res.body.length > 600 ? '${res.body.substring(0, 600)}…' : res.body;
      debugPrint('[ROOM-DETAIL] body: $bodyPreview');

      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint('[ROOM-DETAIL] keys: ${raw.keys.toList()}');
        debugPrint('[ROOM-DETAIL] _debug: ${raw['_debug']}');
        debugPrint(
            '[ROOM-DETAIL] EquipmentList: ${raw['EquipmentList']} (${(raw['EquipmentList'] as List?)?.length ?? 0})');
        return RoomDetail.fromJson(raw);
      } else {
        debugPrint('[ROOM-DETAIL] non-200: ${res.body}');
      }
    } catch (e, st) {
      debugPrint('❌ [ROOM-DETAIL] API error: $e');
      debugPrint('↳ stack: $st');
    }

    // ---- Fallback เฉพาะกรณี API ใช้ไม่ได้จริง ๆ ----
    final d = widget.data;
    if (d != null) {
      return RoomDetail(
        roomNumber: d.roomNumber,
        buildingName: d.buildingName,
        status: d.status,
        roomType: d.roomType,
        price: d.price,
        size: (d.size is num)
            ? (d.size as num).toDouble()
            : double.tryParse('${d.size}') ?? 0.0,
        capacity: d.capacity,
        address: d.address ?? '',
        // ยอมว่าง เพราะไม่มีข้อมูลจาก API
        equipments: const [],
        imageUrl: d.imageUrl,
      );
    }

    throw Exception('โหลดรายละเอียดห้องไม่สำเร็จ');
  }

  String fmtSize(double v) {
    // 25.0 -> "25", 25.5 -> "25.50"
    return (v == v.roundToDouble())
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: FutureBuilder<RoomDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              message: snap.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snap.data!;
          final isVacant = data.status == 'ว่าง' ||
              data.status.toLowerCase().contains('available');
          final statusColor = isVacant ? AppColors.primary : Colors.redAccent;

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 240,
                    backgroundColor: AppColors.primary,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsetsDirectional.only(
                          start: 16, bottom: 12),
                      title: Text(
                        'ห้อง ${data.roomNumber}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Hero(
                            tag: 'room:${data.roomNumber}',
                            child: data.imageUrl == null
                                ? Container(color: AppColors.primaryLight)
                                : Image.network(data.imageUrl!,
                                    fit: BoxFit.cover),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.gradientStart,
                                  AppColors.gradientEnd
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _PriceBadge(text: '${data.price} บาท/เดือน'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(Icons.apartment,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        data.buildingName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _Pill(
                                bg: statusColor.withOpacity(.12),
                                border: BorderSide(
                                    color: statusColor.withOpacity(.6)),
                                child: Text(
                                  data.status,
                                  style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _InfoChip(
                                  icon: Icons.king_bed, label: data.roomType),
                              _InfoChip(
                                  icon: Icons.square_foot,
                                  label: '${fmtSize(data.size)} ตร.ม.'),
                              _InfoChip(
                                  icon: Icons.people_alt,
                                  label: 'รองรับ ${data.capacity} คน'),
                              if (data.address.isNotEmpty)
                                _InfoChip(
                                    icon: Icons.location_on,
                                    label: data.address),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _SectionTitle('อุปกรณ์ภายในห้อง'),
                          const SizedBox(height: 10),
                          _CardContainer(
                            child: data.equipments.isEmpty
                                ? const Text('—',
                                    style: TextStyle(
                                        color: AppColors.textSecondary))
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: data.equipments
                                        .map((e) => _Chip(text: e))
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // CTA ลอย
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _PrimaryButton(
                  text: 'ติดต่อเจ้าของ',
                  onTap: () async {
                    final tenantId = await SharedPrefsHelper
                        .getTenantId(); // อาจเป็น null ได้
                    if (!mounted) return;

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ContactOwnerPage(
                          tenantId: tenantId, // int? ได้
                          roomNumber: widget.roomNumber, // โชว์ใน title ได้
                          buildingName:
                              data.buildingName, // ใช้โชว์ subtitle ได้
                        ),
                      ),
                    );
                  },
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

// ===================== Pieces =====================

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  final Color bg;
  final BorderSide? border;
  const _Pill({required this.child, required this.bg, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.fromBorderSide(border!) : null,
      ),
      child: child,
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final String text;
  const _PriceBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  final Widget child;
  const _CardContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
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
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
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
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }
}
