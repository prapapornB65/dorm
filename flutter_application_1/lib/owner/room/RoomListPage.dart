import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/owner/room/RoomSettingsPage.dart';
import 'package:flutter_application_1/owner/room/room_images_page.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'AddRoomPage.dart';
import 'dart:async';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

class RoomListPage extends StatefulWidget {
  final int buildingId;
  const RoomListPage({super.key, required this.buildingId});

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  bool isLoading = true;
  List<Map<String, dynamic>> rooms = [];

  String? errorMessage;

  @override
  void initState() {
    super.initState();
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

  Future<void> deleteRoom(String roomNumber) async {
    final url = Uri.parse('$apiBaseUrl/api/rooms/$roomNumber'); // DELETE API

    try {
      final res = await http.delete(url);
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบห้องเรียบร้อย')),
        );
        fetchRooms();
      } else {
        throw Exception('ลบห้องไม่สำเร็จ');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('รายการห้องพัก'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'เพิ่มห้องพัก',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddRoomPage()),
              );
              if (result == true) {
                fetchRooms();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: fetchRooms,
        child: isLoading
            ? const _CenteredProgress()
            : errorMessage != null
                ? Padding(
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
                  )
                : rooms.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(18, 18, 18, 24),
                        child: _IllustratedMessage(
                          icon: Icons.meeting_room_outlined,
                          iconColor: AppColors.textSecondary,
                          title: 'ยังไม่มีข้อมูลห้องพัก',
                          message: 'กดปุ่ม + มุมขวาบนเพื่อเพิ่มห้องใหม่',
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                        child: NeumorphicCard(
                          padding: const EdgeInsets.all(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: constraints.maxWidth,
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dataTableTheme: DataTableThemeData(
                                        headingRowColor:
                                            MaterialStateProperty.all(
                                          AppColors.primaryLight,
                                        ),
                                        dataRowMinHeight: 52,
                                        dataRowMaxHeight: 68,
                                        headingTextStyle: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    child: DataTable(
                                      columnSpacing: 20,
                                      horizontalMargin: 12,
                                      columns: const [
                                        DataColumn(label: Text('เลขห้อง')),
                                        DataColumn(label: Text('ที่อยู่')),
                                        DataColumn(label: Text('สถานะ')),
                                        DataColumn(label: Text('ดูรูป')),
                                        DataColumn(label: Text('แก้ไข')),
                                        DataColumn(label: Text('ลบ')),
                                      ],
                                      rows: rooms.map((room) {
                                        // รองรับทั้ง bool / string
                                        bool isRoomAvailable = false;
                                        final st = room['status'];
                                        if (st is bool) {
                                          isRoomAvailable = st;
                                        } else {
                                          final s = st
                                              .toString()
                                              .trim()
                                              .toLowerCase();
                                          isRoomAvailable = (s == 'ว่าง') ||
                                              (s == 'available') ||
                                              (s == 'true');
                                        }

                                        final statusText = isRoomAvailable
                                            ? 'ว่าง'
                                            : 'ไม่ว่าง';
                                        final statusColor = isRoomAvailable
                                            ? AppColors.primary
                                            : Colors.red;

                                        final rn = (room['roomNumber'] ?? '')
                                            .toString()
                                            .trim();

                                        return DataRow(cells: [
                                          DataCell(Text(rn.isEmpty ? '-' : rn)),
                                          DataCell(Text(
                                              room['address']?.toString() ??
                                                  '-')),
                                          DataCell(_StatusChip(
                                              label: statusText,
                                              color: statusColor)),
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(Icons.image,
                                                  color: AppColors.textPrimary),
                                              tooltip: 'ดูรูปห้อง',
                                              onPressed: rn.isEmpty
                                                  ? null
                                                  : () =>
                                                      showRoomImages(rn), // ✅
                                            ),
                                          ),
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  color: Colors.orange),
                                              tooltip: 'แก้ไขห้อง',
                                              onPressed: rn.isEmpty
                                                  ? null
                                                  : () =>
                                                      openRoomSettings(rn), // ✅
                                            ),
                                          ),
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Colors.red),
                                              tooltip: 'ลบห้อง',
                                              onPressed: rn.isEmpty
                                                  ? null
                                                  : () async {
                                                      final confirmed =
                                                          await showDialog<
                                                              bool>(
                                                        context:
                                                            context, // ✅ ต้องใส่
                                                        builder: (ctx) =>
                                                            AlertDialog(
                                                          // ✅ ต้องใส่
                                                          title: const Text(
                                                              'ยืนยันการลบ'),
                                                          content: Text(
                                                              'คุณต้องการลบห้อง $rn ใช่หรือไม่?'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx,
                                                                      false),
                                                              child: const Text(
                                                                  'ยกเลิก'),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx,
                                                                      true),
                                                              child: const Text(
                                                                  'ลบ',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .red)),
                                                            ),
                                                          ],
                                                        ),
                                                      );

                                                      if (confirmed == true) {
                                                        await deleteRoom(rn);
                                                      }
                                                    },
                                            ),
                                          ),
                                        ]);
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
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
