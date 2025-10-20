import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/color_app.dart';

class AddBuildingScreen extends StatefulWidget {
  final int ownerId;
  final Map<String, dynamic>? buildingToEdit;

  const AddBuildingScreen({
    super.key,
    required this.ownerId,
    this.buildingToEdit,
  });

  @override
  State<AddBuildingScreen> createState() => _AddBuildingScreenState();
}

class _AddBuildingScreenState extends State<AddBuildingScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final addressController = TextEditingController();
  final villageController = TextEditingController();
  final zipCodeController = TextEditingController();
  final floorsController = TextEditingController();
  final roomsController = TextEditingController();

  bool hasLift = false;
  bool hasParking = false;
  bool hasWifi = false;
  bool hasAir = false;

  // จังหวัด-อำเภอ-ตำบล
  List provinces = [];
  List amphures = [];
  List tambons = [];

  String? selectedProvinceId;
  String? selectedAmphureId;
  String? selectedTambonId;

  String? selectedProvinceName;
  String? selectedAmphureName;
  String? selectedTambonName;

  List<String> allFacilities = []; // ชื่อสิ่งอำนวยความสะดวกทั้งหมด
  Set<String> selectedFacilities = {}; // สิ่งที่ถูกเลือกไว้

  Uint8List? _qrImage;
  String? _qrUrl;

  @override
  void initState() {
    super.initState();
    loadInitialData();
  }

  Future<void> loadInitialData() async {
    await loadThaiAddressData(); // โหลดจังหวัด, อำเภอ, ตำบล
    await loadFacilities();
    if (widget.buildingToEdit != null) {
      await Future.delayed(const Duration(milliseconds: 50));
      loadEditData();
    }
  }

  Future<void> loadFacilities() async {
    try {
      final resAll = await http.get(Uri.parse('$apiBaseUrl/api/facilities'));
      if (resAll.statusCode == 200) {
        final List data = json.decode(resAll.body);
        allFacilities =
            data.map<String>((f) => f['FacilityName'].toString()).toList();
      }

      if (widget.buildingToEdit != null) {
        final buildingId = widget.buildingToEdit!['buildingId'];
        final resSelected = await http.get(
          Uri.parse('$apiBaseUrl/api/building/$buildingId/facilities'),
        );
        if (resSelected.statusCode == 200) {
          final List data = json.decode(resSelected.body);
          selectedFacilities = data.map<String>((f) => f.toString()).toSet();
        }
      }

      setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print("โหลด facility ล้มเหลว: $e");
    }
  }

  Future<void> loadThaiAddressData() async {
    final jsonString = await rootBundle
        .loadString('assets/data/api_province_with_amphure_tambon.json');
    final data = json.decode(jsonString);

    provinces = data;
    amphures = [];
    tambons = [];

    setState(() {});
  }

  void loadEditData() {
    final b = widget.buildingToEdit!;
    nameController.text = b['buildingName'] ?? '';
    final addressText = b['address'] ?? '';

    // แยกส่วนที่อยู่
    final regex = RegExp(
        r'^(.+?)\s*หมู่\s*(\d+),\s*ต\.(.+?),\s*อ\.(.+?),\s*จ\.(.+?),\s*(\d{5})$');
    final match = regex.firstMatch(addressText);

    if (match != null) {
      addressController.text = match.group(1)?.trim() ?? '';
      villageController.text = match.group(2)?.trim() ?? '';
      selectedTambonName = match.group(3)?.trim();
      selectedAmphureName = match.group(4)?.trim();
      selectedProvinceName = match.group(5)?.trim();

      if (selectedProvinceName != null && selectedAmphureName == "เมือง") {
        selectedAmphureName = "เมือง$selectedProvinceName";
      }

      final prov = provinces.firstWhere(
        (p) => p['name_th'] == selectedProvinceName,
        orElse: () => null,
      );

      if (prov != null) {
        selectedProvinceId = prov['id'].toString();
        amphures = List.from(prov['amphure'] ?? []);

        final amp = amphures.firstWhere(
          (a) => a['name_th'] == selectedAmphureName,
          orElse: () => null,
        );

        if (amp != null) {
          selectedAmphureId = amp['id'].toString();
          tambons = List.from(amp['tambon'] ?? []);

          final tam = tambons.firstWhere(
            (t) => t['name_th'] == selectedTambonName,
            orElse: () => null,
          );

          if (tam != null) {
            selectedTambonId = tam['id'].toString();
            zipCodeController.text = tam['zip_code'].toString();
          }
        }
      }
    }

    // ฟิลด์ตัวเลข/สิ่งอำนวยความสะดวก
    floorsController.text = (b['floors'] ?? '').toString();
    roomsController.text = (b['rooms'] ?? '').toString();

    final List<dynamic> facilityList = b['facilities'] ?? [];
    hasLift = facilityList.contains("Lift");
    hasParking = facilityList.contains("Parking");
    hasWifi = facilityList.contains("Wifi");
    hasAir = facilityList.contains("Air");

    // ตั้งค่า _qrUrl "นอก if" + ใส่ cache-busting เสมอ
    final rawQr = (b['qrCodeUrl'] ?? b['QrCodeUrl'] ?? '').toString().trim();
    if (rawQr.isNotEmpty) {
      final abs = rawQr.startsWith('http') ? rawQr : '$apiBaseUrl/$rawQr';
      _qrUrl = _withBust(abs);
    }

    setState(() {});
  }

  Future<void> submitForm() async {
    if (_formKey.currentState!.validate()) {
      final prov =
          provinces.firstWhere((p) => p['id'].toString() == selectedProvinceId);
      final amp =
          amphures.firstWhere((a) => a['id'].toString() == selectedAmphureId);
      final tam =
          tambons.firstWhere((t) => t['id'].toString() == selectedTambonId);

      final fullAddress =
          '${addressController.text} หมู่ ${villageController.text}, ต.${tam['name_th']}, อ.${amp['name_th']}, จ.${prov['name_th']}, ${zipCodeController.text}';

      final buildingData = {
        "BuildingName": nameController.text.trim(),
        "Address": fullAddress,
        "Floors": int.tryParse(floorsController.text.trim()) ?? 0,
        "Rooms": int.tryParse(roomsController.text.trim()) ?? 0,
        "OwnerID": widget.ownerId,
        "Facilities": selectedFacilities.toList(),
        "QrUrl": _qrUrl ?? "",
      };

      try {
        late http.Response response;

        if (widget.buildingToEdit != null) {
          final buildingId = widget.buildingToEdit!['buildingId'];
          response = await http.put(
            Uri.parse('$apiBaseUrl/api/building/$buildingId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(buildingData),
          );

          if (response.statusCode == 200) {
            // อัปโหลด QR Code ใหม่ถ้ามีการเปลี่ยนรูป
            if (_qrImage != null) {
              await uploadQrToServer(_qrImage!, widget.ownerId, buildingId);
            }
            if (!mounted) return;
            Navigator.pop(context, true);
          } else {
            final body = json.decode(response.body);
            _showErrorDialog("ไม่สำเร็จ: ${body['error'] ?? 'ไม่ทราบสาเหตุ'}");
          }
        } else {
          // เพิ่มตึกใหม่
          response = await http.post(
            Uri.parse('$apiBaseUrl/api/building'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(buildingData),
          );

          if (response.statusCode == 200) {
            final body = json.decode(response.body);
            final newBuildingId = body['buildingId'];

            if (_qrImage != null && newBuildingId != null) {
              await uploadQrToServer(_qrImage!, widget.ownerId, newBuildingId);
            }
            if (!mounted) return;
            Navigator.pop(context, true);
          } else {
            final body = json.decode(response.body);
            _showErrorDialog("ไม่สำเร็จ: ${body['error'] ?? 'ไม่ทราบสาเหตุ'}");
          }
        }
      } catch (e) {
        _showErrorDialog("เกิดข้อผิดพลาด: $e");
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.card,
        title: const Text("ผิดพลาด",
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content:
            Text(message, style: const TextStyle(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ตกลง",
                style: TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
          )
        ],
      ),
    );
  }

  Widget buildTextField(String label, TextEditingController controller,
      {bool isNumeric = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      validator: (value) =>
          value == null || value.isEmpty ? 'กรุณากรอก $label' : null,
      decoration: _inputDecoration(label),
    );
  }

  Future<void> deleteBuilding(int buildingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.card,
        title: const Text('ยืนยันการลบ',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: const Text('คุณแน่ใจว่าจะลบตึกนี้ใช่หรือไม่?',
            style: TextStyle(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก',
                style: TextStyle(color: AppColors.primaryDark)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/api/building/$buildingId'),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        String errorMessage = 'เกิดข้อผิดพลาด';
        try {
          final body = json.decode(response.body);
          errorMessage = body['error'] ?? errorMessage;
        } catch (_) {
          errorMessage = 'ลบไม่สำเร็จ (${response.statusCode})';
        }
        _showErrorDialog(errorMessage);
      }
    } catch (e) {
      _showErrorDialog('เกิดข้อผิดพลาด: $e');
    }
  }

  String _withBust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}t=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> pickQrImage() async {
  final picker = ImagePicker();
  final pickedFile = await picker.pickImage(source: ImageSource.gallery);

  if (pickedFile == null) {
    debugPrint('[AddBuilding] no file picked');
    return;
  }

  final bytes = await pickedFile.readAsBytes();
  debugPrint('[AddBuilding] picked: ${pickedFile.name} bytes=${bytes.length} at ${DateTime.now()}');

  // แสดง “รูปใหม่จากหน่วยความจำ” ทันที และตัด URL เก่าออก
  setState(() {
    _qrImage = bytes;
    _qrUrl = null;
  });
  debugPrint('[AddBuilding] preview = MEMORY');

  // ถ้าเป็นโหมดแก้ไข → อัปโหลด แล้วสลับกลับเป็น URL ใหม่
  final buildingId = widget.buildingToEdit?['buildingId'] ?? 0;
  if (buildingId != 0) {
    try {
      await uploadQrToServer(bytes, widget.ownerId, buildingId);
      setState(() {
        _qrImage = null; // ใช้ URL ใหม่แทน
      });
      debugPrint('[AddBuilding] preview = NETWORK (after upload)');
    } catch (e) {
      _showErrorDialog('อัปโหลด QR Code ล้มเหลว: $e');
      debugPrint('[AddBuilding] upload error: $e');
    }
  }
}


  Future<void> uploadQrToServer(
  Uint8List imageBytes, int ownerId, int buildingId) async {

  debugPrint('[AddBuilding] upload start size=${imageBytes.length} at ${DateTime.now()}');

  final uri = Uri.parse('$apiBaseUrl/api/upload-qr');
  final request = http.MultipartRequest('POST', uri)
    ..fields['ownerId'] = ownerId.toString()
    ..fields['buildingId'] = buildingId.toString()
    ..files.add(
      http.MultipartFile.fromBytes(
        'qrImage',
        imageBytes,
        filename: 'qr_${DateTime.now().millisecondsSinceEpoch}.png',
        contentType: MediaType('image', 'png'),
      ),
    );

  final response = await request.send();
  debugPrint('[AddBuilding] upload responseStatus=${response.statusCode}');

  if (response.statusCode != 200) {
    throw Exception('Failed to upload QR Code');
  }

  final bodyStr = await response.stream.bytesToString();
  debugPrint('[AddBuilding] upload body=$bodyStr');

  final data = json.decode(bodyStr);
  final raw = (data['qrUrl'] ?? '').toString();
  final abs = raw.startsWith('http') ? raw : '$apiBaseUrl/$raw';
  final busted = _withBust(abs); // กันแคช

  setState(() {
    _qrUrl = busted;
  });
  debugPrint('[AddBuilding] new url=$_qrUrl');
}


  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.buildingToEdit != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        title: Text(
          isEditMode ? 'แก้ไขตึก' : 'เพิ่มตึก',
          style:
              const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
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
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: _NeuCard(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.apartment,
                                  color: AppColors.primaryDark),
                              SizedBox(width: 6),
                              Text('ข้อมูลตึก',
                                  style: TextStyle(
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (isEditMode)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('โหมดแก้ไข',
                                style: TextStyle(
                                    color: AppColors.primaryDark,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Basic info
                    buildTextField("ชื่อตึก", nameController),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child:
                              buildTextField("บ้านเลขที่", addressController),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildTextField("หมู่", villageController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // จังหวัด / อำเภอ / ตำบล
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedProvinceId,
                            decoration: _dropdownDecoration("จังหวัด"),
                            items:
                                provinces.map<DropdownMenuItem<String>>((prov) {
                              return DropdownMenuItem(
                                value: prov['id'].toString(),
                                child: Text(prov['name_th']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedProvinceId = value;
                                selectedAmphureId = null;
                                selectedTambonId = null;
                                zipCodeController.clear();
                                amphures = provinces.firstWhere((p) =>
                                        p['id'].toString() == value)['amphure']
                                    as List<dynamic>;
                                tambons = [];
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedAmphureId,
                            decoration: _dropdownDecoration("อำเภอ"),
                            items:
                                amphures.map<DropdownMenuItem<String>>((amp) {
                              return DropdownMenuItem(
                                value: amp['id'].toString(),
                                child: Text(amp['name_th']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedAmphureId = value;
                                selectedTambonId = null;
                                zipCodeController.clear();
                                tambons = amphures.firstWhere((a) =>
                                        a['id'].toString() == value)['tambon']
                                    as List<dynamic>;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedTambonId,
                            decoration: _dropdownDecoration("ตำบล"),
                            items: tambons.map<DropdownMenuItem<String>>((tam) {
                              return DropdownMenuItem(
                                value: tam['id'].toString(),
                                child: Text(tam['name_th']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              final zip = tambons
                                  .firstWhere((t) =>
                                      t['id'].toString() == value)['zip_code']
                                  .toString();
                              setState(() {
                                selectedTambonId = value;
                                zipCodeController.text = zip;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: zipCodeController,
                      readOnly: true,
                      decoration: _inputDecoration('รหัสไปรษณีย์'),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: buildTextField("จำนวนชั้น", floorsController,
                              isNumeric: true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildTextField("จำนวนห้อง", roomsController,
                              isNumeric: true),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Facilities
                    const _SectionHeader(
                      icon: Icons.widgets_outlined,
                      title: 'สิ่งอำนวยความสะดวก',
                    ),
                    const SizedBox(height: 10),
                    _NeuCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          checkboxTheme: CheckboxThemeData(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            fillColor: MaterialStateProperty.resolveWith(
                                (states) => AppColors.primary),
                          ),
                        ),
                        child: Column(
                          children: allFacilities.map((facility) {
                            return CheckboxListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              title: Text(
                                facility,
                                style: const TextStyle(
                                    color: AppColors.textPrimary),
                              ),
                              value: selectedFacilities.contains(facility),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    selectedFacilities.add(facility);
                                  } else {
                                    selectedFacilities.remove(facility);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // QR Code
                    const _SectionHeader(
                      icon: Icons.qr_code_2_rounded,
                      title: 'QR Code',
                    ),
                    const SizedBox(height: 10),
                    _NeuCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: () {
                              if (_qrImage != null) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(_qrImage!,
                                      fit: BoxFit.cover),
                                );
                              }
                              if (_qrUrl != null && _qrUrl!.isNotEmpty) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    _qrUrl!,
                                    key: ValueKey(
                                        _qrUrl), 
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        size: 40,
                                        color: AppColors.textSecondary),
                                  ),
                                );
                              }
                              return const Center(
                                child: Icon(Icons.image_not_supported,
                                    size: 40, color: AppColors.textSecondary),
                              );
                            }(),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'อัปโหลดไฟล์ภาพ QR Code',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'รองรับ .png / .jpg',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: pickQrImage,
                                  icon: const Icon(Icons.upload_file_rounded,
                                      color: AppColors.primaryDark),
                                  label: const Text('เลือกรูป QR Code',
                                      style: TextStyle(
                                          color: AppColors.primaryDark)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: AppColors.primaryDark),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Action buttons
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _PrimaryGradientButton(
                            text: isEditMode ? "บันทึกการแก้ไข" : "เพิ่มตึก",
                            icon: Icons.save_rounded,
                            onTap: submitForm,
                          ),
                          if (isEditMode)
                            ElevatedButton.icon(
                              onPressed: () => deleteBuilding(
                                  widget.buildingToEdit!['buildingId']),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text("ลบ"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                            ),
                        ],
                      ),
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

  // ===== Helper Decorations (ดีไซน์เท่านั้น) =====
  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.primaryLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      );

  InputDecoration _dropdownDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.primaryLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      );
}

// -------------------- UI helpers (ดีไซน์) --------------------

class _NeuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _NeuCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
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
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryGradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryGradientButton({
    required this.text,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // << ต้องมี Material
      color: Colors.transparent,
      elevation: 2, // ดูเด่นขึ้น
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          // Ink วาดบน Material ข้างบน
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min, // << ขนาดพอดีเนื้อหา
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
