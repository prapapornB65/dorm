import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;


class RoomImagesPage extends StatefulWidget {
  final String roomNumber;
  const RoomImagesPage({super.key, required this.roomNumber});

  @override
  State<RoomImagesPage> createState() => _RoomImagesPageState();
}

class _RoomImagesPageState extends State<RoomImagesPage> {
  bool isLoading = true;
  List<String> images = [];
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchRoomImages();
  }

  Future<void> fetchRoomImages() async {
    final url =
        Uri.parse('$apiBaseUrl/api/room-images/${widget.roomNumber}');
    try {
      final res = await http.get(url);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        // เช็ค data เป็น List และแต่ละ item มี key 'ImageURL' หรือไม่
        if (data is List) {
          List<String> loadedImages = [];
          for (var item in data) {
            if (item is Map &&
                item.containsKey('ImageURL') &&
                item['ImageURL'] is String) {
              loadedImages.add(item['ImageURL']);
            }
          }
          setState(() {
            images = loadedImages;
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'ข้อมูลรูปภาพไม่ถูกต้อง';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'ไม่สามารถโหลดรูปภาพได้ (สถานะ: ${res.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'เกิดข้อผิดพลาด: $e';
        isLoading = false;
      });
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
        title: Text('รูปห้อง ${widget.roomNumber}'),
      ),
      body: Builder(
        builder: (context) {
          if (isLoading) {
            return const _CenteredProgress();
          }

          if (errorMessage != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: _IllustratedMessage(
                icon: Icons.error_outline_rounded,
                iconColor: Colors.red,
                title: 'โหลดรูปภาพไม่สำเร็จ',
                message: errorMessage!,
                action: TextButton.icon(
                  onPressed: fetchRoomImages,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ),
            );
          }

          if (images.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: _IllustratedMessage(
                icon: Icons.photo_library_outlined,
                iconColor: AppColors.textSecondary,
                title: 'ยังไม่มีรูปภาพสำหรับห้องนี้',
                message: 'กดปุ่มเพิ่มรูปภาพจากหน้าตั้งค่าห้องเพื่ออัปโหลด',
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: fetchRoomImages,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // ปรับจำนวนคอลัมน์ตามความกว้าง (responsive นิดๆ)
                final crossAxisCount = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 600
                        ? 3
                        : 2;

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final imageUrl = images[index];
                    return NeumorphicCard(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loading) {
                                if (loading == null) return child;
                                return const _ThumbLoading();
                              },
                              errorBuilder: (_, __, ___) => const _ThumbError(),
                            ),
                            // แถบข้อมูลเล็กๆ ด้านล่าง (ทินท์เขียวใส)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withOpacity(0.0),
                                      Colors.black.withOpacity(0.35),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Icon(Icons.zoom_out_map_rounded,
                                        size: 18, color: Colors.white70),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
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
        height: 44, width: 44,
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class _ThumbLoading extends StatelessWidget {
  const _ThumbLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight,
      child: const Center(
        child: SizedBox(
          height: 24, width: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ThumbError extends StatelessWidget {
  const _ThumbError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 36),
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
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
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

