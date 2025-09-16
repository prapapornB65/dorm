import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../wallet/slipok_api.dart';
import 'package:flutter_application_1/tenantt/wallet/save_to_server.dart';
import 'package:flutter_application_1/config/api_config.dart';
import 'SlipOKError.dart';

// ✅ ดีไซน์: ใช้ธีม/วิจเจ็ตของเรา
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/color_app.dart';

class TopUpPage extends StatefulWidget {
  final int tenantId;

  const TopUpPage({super.key, required this.tenantId});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  Uint8List? _pickedImageBytes;
  String? _fileName;
  int? tenantId;
  String? tenantName;
  String? ownerName;
  String? qrCodeUrl;

  @override
  void initState() {
    super.initState();
    _loadTenantInfo();
  }

  String fixQrCodeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';

    final base = Uri.parse(apiBaseUrl);
    final u = Uri.tryParse(raw);
    if (u == null) return '';

    // ถ้า backend ส่ง localhost/127.0.0.1 หรือ host ไม่ตรงกับ base → ใช้ host ของ apiBaseUrl
    if (u.host == 'localhost' || u.host == '127.0.0.1' || u.host != base.host) {
      return u
          .replace(
            scheme: base.scheme,
            host: base.host,
            port: base.hasPort ? base.port : u.port,
          )
          .toString();
    }

    return u.toString();
  }

  Future<void> _loadTenantInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('tenantName');

    setState(() {
      tenantId = widget.tenantId; // ใช้ tenantId ที่ส่งมา
      tenantName = name;
    });

    debugPrint("📦 โหลด tenantId: $tenantId");
    debugPrint("📦 โหลด tenantName: $name");
    debugPrint('widget.tenantId = ${widget.tenantId}');

    if (tenantId == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('กรุณาเข้าสู่ระบบ'),
          content: const Text('ไม่พบข้อมูลผู้เช่า กรุณาเข้าสู่ระบบใหม่'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      return;
    }

    if (tenantId != null) {
      try {
        final url = Uri.parse('$apiBaseUrl/api/contact-owner/$tenantId');
        debugPrint("🌐 เรียก API: $url");

        final ownerResponse = await http.get(url);
        debugPrint("📥 สถานะ: ${ownerResponse.statusCode}");
        debugPrint("📥 ข้อมูลที่ได้: ${ownerResponse.body}");

        if (ownerResponse.statusCode == 200) {
          final ownerData = jsonDecode(ownerResponse.body);
          debugPrint("✅ ownerData: $ownerData");

          setState(() {
            ownerName = ownerData['OwnerName'];
            ownerId = (ownerData['OwnerID'] as num?)?.toInt();
            qrCodeUrl = fixQrCodeUrl(ownerData['QrCodeUrl']);
          });

          debugPrint("📌 ownerName = $ownerName");
          debugPrint("📌 ownerId = $ownerId");
          debugPrint("📌 qrCodeUrl = $qrCodeUrl");
        } else {
          debugPrint("❌ โหลดข้อมูลเจ้าของไม่สำเร็จ (status != 200)");
        }
      } catch (e) {
        debugPrint("🚨 error จากการโหลด contact-owner: $e");
      }
    } else {
      debugPrint("❗ tenantId เป็น null ไม่สามารถโหลดเจ้าของได้");
    }
  }

  int? ownerId;

  Future<String?> fetchOwnerName(int ownerId) async {
    final url = Uri.parse('$apiBaseUrl/api/owner/$ownerId');
    debugPrint('Fetching owner name for ownerId: $ownerId');

    final response = await http.get(url);
    debugPrint('Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['error'] == false) {
        setState(() {
          ownerName = data['ownerName'];
        });
        return data['ownerName'];
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchOwnerApiInfo(int ownerId) async {
    final url = Uri.parse('$apiBaseUrl/api/owner/$ownerId');
    debugPrint('Fetching owner api info for ownerId: $ownerId');

    final response = await http.get(url);
    debugPrint('Response from /api/owner/$ownerId: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['error'] == false) {
        return {
          'apiKey': data['apiKey'],
          'projectId': data['projectId'],
          'ownerName': data['ownerName'],
        };
      }
    }
    return null;
  }

  Future<void> _pickSlipFile() async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.storage.request();
    } else if (Platform.isIOS) {
      status = await Permission.photos.request();
    } else {
      status = PermissionStatus.granted;
    }

    if (!status.isGranted) {
      _showResultDialog(
        success: false,
        message: "⚠️ กรุณาอนุญาตเข้าถึงคลังภาพก่อนอัปโหลด",
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _pickedImageBytes = bytes;
        _fileName = pickedFile.name;
      });

      debugPrint("✅ เลือกรูปสลิปแล้ว: ${pickedFile.name}");
    } else {
      debugPrint("❌ ไม่ได้เลือกรูป");
    }
  }

  Future<String> uploadSlipImage(Uint8List imageBytes, String fileName) async {
    var uri = Uri.parse('$apiBaseUrl/api/upload-slip-image');
    var request = http.MultipartRequest('POST', uri);
    request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: fileName));
    var response = await request.send();

    debugPrint('uploadSlipImage - Response status: ${response.statusCode}');

    var respStr = await response.stream.bytesToString();
    debugPrint('uploadSlipImage - Response body: $respStr');

    if (response.statusCode == 200) {
      var data = jsonDecode(respStr);
      if (data['error'] == false && data['fileUrl'] != null) {
        return data['fileUrl'];
      } else {
        throw Exception(
            'ไม่สามารถอัปโหลดรูปภาพได้: ${data['message'] ?? 'Unknown error'}');
      }
    } else {
      throw Exception('อัปโหลดรูปภาพล้มเหลว: ${response.statusCode}');
    }
  }

  bool _isSubmitting = false;

  Future<void> _submitSlip() async {
    if (_isSubmitting) return;
    if (_pickedImageBytes == null || _fileName == null) return;

    debugPrint(" เริ่มอัปโหลด...");
    _isSubmitting = true;
    if (mounted) setState(() {});

    try {
      // STEP 1: เตรียมข้อมูลเจ้าของ
      final ownerIdNow = ownerId ?? 0;
      final ownerInfo = await fetchOwnerApiInfo(ownerIdNow);
      if (ownerInfo == null) {
        _showResultDialog(
            success: false,
            message: "ไม่สามารถดึง API Key หรือ Project ID ได้");
        return;
      }
      final apiKey = ownerInfo['apiKey'];
      final projectId = ownerInfo['projectId'];
      ownerName = ownerInfo['ownerName'];
      debugPrint('✅ ownerInfo: $ownerInfo');

      // STEP 2: เรียก SlipOK
      final result = await uploadToSlipOK(
          _pickedImageBytes!, _fileName!, apiKey, projectId);
      debugPrint("✅ Full response: $result");

      // กันเคสผิดพลาดเบื้องต้น
      if (result == null) {
        _showResultDialog(
            success: false, message: "ไม่สามารถเชื่อมต่อ SlipOK ได้");
        return;
      }
      if (result['error'] == true) {
        _showResultDialog(
          success: false,
          message: (result['message']?.toString().isNotEmpty == true)
              ? result['message'].toString()
              : "ไม่สามารถตรวจสอบสลิปได้ (error=true)",
        );
        return;
      }

      // STEP 3: ตรวจ code
      final int apiCode = int.tryParse('${result['code'] ?? '0'}') ?? 0;
      debugPrint('🟦 STEP 3: ตรวจ code = $apiCode');

      if (apiCode != 0) {
        handleSlipOkErrorCode(
          code: apiCode,
          message: result['message'],
          context: context,
          showResultDialog: _showResultDialog,
          mounted: mounted,
        );
        return;
      }

      // STEP 3.1: data ต้องเป็น Map และไม่ว่าง
      final Map<String, dynamic> slipData = (result['data'] is Map)
          ? Map<String, dynamic>.from(result['data'])
          : {};
      if (slipData.isEmpty) {
        _showResultDialog(
          success: false,
          message: (result['message']?.toString().isNotEmpty == true)
              ? result['message'].toString()
              : "ไม่พบข้อมูลสลิปจากระบบ",
        );
        return;
      }

      // STEP 4: แตกค่าจากสลิป
      const bankNames = {
        '006': 'กรุงเทพ',
        '002': 'กรุงไทย',
        '004': 'กสิกรไทย',
        '014': 'ไทยพาณิชย์',
        '011': 'ทหารไทยธนชาต',
        '017': 'ซีไอเอ็มบี',
        '020': 'ออมสิน',
      };
      final String bank = slipData['sendingBank']?.toString() ?? '';
      final String amountStr = slipData['paidLocalAmount']?.toString() ??
          slipData['amount']?.toString() ??
          '0';
      final String date = slipData['transDate']?.toString() ?? '';
      final String time = slipData['transTime']?.toString() ?? '';
      final String senderName =
          slipData['sender']?['displayName']?.toString() ?? 'ไม่ทราบชื่อ';
      final String bankFullName = bankNames[bank] ?? bank;
      final String datetime =
          formatDateTime(date, time); // <- จาก slipok_api.dart

      if (tenantId == null) {
        _showResultDialog(
            success: false, message: "ไม่พบข้อมูลผู้เช่า กรุณาเข้าสู่ระบบใหม่");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final roomNumber = prefs.getString('roomNumber') ?? 'A101';

      // STEP 5: อัปโหลดรูปสลิปไปเซิร์ฟเวอร์ไฟล์
      final String imageUrl =
          await uploadSlipImage(_pickedImageBytes!, _fileName!);
      debugPrint('✅ ได้ imageUrl: $imageUrl');

      // STEP 6: เตรียมบันทึกลง DB
      final int parsedAmount = int.tryParse(amountStr) ?? 0;
      final DateTime parsedDatetime =
          DateTime.tryParse(datetime) ?? DateTime.now();

      // STEP 7: บันทึกลง DB (กำหนดสถานะเริ่มต้นให้เป็น pending)
      final resultSave = await saveSlipToServer(
        tenantId: tenantId!,
        bank: bank,
        amount: parsedAmount,
        datetime: parsedDatetime,
        tenantName: tenantName ?? '',
        roomNumber: roomNumber,
        imagePath: imageUrl,
        senderName: senderName,
        status: "pending", // ✅ ปักสถานะเริ่มต้นให้รอตรวจสอบ
      );
      debugPrint(
          '✅ ผลบันทึก DB: ok=${resultSave.ok}, status=${resultSave.statusCode}, msg=${resultSave.message}');

      if (!mounted) return;

      // STEP 8: แจ้งผล
      _showResultDialog(
        success: resultSave.ok,
        message: resultSave.ok
            ? "บันทึกลงฐานข้อมูลสำเร็จ\nผู้โอน: $senderName\nธนาคาร: $bankFullName\nยอด: $amountStr บาท\nเวลา: $datetime"
            : "บันทึกลงฐานข้อมูลไม่สำเร็จ\n${resultSave.message}",
      );
    } catch (e) {
      debugPrint("🛑 CATCH ERROR: $e");
      if (!mounted) return;
      _showResultDialog(success: false, message: "เกิดข้อผิดพลาด:\n$e");
    } finally {
      _isSubmitting = false;
      if (mounted) setState(() {});
      debugPrint('🟩 FINALLY: reset _isSubmitting');
    }
  }

  Future<void> fetchOwnerInfo() async {
    final response =
        await http.get(Uri.parse('$apiBaseUrl/api/owner/${ownerId}'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        ownerName = data['ownerName'];
        qrCodeUrl = data['qrCodeUrl'];
      });
    }
  }

  Future<void> _showResultDialog(
      {required bool success, required String message}) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Icon(
          success ? Icons.check_circle : Icons.cancel,
          color: success ? Colors.green : Colors.red,
          size: 60,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            child: Text("OK",
                style: TextStyle(color: success ? Colors.green : Colors.red)),
            onPressed: () => Navigator.pop(context), // ปิด dialog
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ เปลี่ยนเฉพาะดีไซน์: ใช้ GradientScaffold + โทน AppColors
    return GradientScaffold(
      appBar: AppBar(title: const Text("เติมเงิน")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle("ช่องทางชำระเงิน"),
              Center(child: _paymentBox()),
              const SizedBox(height: 24),
              _sectionTitle("ยืนยันการชำระเงิน"),
              const SizedBox(height: 8),
              Center(child: _uploadButton()),
              const SizedBox(height: 20),
              if (_pickedImageBytes != null) _slipPreview(),
              const SizedBox(height: 20),
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------- UI (ดีไซน์อย่างเดียว) -------------------

  Widget _sectionTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 4,
          width: 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _paymentBox() {
    if (qrCodeUrl != null) {
      debugPrint('QR Code URL: $qrCodeUrl');
    } else {
      debugPrint('QR Code URL is null or empty');
    }

    // ใช้ NeumorphicCard แทน Container
    return NeumorphicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          qrCodeUrl != null && qrCodeUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    qrCodeUrl!,
                    height: 200,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        debugPrint('โหลดรูป QR code สำเร็จ');
                        return child;
                      }
                      debugPrint('กำลังโหลดรูป QR code...');
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('โหลดรูป QR code ไม่สำเร็จ: $error');
                      return const SizedBox(
                        height: 200,
                        child:
                            Center(child: Icon(Icons.error, color: Colors.red)),
                      );
                    },
                  ),
                )
              : const SizedBox(
                  height: 200,
                  child: Center(
                      child: Icon(Icons.qr_code_2,
                          size: 64, color: AppColors.textSecondary)),
                ),
          const SizedBox(height: 12),
          Text(
            ownerName != null
                ? "ชื่อบัญชี: $ownerName"
                : "กำลังโหลดชื่อเจ้าของหอพัก...",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadButton() {
    // ใช้ AppButton (gradient) พร้อม label ตามไฟล์ที่เลือก
    return SizedBox(
      width: 280,
      child: AppButton(
        label: _fileName ?? 'อัปโหลดสลิป',
        icon: Icons.upload_file,
        expand: true,
        onPressed: _pickSlipFile,
      ),
    );
  }

  Widget _slipPreview() {
    return NeumorphicCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "แสดงตัวอย่างสลิป",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _pickedImageBytes!,
              height: 280,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fileName ?? '',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    return Center(
      child: SizedBox(
        width: 220,
        child: AppButton(
          label: _isSubmitting ? 'กำลังส่ง…' : 'ส่ง',
          icon: _isSubmitting ? Icons.hourglass_top : Icons.send,
          onPressed:
              _isSubmitting ? null : _submitSlip, // disable เมื่อกำลังส่ง
        ),
      ),
    );
  }
}
