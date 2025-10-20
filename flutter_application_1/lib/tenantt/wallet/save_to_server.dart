// save_to_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/api_config.dart';

class SaveResult {
  final bool ok;
  final String message;
  final int statusCode;
  final int? paymentId;
  final int? slipId;

  const SaveResult({
    required this.ok,
    required this.message,
    required this.statusCode,
    this.paymentId,
    this.slipId,
  });

  @override
  String toString() =>
      'SaveResult(ok=$ok, code=$statusCode, paymentId=$paymentId, slipId=$slipId, msg="$message")';
}

Future<SaveResult> saveSlipToServer({
  required int tenantId,
  required String tenantName, // เผื่อใช้อนาคต แม้ backend ยังไม่อ่านค่านี้
  required String roomNumber,
  required String imagePath,
  required String senderName,
  required String bank,       // ส่ง "ชื่อธนาคาร" มาแล้ว เช่น "กรุงเทพ"
  required int amount,
  required DateTime datetime,
  String? note,
  int? paymentId,
  String status = "verified", // ✅ default เป็น "verified"
}) async {
  final url = Uri.parse('$apiBaseUrl/api/slipupload/$tenantId');

  final bodyMap = <String, dynamic>{
    "RoomNumber": roomNumber,
    "ImagePath": imagePath,
    "SenderName": senderName,
    if (note != null) "Note": note,
    "UploadDate": datetime.toIso8601String(),
    "amount": amount,
    "bank": bank,
    "status": status,
    if (paymentId != null) "paymentId": paymentId,
  };

  if (kDebugMode) {
    debugPrint("📤 [saveSlipToServer] POST $url");
    debugPrint("📝 payload: ${jsonEncode(bodyMap)}");
  }

  const int maxRetry = 2; // รวมเป็น 3 ครั้ง (ครั้งแรก + 2 retry)
  for (int attempt = 0; attempt <= maxRetry; attempt++) {
    final tryNo = attempt + 1;
    try {
      final res = await http
          .post(
            url,
            body: jsonEncode(bodyMap),
            headers: const {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
          )
          .timeout(const Duration(seconds: 12));

      final code = res.statusCode;
      final body = res.body;

      if (kDebugMode) {
        debugPrint("📥 [saveSlipToServer] attempt=$tryNo status=$code");
        debugPrint("📄 [saveSlipToServer] body=$body");
      }

      Map<String, dynamic>? decoded;
      try {
        if (body.isNotEmpty) {
          final d = jsonDecode(body);
          if (d is Map<String, dynamic>) decoded = d;
        }
      } catch (_) {/* ไม่เป็น JSON ก็ปล่อยผ่าน */}

      // กรณี 2xx แต่ฝั่ง server ส่ง ok=false หรือมี error
      if (code >= 200 && code < 300) {
        final bool okFlag = (decoded?['ok'] == true) || (decoded?['error'] == false);
        final serverMsg = (decoded?['message']?.toString() ?? "OK");
        final pid = (decoded?['paymentId'] is num) ? (decoded?['paymentId'] as num).toInt() : null;
        final sid = (decoded?['slipId'] is num) ? (decoded?['slipId'] as num).toInt() : null;

        if (!okFlag) {
          // server ตอบ 200 แต่สถานะธุรกิจไม่ผ่าน
          return SaveResult(ok: false, message: serverMsg, statusCode: code);
        }

        return SaveResult(
          ok: true,
          message: serverMsg,
          statusCode: code,
          paymentId: pid,
          slipId: sid,
        );
      }

      // 4xx/5xx
      String serverMsg = "HTTP $code";
      if (decoded != null) {
        serverMsg = decoded?['message']?.toString() ??
            decoded?['error']?.toString() ??
            serverMsg;
      }

      // retry เฉพาะ 5xx
      if (code >= 500 && attempt < maxRetry) {
        if (kDebugMode) {
          debugPrint("🔁 [saveSlipToServer] retry on 5xx (attempt=$tryNo)");
        }
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      return SaveResult(ok: false, message: "บันทึกสลิปล้มเหลว: $serverMsg", statusCode: code);

    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint("⏳ [saveSlipToServer] timeout (attempt=$tryNo): $e");
      }
      if (attempt < maxRetry) {
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      return const SaveResult(
        ok: false,
        message: "บันทึกข้อมูลสลิปไม่สำเร็จ: เซิร์ฟเวอร์ตอบช้าเกินกำหนด",
        statusCode: 0,
      );

    } on SocketException catch (e) {
      if (kDebugMode) {
        debugPrint("🌐 [saveSlipToServer] socket error (attempt=$tryNo): $e");
      }
      if (attempt < maxRetry) {
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      return SaveResult(
        ok: false,
        message: "บันทึกข้อมูลสลิปไม่สำเร็จ: เครือข่ายผิดพลาด ($e)",
        statusCode: 0,
      );

    } catch (e) {
      if (kDebugMode) {
        debugPrint("🛑 [saveSlipToServer] unexpected error: $e");
      }
      // บั๊กฝั่งแอป/serialization ไม่ควร retry
      return SaveResult(
        ok: false,
        message: "บันทึกข้อมูลสลิปไม่สำเร็จ: $e",
        statusCode: 0,
      );
    }
  }

  // ปกติจะไม่ถึงตรงนี้
  return const SaveResult(
    ok: false,
    message: "บันทึกข้อมูลสลิปไม่สำเร็จ: ไม่ทราบสาเหตุ",
    statusCode: 0,
  );
}
