import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'dart:async';


class AddRoomPage extends StatefulWidget {
  const AddRoomPage({super.key});

  @override
  State<AddRoomPage> createState() => _AddRoomPageState();
}

class _AddRoomPageState extends State<AddRoomPage> {
  final _formKey = GlobalKey<FormState>();
  final roomNumberController = TextEditingController();
  final capacityController = TextEditingController();
  final sizeController = TextEditingController();

  final houseNo = TextEditingController();
  final moo = TextEditingController();
  final subDistrict = TextEditingController();
  final district = TextEditingController();
  final province = TextEditingController();
  final postalCode = TextEditingController();

  String? selectedStatus;
  String? selectedRoomTypeId;
  String? selectedBuildingId;
  List<String> selectedEquipmentIds = [];
  List<File> selectedImages = [];
  List<Uint8List> selectedImageBytes = [];

  List roomTypes = [];
  List buildings = [];
  List equipments = [];

  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    fetchDropdownData();
  }
  
  // กัน memory leak
  @override
  void dispose() {
    roomNumberController.dispose();
    capacityController.dispose();
    sizeController.dispose();
    houseNo.dispose();
    moo.dispose();
    subDistrict.dispose();
    district.dispose();
    province.dispose();
    postalCode.dispose();
    super.dispose();
  }

  Future<void> fetchDropdownData() async {
    try {
      final rt = await http.get(Uri.parse('$apiBaseUrl/api/room-types'));
      final bld = await http.get(Uri.parse('$apiBaseUrl/api/buildings'));
      final eq = await http.get(Uri.parse('$apiBaseUrl/api/equipments'));

      if (rt.statusCode == 200 &&
          bld.statusCode == 200 &&
          eq.statusCode == 200) {
        setState(() {
          roomTypes = json.decode(rt.body);
          buildings = json.decode(bld.body);
          equipments = json.decode(eq.body);

          if (roomTypes.isNotEmpty) {
            selectedRoomTypeId = roomTypes[0]['RoomTypeID'].toString();
          }
          if (buildings.isNotEmpty) {
            selectedBuildingId = buildings[0]['BuildingID'].toString();
          }
        });
      }
    } catch (e) {
      print('Error fetching dropdown data: $e');
    }
  }

  Future<void> pickImages() async {
    final picked = await picker.pickMultiImage();
    // อ่าน bytes จากแต่ละไฟล์ที่เลือกมา
    List<Uint8List> bytesList = [];
    for (var file in picked) {
      final bytes = await file.readAsBytes();
      bytesList.add(bytes);
    }

    setState(() {
      selectedImages = picked.map((e) => File(e.path)).toList();
      selectedImageBytes = bytesList;
    });
  }

  Future<void> submitRoom() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ 1) กัน null + parse ให้เรียบร้อยก่อน
    if (selectedRoomTypeId == null || selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกประเภทห้องและตึก')),
      ); // หลังเพิ่มห้องและอัปโหลดรูปสำเร็จ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เพิ่มห้องสำเร็จ')),
      );
      Navigator.pop(context, true); // ✅ ส่ง true กลับ

      return;
    }
    final roomTypeId = int.tryParse(selectedRoomTypeId!);
    final buildingId = int.tryParse(selectedBuildingId!);
    if (roomTypeId == null || buildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ข้อมูลประเภทห้อง/ตึกไม่ถูกต้อง')),
      );
      return;
    }

    // ✅ 2) กันค่าว่าง/ผิดรูปแบบของตัวเลขที่กรอก
    final capacity = int.tryParse(capacityController.text);
    final size = double.tryParse(sizeController.text);
    if (capacity == null || size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('กรุณากรอกความจุ/ขนาดเป็นตัวเลขให้ถูกต้อง')),
      );
      return;
    }

    // ✅ 3) address
    final address =
        '${houseNo.text} หมู่ ${moo.text} ต.${subDistrict.text} อ.${district.text} จ.${province.text} ${postalCode.text}';

    // ✅ 4) ส่งข้อมูลห้อง โดยใช้ตัวแปรที่ parse แล้ว
    final roomRes = await http.post(
      Uri.parse('$apiBaseUrl/api/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'RoomNumber': roomNumberController.text,
        'Address': address,
        'Capacity': capacity,
        'Size': size,
        'Status': selectedStatus ?? 'available',
        'RoomTypeID': roomTypeId,
        'BuildingID': buildingId,
        'EquipmentIDs': selectedEquipmentIds
            .map((e) => int.tryParse(e))
            .whereType<int>()
            .toList(),
      }),
    );

    if (roomRes.statusCode == 200 || roomRes.statusCode == 201) {
      // ✅ 5) อัปโหลดรูป — backend ตอนนี้รับ single('image'), field = 'image'
      //    และใช้ชื่อฟิลด์ RoomNumber / BuildingID (ตัวใหญ่)
      if (selectedImages.isNotEmpty) {
        for (final imageFile in selectedImages) {
          final req = http.MultipartRequest(
            'POST',
            Uri.parse('$apiBaseUrl/api/room-images'),
          );
          req.fields['RoomNumber'] = roomNumberController.text;
          req.fields['BuildingID'] = buildingId.toString();
          req.files
              .add(await http.MultipartFile.fromPath('image', imageFile.path));

          final resp = await req.send();
          if (resp.statusCode != 200 && resp.statusCode != 201) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ')),
            );
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เพิ่มห้องสำเร็จ')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึกห้อง')),
      );
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        selectedImageBytes.add(bytes);
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
        title: const Text('เพิ่มห้องพัก'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ===== ส่วน: รายละเอียดห้อง =====
                    const _SectionTitle(title: 'รายละเอียดห้อง'),
                    const SizedBox(height: 10),
                    NeumorphicCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: roomNumberController,
                            decoration: const InputDecoration(
                              labelText: 'เลขห้อง',
                              hintText: 'เช่น A101',
                            ),
                            validator: (val) => (val == null || val.isEmpty)
                                ? 'กรุณากรอกเลขห้อง'
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
                                    labelText: 'ความจุ',
                                    hintText: 'จำนวนผู้อยู่อาศัย',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: sizeController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'ขนาด (ตร.ม.)',
                                    hintText: 'เช่น 28',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedStatus,
                            decoration:
                                const InputDecoration(labelText: 'สถานะ'),
                            items: ['ว่าง', 'ไม่ว่าง']
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => selectedStatus = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedRoomTypeId,
                            decoration:
                                const InputDecoration(labelText: 'ประเภทห้อง'),
                            items: roomTypes
                                .map((t) => DropdownMenuItem(
                                      value: t['RoomTypeID'].toString(),
                                      child: Text(t['TypeName']),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => selectedRoomTypeId = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedBuildingId,
                            decoration: const InputDecoration(labelText: 'ตึก'),
                            items: buildings
                                .map((b) => DropdownMenuItem(
                                      value: b['BuildingID'].toString(),
                                      child: Text(b['BuildingName']),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => selectedBuildingId = v),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ===== ส่วน: ที่อยู่ =====
                    const _SectionTitle(title: 'ที่อยู่ห้องพัก (ถ้ามี)'),
                    const SizedBox(height: 10),
                    NeumorphicCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: houseNo,
                                  decoration: const InputDecoration(
                                    labelText: 'เลขที่',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: moo,
                                  decoration: const InputDecoration(
                                    labelText: 'หมู่',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: subDistrict,
                                  decoration: const InputDecoration(
                                    labelText: 'ตำบล',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: district,
                                  decoration: const InputDecoration(
                                    labelText: 'อำเภอ',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: province,
                                  decoration: const InputDecoration(
                                    labelText: 'จังหวัด',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: postalCode,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'รหัสไปรษณีย์',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ===== ส่วน: อุปกรณ์ในห้อง =====
                    const _SectionTitle(title: 'อุปกรณ์ในห้อง'),
                    const SizedBox(height: 10),
                    NeumorphicCard(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: (equipments.isEmpty)
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('ไม่มีข้อมูลอุปกรณ์',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                            )
                          : Column(
                              children: equipments.map<Widget>((e) {
                                final idStr = e['EquipmentID'].toString();
                                final checked =
                                    selectedEquipmentIds.contains(idStr);
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(e['EquipmentName']),
                                  value: checked,
                                  activeColor: AppColors.primary,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        selectedEquipmentIds.add(idStr);
                                      } else {
                                        selectedEquipmentIds.remove(idStr);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 18),

                    // ===== ส่วน: รูปภาพห้อง =====
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionTitle(title: 'รูปภาพห้อง'),
                        AppButton(
                          icon: Icons.add_photo_alternate_rounded,
                          label: 'เลือกรูป (${selectedImages.length})',
                          onPressed: pickImages, // ใช้ฟังก์ชันเดิม
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    NeumorphicCard(
                      padding: const EdgeInsets.all(12),
                      child: selectedImageBytes.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('ยังไม่มีรูปภาพ',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                            )
                          : Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: selectedImageBytes.map((bytes) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(bytes,
                                      width: 110,
                                      height: 110,
                                      fit: BoxFit.cover),
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 22),

                    // ===== ปุ่มบันทึก / ยกเลิก =====
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            icon: Icons.save_rounded,
                            label: 'บันทึกห้องพัก',
                            expand: true,
                            onPressed: submitRoom, // ฟังก์ชันเดิม
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            icon: Icons.cancel_rounded,
                            label: 'ยกเลิก',
                            expand: true,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
          child: const Icon(Icons.edit_note_rounded,
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
