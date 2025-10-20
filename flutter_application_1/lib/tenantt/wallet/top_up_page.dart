import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../wallet/slipok_api.dart';
import 'package:flutter_application_1/tenantt/wallet/save_to_server.dart';
import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/tenantt/wallet/SlipOkError.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

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
  ImageProvider? _qrProvider;
  bool _qrReady = false;
  String? _apiKey;
  String? _projectId;

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

    // เก็บค่า tenant เบื้องต้น
    setState(() {
      tenantId = widget.tenantId;
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
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง')),
          ],
        ),
      );
      return;
    }

    try {
      final url = Uri.parse('$apiBaseUrl/api/contact-owner/$tenantId');
      debugPrint("🌐 เรียก API: $url");

      final ownerResponse = await http.get(url);
      debugPrint("📥 สถานะ: ${ownerResponse.statusCode}");
      debugPrint("📥 ข้อมูลที่ได้: ${ownerResponse.body}");

      if (ownerResponse.statusCode != 200) {
        debugPrint("❌ โหลดข้อมูลเจ้าของไม่สำเร็จ (status != 200)");
        return;
      }

      final ownerData = jsonDecode(ownerResponse.body);
      final fixedQr = fixQrCodeUrl(ownerData['QrCodeUrl']);

      // ✅ เตรียมข้อมูล owner ก่อน
      if (mounted) {
        final apiKey =
            (ownerData['apiKey'] ?? ownerData['ApiKey'] ?? ownerData['api_key'])
                ?.toString();
        final projectId = (ownerData['projectId'] ??
                ownerData['ProjectID'] ??
                ownerData['project_id'])
            ?.toString();

        setState(() {
          ownerName = ownerData['OwnerName'];
          ownerId = (ownerData['OwnerID'] as num?)?.toInt();
          qrCodeUrl = fixedQr;
          _apiKey = apiKey?.trim();
          _projectId = projectId?.trim();
          _qrReady = false;
        });
      }

      // ✅ Preload/Decode รูป QR ให้เสร็จก่อน แล้วค่อยโชว์ (จะไม่สแปม log/ไม่กระตุก)
      if (fixedQr.isNotEmpty && mounted) {
        final provider = NetworkImage(fixedQr);
        await precacheImage(provider, context);
        if (mounted) {
          setState(() {
            _qrProvider = provider;
            _qrReady = true;
          });
        }
      }
    } catch (e) {
      debugPrint("🚨 error จากการโหลด contact-owner: $e");
    }
  }

  int? ownerId;

  Future<Map<String, dynamic>?> fetchOwnerApiInfo(int ownerId) async {
    final url = Uri.parse('$apiBaseUrl/api/owner/$ownerId');
    debugPrint('Fetching owner api info for ownerId: $ownerId');

    final response = await http.get(url).timeout(const Duration(seconds: 12));
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
    final uri = Uri.parse('$apiBaseUrl/api/upload-slip-image');

    // เดา mime จากชื่อไฟล์/ไบต์
    final mime =
        lookupMimeType(fileName, headerBytes: imageBytes) ?? 'image/jpeg';
    final parts = mime.split('/'); // ['image','jpeg']

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: fileName,
          contentType: MediaType(parts[0], parts[1]), // 👈 สำคัญ
        ),
      );

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 10));

    debugPrint('uploadSlipImage - Response status: ${resp.statusCode}');
    debugPrint('uploadSlipImage - Response body: ${resp.body}');

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data['error'] == false && data['fileUrl'] != null)
        return data['fileUrl'];
      throw Exception(
          'ไม่สามารถอัปโหลดรูปภาพได้: ${data['message'] ?? 'Unknown error'}');
    } else {
      throw Exception('อัปโหลดรูปภาพล้มเหลว: ${resp.statusCode} ${resp.body}');
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
      // STEP 1: ใช้คีย์จาก contact-owner
      final apiKey = (_apiKey ?? '').trim();
      final projectId = (_projectId ?? '').trim();
      if (apiKey.isEmpty || projectId.isEmpty) {
        await _showResultDialog(
            success: false,
            message: "ไม่พบ ApiKey/ProjectID จาก contact-owner");
        return;
      }

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

  // แถว key:value สั้นๆ
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 108,
                child: Text('$k: ',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );

// กล่องรายละเอียดสลิป
  Future<void> _showSlipDetailsDialog({
    required String senderName,
    required String bankName,
    required int amount,
    required DateTime dateTimeLocal,
    String? roomNumber,
    String? imageUrl,
    String? receiverName,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dateTimeLocal;
    final dateStr = '${d.year}-${two(d.month)}-${two(d.day)}';
    final timeStr = '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';

    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('รายละเอียดสลิป', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((roomNumber ?? '').isNotEmpty) _kv('ห้อง', roomNumber!),
            _kv('ผู้โอน', senderName),
            if ((receiverName ?? '').isNotEmpty) _kv('ผู้รับ', receiverName!),
            _kv('ธนาคารผู้โอน',
                bankName.isEmpty ? 'พร้อมเพย์/วอลเล็ต' : bankName),
            _kv('จำนวนเงิน', '$amount บาท'),
            const SizedBox(height: 8),
            _kv('วันที่', dateStr),
            _kv('เวลา', timeStr),
            if ((imageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('ไฟล์สลิป:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(imageUrl!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            child: const Text('ปิด'),
            onPressed: () => Navigator.pop(context),
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
    return NeumorphicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ ถ้ายังไม่พร้อม แสดง progress สั้น ๆ เฉย ๆ
          if (!_qrReady || _qrProvider == null)
            const SizedBox(
              height: 220,
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else
            // ✅ แสดงรูปตรง ๆ ไม่ใช้ loadingBuilder (ตัดสแปม)
            //   ให้เต็มกว้าง ไม่มีกรอบ ตามที่ขอ
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image(
                image: _qrProvider!,
                width: double.infinity,
                height: 260,
                fit: BoxFit.contain, // หรือ BoxFit.cover ถ้าอยากเต็มกว่า
                filterQuality: FilterQuality.low, // ลดงานเรนเดอร์
              ),
            ),
          const SizedBox(height: 12),
          Text(
            ownerName != null
                ? "ชื่อบัญชี: $ownerName"
                : "กำลังโหลดชื่อเจ้าของหอพัก...",
            style: const TextStyle(
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
    // ✅ ไม่มีการ์ด/กรอบ ใช้รูปเต็มความกว้าง
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          "แสดงตัวอย่างสลิป",
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Image.memory(
          _pickedImageBytes!,
          height: 420, // ← ขยายให้ใหญ่
          width: double.infinity,
          fit: BoxFit.contain, // ← ให้พอดีจอ ไม่บิดเบี้ยว
        ),
        const SizedBox(height: 8),
        if (_fileName != null)
          Text(_fileName!,
              style: const TextStyle(color: AppColors.textSecondary)),
      ],
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
