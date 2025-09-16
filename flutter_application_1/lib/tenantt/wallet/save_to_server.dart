// save_to_server.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/api_config.dart';

class SaveResult {
  final bool ok;
  final String message;
  final int statusCode;
  const SaveResult(
      {required this.ok, required this.message, required this.statusCode});
}

Future<SaveResult> saveSlipToServer({
  required int tenantId,
  required String tenantName,
  required String roomNumber,
  required String imagePath,
  required String senderName,
  required String bank,
  required int amount,
  required DateTime datetime,
  String? note,
  int? paymentId,
  String status = "ตรวจสอบแล้ว",
}) async {
  final url = Uri.parse('$apiBaseUrl/api/slipupload/$tenantId');

  final bodyMap = {
    "RoomNumber": roomNumber,
    "ImagePath": imagePath,
    "SenderName": senderName,
    "Note": note ?? '',
    "UploadDate": datetime.toIso8601String(),
    "amount": amount,
    "bank": bank,
    "status": status,
  };

  debugPrint("📤 เริ่มส่งข้อมูลสลิป.");
  debugPrint("🌐 URL: $url");
  debugPrint("📝 Payload Map: $bodyMap");

  try {
    final res = await http.post(
      url,
      body: jsonEncode(bodyMap),
      headers: {"Content-Type": "application/json"},
    );

    debugPrint("📥 Status Code: ${res.statusCode}");
    debugPrint("📄 Response Body: ${res.body}");

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return const SaveResult(
          ok: true, message: "บันทึกข้อมูลสลิปสำเร็จ", statusCode: 200);
    } else {
      return SaveResult(
          ok: false,
          message: "บันทึกสลิปล้มเหลว: HTTP ${res.statusCode}",
          statusCode: res.statusCode);
    }
  } catch (e) {
    return SaveResult(
        ok: false, message: "ผิดพลาดเครือข่าย/ระบบ: $e", statusCode: 0);
  }
}
