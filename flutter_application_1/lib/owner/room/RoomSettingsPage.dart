import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'dart:io' as io;
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'dart:async';
import 'package:http/http.dart' as http;

class RoomSettingsPage extends StatefulWidget {
  final String roomNumber;
  const RoomSettingsPage({super.key, required this.roomNumber});

  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  bool isLoading = true;
  Map<String, dynamic>? roomData;

  final _formKey = GlobalKey<FormState>();
  final ImagePicker picker = ImagePicker();
  XFile? selectedImage;

  final addressController = TextEditingController();
  final capacityController = TextEditingController();
  final sizeController = TextEditingController();

  bool isAvailable = false;
  List<Map<String, dynamic>> roomImages = [];

  @override
  void initState() {
    super.initState();
    fetchRoomData(); // ✅ พอ
  }

  @override
  void dispose() {
    addressController.dispose();
    capacityController.dispose();
    sizeController.dispose();
    super.dispose();
  }

  Future<void> fetchRoomData() async {
    setState(() => isLoading = true);
    try {
      final url = Uri.parse(
          '$apiBaseUrl/api/room-detail/${Uri.encodeComponent(widget.roomNumber)}');
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 404) {
        // ไม่พบห้อง
        if (!mounted) return;
        setState(() => roomData = null);
        return;
      }
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final raw = jsonDecode(res.body);
      Map<String, dynamic> data;
      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
        data = Map<String, dynamic>.from(raw.first as Map);
      } else {
        throw const FormatException('room-detail: invalid JSON shape');
      }

      if (!mounted) return;
      setState(() {
        roomData = data;
        addressController.text =
            (data['Address'] ?? data['address'] ?? '').toString();
        capacityController.text =
            (data['Capacity'] ?? data['capacity'] ?? '').toString();
        sizeController.text = (data['Size'] ?? data['size'] ?? '').toString();

        final rawStatus =
            data['Status'] ?? data['status'] ?? data['isAvailable'];
        final statusStr = rawStatus is bool
            ? (rawStatus ? 'ว่าง' : 'ไม่ว่าง')
            : (rawStatus ?? '').toString().trim();
        isAvailable = statusStr == 'ว่าง' ||
            statusStr.toLowerCase() == 'available' ||
            rawStatus == true;
      });

      await fetchRoomImages();
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เชื่อมต่อนานเกินไป (timeout)')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('รูปแบบข้อมูลไม่ถูกต้อง: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดข้อมูลห้องล้มเหลว: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchRoomImages() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/room-images/${widget.roomNumber}');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final decoded = json.decode(res.body);

      final List list = decoded is List
          ? decoded
          : (decoded['data'] as List? ??
              decoded['images'] as List? ??
              decoded['rows'] as List? ??
              const []);

      if (!mounted) return;
      setState(() {
        roomImages = list
            .whereType<Map>() // กัน element null
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      debugPrint('Error fetching room images: $e');
    }
  }

  Future<void> saveRoomData() async {
    if (!_formKey.currentState!.validate()) return;

    final updateData = {
      'Address': addressController.text,
      'Capacity': int.tryParse(capacityController.text) ?? 0,
      'Size':
          double.tryParse(sizeController.text) ?? 0.0, // ← เปลี่ยนเป็น double
      'Status': isAvailable ? 'ว่าง' : 'ไม่ว่าง',
    };

    final url = Uri.parse('$apiBaseUrl/api/room-update/${widget.roomNumber}');
    try {
      final res = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลห้องเรียบร้อย')),
        );
      } else {
        throw Exception('Failed to update room');
      }
    } catch (e) {
      debugPrint('Error updating room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกข้อมูลล้มเหลว: $e')),
        );
      }
    }
  }

  Future<void> pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        selectedImage = pickedFile;
      });
    }
  }

  Future<void> uploadImage() async {
    if (selectedImage == null) return;

    final uri = Uri.parse('$apiBaseUrl/api/room-images');
    final request = http.MultipartRequest('POST', uri)
      ..fields['RoomNumber'] = widget.roomNumber
      ..fields['BuildingID'] = roomData?['BuildingID']?.toString() ?? '';

    try {
      if (kIsWeb) {
        final bytes = await selectedImage!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: selectedImage!.name,
          contentType: MediaType('image', 'jpeg'),
        ));
      } else {
        request.files.add(
            await http.MultipartFile.fromPath('image', selectedImage!.path));
      }

      final resp = await request.send().timeout(const Duration(seconds: 15));
      debugPrint('Upload status: ${resp.statusCode}');

      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('อัปโหลดรูปภาพสำเร็จ')));
        setState(() {
          selectedImage = null;
        });
        await fetchRoomImages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('อัปโหลดรูปภาพไม่สำเร็จ')));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดนานเกินไป (timeout)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปโหลด: $e')));
    }
  }

  Widget buildRoomImages() {
    if (roomImages.isEmpty) {
      return const Text('ยังไม่มีรูปภาพของห้องนี้');
    }

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: roomImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final img = (index >= 0 && index < roomImages.length)
              ? roomImages[index]
              : const <String, dynamic>{};
          final imageUrl =
              (img['ImageURL'] ?? img['imageUrl'] ?? '').toString().trim();

          if (imageUrl.isEmpty) {
            return const _ThumbError(); // ✅ ไม่คืน null
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 150,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _ThumbError(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        'RoomSettingsPage: isLoading=$isLoading roomData=${roomData != null} images=${roomImages.length} selectedImage=${selectedImage != null}');
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
        title: Row(
          children: [
            const Icon(Icons.settings, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ตั้งค่าห้องพัก ${widget.roomNumber}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      body: isLoading
          ? const _CenteredProgress()
          : roomData == null
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: _IllustratedMessage(
                    icon: Icons.meeting_room_outlined,
                    iconColor: AppColors.textSecondary,
                    title: 'ไม่พบข้อมูลห้อง',
                    message: 'ตรวจสอบเลขห้องหรือเชื่อมต่อเครือข่ายอีกครั้ง',
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        // ===== ข้อมูลพื้นฐาน =====
                        const _SectionTitle(title: 'ข้อมูลพื้นฐาน'),
                        const SizedBox(height: 10),
                        NeumorphicCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: addressController,
                                decoration: const InputDecoration(
                                  labelText: 'ที่อยู่',
                                  hintText: 'เช่น อาคาร/ชั้น/ซอย/ถนน',
                                ),
                                validator: (val) => (val == null || val.isEmpty)
                                    ? 'กรุณากรอกที่อยู่'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: capacityController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'จำนวนคนพักสูงสุด',
                                        hintText: 'เช่น 2',
                                      ),
                                      validator: (val) {
                                        final n = int.tryParse(val ?? '');
                                        return (n == null || n <= 0)
                                            ? 'กรุณากรอกจำนวนคนพักให้ถูกต้อง'
                                            : null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: sizeController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'ขนาด (ตร.ม.)',
                                        hintText: 'เช่น 28.5',
                                      ),
                                      validator: (val) {
                                        final n =
                                            double.tryParse((val ?? '').trim());
                                        return (n == null || n <= 0)
                                            ? 'กรุณากรอกขนาดให้ถูกต้อง'
                                            : null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('สถานะว่าง'),
                                value: isAvailable,
                                onChanged: (val) =>
                                    setState(() => isAvailable = val),
                                activeColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ===== รูปภาพห้อง =====
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            _SectionTitle(title: 'รูปภาพห้องพัก'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NeumorphicCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // แสดงรูปที่มีอยู่
                              roomImages.isEmpty
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        'ยังไม่มีรูปภาพของห้องนี้',
                                        style: TextStyle(
                                            color: AppColors.textSecondary),
                                      ),
                                    )
                                  : SizedBox(
                                      height: 150,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: roomImages.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 10),
                                        itemBuilder: (context, index) {
                                          final img = roomImages[index];
                                          final imageUrl = (img['ImageURL'] ??
                                                  img['imageUrl'] ??
                                                  '')
                                              .toString()
                                              .trim();

                                          if (imageUrl.isEmpty) {
                                            return const _ThumbError();
                                          }
                                          return ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.network(
                                              imageUrl,
                                              width: 150,
                                              height: 150,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const _ThumbError(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                              const SizedBox(height: 12),

                              // Preview รูปที่เพิ่งเลือก
                              selectedImage != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: kIsWeb
                                          ? Image.network(
                                              selectedImage!.path,
                                              height: 150,
                                              width: double.infinity,
                                              fit: BoxFit.contain,
                                            )
                                          : Image(
                                              image: FileImage(
                                                  io.File(selectedImage!.path)),
                                              height: 150,
                                              width: double.infinity,
                                              fit: BoxFit.contain,
                                            ),
                                    )
                                  : const Text(
                                      'ยังไม่ได้เลือกรูปภาพ',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),

                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: Row(
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: pickImage,
                                          icon: const Icon(Icons
                                              .add_photo_alternate_rounded),
                                          label: const Text('เลือกรูปภาพ'),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton.icon(
                                          onPressed: selectedImage != null
                                              ? uploadImage
                                              : () {},
                                          icon: const Icon(
                                              Icons.cloud_upload_rounded),
                                          label: const Text('อัปโหลดรูปภาพ'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        // ===== ปุ่มบันทึก =====
                        ElevatedButton.icon(
                          onPressed: saveRoomData,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('บันทึกข้อมูล'),
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44)),
                        ),
                      ],
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

class _ThumbError extends StatelessWidget {
  const _ThumbError();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.broken_image_outlined,
          color: AppColors.textSecondary, size: 36),
    );
  }
}

class _IllustratedMessage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;

  const _IllustratedMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
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
          child: const Icon(Icons.tune_rounded,
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
