import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

final Set<int> _allowedEquipmentIds = {}; // จาก /api/owner/:id/equipments

Future<List> _getListFromEither(String a, String b) async {
  Future<List> f(String url) async {
    final r =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode} $url';
    final j = json.decode(r.body);
    if (j is List) return j;
    if (j is Map) {
      final v = j['data'] ?? j['items'] ?? j['rows'];
      if (v is List) return v;
    }
    return <dynamic>[];
  }

  try {
    return await f(a);
  } catch (_) {
    return await f(b);
  }
}

// ---------- helpers ----------
T? safeIn<T>(T? v, List<T> list) => (v != null && list.contains(v)) ? v : null;

void d(Object? msg) {
  if (kDebugMode) debugPrint('[AddRoom] $msg');
}

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

class AddRoomPage extends StatefulWidget {
  final int? buildingId;
  const AddRoomPage({super.key, this.buildingId});

  @override
  State<AddRoomPage> createState() => _AddRoomPageState();
}

class _AddRoomPageState extends State<AddRoomPage> {
  final _formKey = GlobalKey<FormState>();

  // controllers (เฉพาะที่ยังใช้จริง)
  final roomNumberController = TextEditingController();
  final capacityController = TextEditingController();
  final sizeController = TextEditingController();
  final priceController = TextEditingController();

  // dropdown states
  String? selectedStatus = 'ว่าง'; // default
  String? selectedRoomTypeId;
  String? selectedBuildingId;
  String? selectedBuildingName;
  final List<String> selectedEquipmentIds = [];

  // images
  final picker = ImagePicker();
  List<File> selectedImages = [];
  List<Uint8List> selectedImageBytes = [];

  // sources
  List roomTypes = [];
  List buildings = [];
  List equipments = [];

  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    d('initState(buildingId=${widget.buildingId})');
    selectedBuildingId = widget.buildingId?.toString();
    fetchDropdownData();
  }

  @override
  void dispose() {
    // room
    roomNumberController.dispose();
    capacityController.dispose();
    sizeController.dispose();
    priceController.dispose();

    super.dispose();
  }

  Future<void> fetchDropdownData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      // โหลด room-types และ buildings
      final rt = await http
          .get(Uri.parse('$apiBaseUrl/api/room-types'))
          .timeout(const Duration(seconds: 10));
      final bld = await http
          .get(Uri.parse('$apiBaseUrl/api/buildings'))
          .timeout(const Duration(seconds: 10));
      if (rt.statusCode != 200 || bld.statusCode != 200) {
        throw 'HTTP ${rt.statusCode}/${bld.statusCode}';
      }

      List<dynamic> _asList(dynamic body) {
        if (body is List) return body;
        if (body is Map) {
          final v = body['rows'] ?? body['data'] ?? body['items'];
          if (v is List) return v;
        }
        return <dynamic>[];
      }

      final roomTypesJson = _asList(json.decode(rt.body));
      final buildingsJson = _asList(json.decode(bld.body));

      // ------------------ เลือกตึกเริ่มต้น ------------------
      final rTypeIds =
          roomTypesJson.map<String>((t) => t['RoomTypeID'].toString()).toList();

      // ids ตึกทั้งหมดจาก API
      final bIds =
          buildingsJson.map<String>((b) => b['BuildingID'].toString()).toList();

      // id ตึกที่ส่งมาจากหน้าเดิม (OwnerDashboard)
      final incoming = widget.buildingId?.toString();

      // ถ้ามี incoming และอยู่ในลิสต์ -> ใช้นั้น, ไม่งั้นใช้ตัวแรก (ถ้ามี)
      String? buildingIdSel = (incoming != null && bIds.contains(incoming))
          ? incoming
          : (bIds.isNotEmpty ? bIds.first : null);

      // หา "ชื่ออาคาร" จาก id ที่เลือก (ถ้าเจอ)
      String? buildingNameSel;
      if (buildingIdSel != null) {
        final found = firstWhereOrNull(
          buildingsJson,
          (b) => b['BuildingID'].toString() == buildingIdSel,
        );
        buildingNameSel =
            (found?['BuildingName'] ?? found?['name'])?.toString();
      }

      // ถ้า API buildings ว่าง แต่เรามี widget.buildingId -> ใช้ id นั้นไปก่อน
      buildingIdSel ??= incoming;

      // ------------------ อุปกรณ์ที่อนุญาต ------------------
      final equipmentsJson = await _getListFromEither(
        '$apiBaseUrl/api/equipment',
        '$apiBaseUrl/api/equipments',
      );

      // หา ownerId จากอาคารที่เลือก (ถ้ามี field)
      int? ownerIdSel;
      if (buildingIdSel != null) {
        final found = firstWhereOrNull(
          buildingsJson,
          (b) => b['BuildingID'].toString() == buildingIdSel,
        );
        ownerIdSel =
            int.tryParse('${found?['OwnerID'] ?? found?['ownerId'] ?? ''}');
      }

      final allowedIds = <int>{};
      if (ownerIdSel != null) {
        final rAllowed = await http
            .get(Uri.parse('$apiBaseUrl/api/owner/$ownerIdSel/equipments'))
            .timeout(const Duration(seconds: 10));
        if (rAllowed.statusCode == 200) {
          final aj = json.decode(rAllowed.body);
          final List list =
              (aj is List) ? aj : (aj['data'] ?? aj['items'] ?? []);
          allowedIds.addAll(
            list.map((e) {
              if (e is int) return e;
              if (e is Map && e['EquipmentID'] != null) {
                return int.tryParse('${e['EquipmentID']}') ?? -1;
              }
              return int.tryParse('$e') ?? -1;
            }).where((id) => id > 0),
          );
        }
      }

      final filteredEquipments = equipmentsJson.where((e) {
        final id = int.tryParse('${e['EquipmentID']}') ?? -1;
        return allowedIds.isEmpty ? false : allowedIds.contains(id);
      }).toList()
        ..sort((a, b) => (a['EquipmentName'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['EquipmentName'] ?? '').toString().toLowerCase()));

      if (!mounted) return;
      setState(() {
        roomTypes = roomTypesJson;
        buildings = buildingsJson;
        equipments = filteredEquipments;
        _allowedEquipmentIds
          ..clear()
          ..addAll(allowedIds);

        selectedStatus ??= 'ว่าง';
        selectedRoomTypeId = rTypeIds.isNotEmpty ? rTypeIds.first : null;

        // ✅ ตั้งทั้ง id และ name ของตึกที่เลือก
        selectedBuildingId = buildingIdSel;
        selectedBuildingName = buildingNameSel;

        // กันค่าที่เลือกหลุดจาก allowed
        selectedEquipmentIds.removeWhere(
          (sid) => !_allowedEquipmentIds.contains(int.tryParse(sid) ?? -1),
        );
      });
    } on TimeoutException {
      _loadError = 'เชื่อมต่อ API ช้า/หมดเวลา (timeout)';
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> pickImages() async {
    final picked = await picker.pickMultiImage();
    final bytesList = <Uint8List>[];
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

    if (selectedRoomTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกประเภทห้อง')),
      );
      return;
    }

    final roomTypeId = int.tryParse(selectedRoomTypeId ?? '');
    final buildingId =
        widget.buildingId ?? int.tryParse(selectedBuildingId ?? '');

    if (roomTypeId == null || buildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ข้อมูลประเภทห้อง/ตึกไม่ถูกต้อง')),
      );
      return;
    }

    final capacity = int.tryParse(capacityController.text);
    final size = double.tryParse(sizeController.text);
    final priceRaw = priceController.text.replaceAll(',', '').trim();
    final price = double.tryParse(priceRaw) ?? 0.0;
    if (capacity == null || size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('กรุณากรอกความจุ/ขนาดเป็นตัวเลขให้ถูกต้อง')),
      );
      return;
    }

    final statusToSave = selectedStatus ?? 'ว่าง';

    final payloadEquipmentIds = selectedEquipmentIds
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .where(_allowedEquipmentIds.contains)
        .toList();

    setState(() => _submitting = true);
    try {
      final roomRes = await http.post(
        Uri.parse('$apiBaseUrl/api/rooms'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'RoomNumber': roomNumberController.text.trim(),
          'Address': '-',
          'Capacity': capacity,
          'Size': size,
          'Status': statusToSave,
          'RoomTypeID': roomTypeId,
          'BuildingID': buildingId,
          'EquipmentIDs': payloadEquipmentIds,
          'PricePerMonth': price,
        }),
      );

      if (roomRes.statusCode != 200 && roomRes.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('บันทึกห้องไม่สำเร็จ (${roomRes.statusCode})')),
        );
        return;
      }

      // upload images (optional)
      if (selectedImages.isNotEmpty) {
        for (final imageFile in selectedImages) {
          final req = http.MultipartRequest(
            'POST',
            Uri.parse('$apiBaseUrl/api/room-images'),
          );
          req.fields['RoomNumber'] = roomNumberController.text.trim();
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
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F6),
      appBar: AppBar(
        title: const Text('เพิ่มห้องพัก'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_loadError != null)
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: NeumorphicCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.red, size: 36),
                        const SizedBox(height: 8),
                        const Text('โหลดข้อมูลเริ่มต้นไม่สำเร็จ'),
                        const SizedBox(height: 6),
                        Text(_loadError ?? '',
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: fetchDropdownData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองใหม่'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      // Header card
                      NeumorphicCard(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Row(
                          children: [
                            const Icon(Icons.add_home_rounded,
                                color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('เพิ่มห้องพัก',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            if ((selectedBuildingId ?? '').trim().isNotEmpty &&
                                (selectedBuildingId ?? '')
                                        .toLowerCase()
                                        .trim() !=
                                    'null')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('Building ID: $selectedBuildingId',
                                    style: const TextStyle(
                                        color: AppColors.primaryDark)),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // การ์ดฟอร์มหลัก — Form ครอบไว้เพื่อใช้ validator
                      NeumorphicCard(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1) รายละเอียดห้อง
                              const _SectionTitle(title: 'รายละเอียดห้อง'),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: roomNumberController,
                                decoration: const InputDecoration(
                                  labelText: 'เลขห้อง',
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
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
                                          hintText: 'จำนวนผู้อยู่อาศัย'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: sizeController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: 'ขนาด (ตร.ม.)',
                                          hintText: 'เช่น 28.23'),
                                    ),
                                  ),
                                ],
                              ),
                              TextFormField(
                                controller: priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'ราคาต่อเดือน (บาท)',
                                  hintText: 'เช่น 3200',
                                ),
                                validator: (v) {
                                  final s =
                                      (v ?? '').replaceAll(',', '').trim();
                                  final n = double.tryParse(s);
                                  if (n == null || n < 0)
                                    return 'กรุณากรอกราคาเป็นตัวเลขให้ถูกต้อง';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: safeIn(
                                    selectedStatus, const ['ว่าง', 'ไม่ว่าง']),
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'สถานะ'),
                                items: const ['ว่าง', 'ไม่ว่าง']
                                    .map((s) => DropdownMenuItem(
                                        value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => selectedStatus = v),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: safeIn(
                                  selectedRoomTypeId,
                                  roomTypes
                                      .map<String>(
                                          (t) => t['RoomTypeID'].toString())
                                      .toList(),
                                ),
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'ประเภทห้อง'),
                                items: roomTypes
                                    .map((t) => DropdownMenuItem(
                                          value: t['RoomTypeID'].toString(),
                                          child: Text(t['TypeName'].toString()),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => selectedRoomTypeId = v),
                              ),
                              const SizedBox(height: 12),
                              // ตึก  ⬇⬇ แทนที่ทั้งบล็อกเดิมด้วยโค้ดนี้
                              (widget.buildingId != null)
                                  // โหมดอ่านอย่างเดียว เมื่อถูกส่ง buildingId มาจากหน้าก่อน
                                  ? TextFormField(
                                      readOnly: true, // หรือ enabled: false
                                      decoration: const InputDecoration(
                                          labelText: 'ตึก'),
                                      initialValue: selectedBuildingName ??
                                          'ID: ${widget.buildingId}',
                                    )
                                  // โหมดเลือกจากลิสต์ เมื่อไม่ได้ล็อกตึก
                                  : DropdownButtonFormField<String>(
                                      value: selectedBuildingId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'ตึก'),
                                      items: buildings
                                          .map<DropdownMenuItem<String>>(
                                            (b) => DropdownMenuItem<String>(
                                              value: b['BuildingID'].toString(),
                                              child: Text(
                                                  b['BuildingName'].toString()),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                          () => selectedBuildingId = v),
                                    ),

                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 12),

                              // 3) อุปกรณ์ในห้อง
                              // ====== วางแทนบล็อกอุปกรณ์ในห้องใน build() ======
                              const _SectionTitle(title: 'อุปกรณ์ในห้อง'),
                              const SizedBox(height: 8),

                              if (equipments.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                      'ไม่มีข้อมูลอุปกรณ์ที่เจ้าของอนุญาต',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                )
                              else
                                _EquipmentTagGrid(
                                  items:
                                      equipments, // [{EquipmentID, EquipmentName}, ...]
                                  isSelected: (idStr) =>
                                      selectedEquipmentIds.contains(idStr),
                                  onToggle: (idStr, nowSelected) {
                                    setState(() {
                                      if (nowSelected) {
                                        // อนุญาตเท่านั้น
                                        final id = int.tryParse(idStr) ?? -1;
                                        if (_allowedEquipmentIds.contains(id) &&
                                            !selectedEquipmentIds
                                                .contains(idStr)) {
                                          selectedEquipmentIds.add(idStr);
                                        }
                                      } else {
                                        selectedEquipmentIds.remove(idStr);
                                      }
                                    });
                                  },
                                ),

                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 12),

                              // 4) รูปภาพห้อง
                              Row(
                                children: [
                                  const _SectionTitle(title: 'รูปภาพห้อง'),
                                  const Spacer(),
                                  // ปุ่มนี้อยู่ใน Row -> ใช้ expand:false กัน infinite width
                                  AppButton(
                                    icon: Icons.add_photo_alternate_rounded,
                                    label:
                                        'เลือกรูป (${selectedImages.length})',
                                    onPressed: pickImages,
                                    expand: false,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              selectedImageBytes.isEmpty
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text('ยังไม่มีรูปภาพ',
                                          style: TextStyle(
                                              color: AppColors.textSecondary)),
                                    )
                                  : Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: selectedImageBytes
                                          .map((bytes) => ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.memory(bytes,
                                                    width: 120,
                                                    height: 120,
                                                    fit: BoxFit.cover),
                                              ))
                                          .toList(),
                                    ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // ปุ่ม action (อยู่นอกการ์ด)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: AppButton(
                                icon: _submitting
                                    ? Icons.hourglass_top_rounded
                                    : Icons.save_rounded,
                                label: _submitting
                                    ? 'กำลังบันทึก...'
                                    : 'บันทึกห้องพัก',
                                onPressed: _submitting ? null : submitRoom,
                                expand: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: AppButton(
                                icon: Icons.cancel_rounded,
                                label: 'ยกเลิก',
                                onPressed: () => Navigator.pop(context),
                                expand: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

/* ===================== Sub Widgets ===================== */

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
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// แสดงอุปกรณ์เป็นชิปสวยๆ (responsive)
class _EquipmentTagGrid extends StatelessWidget {
  final List items;
  final bool Function(String id) isSelected;
  final void Function(String id, bool selected) onToggle;

  const _EquipmentTagGrid({
    required this.items,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map<Widget>((e) {
        final idStr = '${e['EquipmentID']}';
        final name = (e['EquipmentName'] ?? '').toString();
        final selected = isSelected(idStr);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onToggle(idStr, !selected),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : const Color(0xFFF6FAF9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.inventory_2_rounded,
                  size: 18,
                  color: selected ? Colors.white : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
