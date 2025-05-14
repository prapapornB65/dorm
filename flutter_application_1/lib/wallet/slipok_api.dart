import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// อัปโหลดรูปสลิปไปยัง SlipOK API
Future<Map<String, dynamic>?> uploadToSlipOK(
    Uint8List imageBytes, String fileName) async {
  // ✅ ใช้ branch ID จริงจากระบบ SlipOK
  const apiKey = "SLIPOKXDJKDDR"; // ← และตรงนี้

  final uri = Uri.parse("https://api.slipok.com/api/line/apikey/45205");

  final request = http.MultipartRequest("POST", uri)
    ..headers['x-authorization'] = apiKey
    ..files.add(
      http.MultipartFile.fromBytes(
        'files',
        imageBytes,
        filename: fileName,
      ),
    )
    ..fields['log'] = 'true'; // ✅ บอกให้ระบบเก็บ log เพื่อตรวจซ้ำได้

  try {
  print("📤 กำลังส่งไปยัง SlipOK...");
  print("📂 ขนาดไฟล์: ${imageBytes.length} bytes");

  final response = await request.send();
  final responseBody = await response.stream.bytesToString();

  print("📄 Response code: ${response.statusCode}");
  print("📄 Body: $responseBody");

  if (response.statusCode == 200) {
    final jsonResp = jsonDecode(responseBody);
    print("✅ อัปโหลดสำเร็จ: $jsonResp");
    return jsonResp['data'];
  } else {
    final jsonResp = jsonDecode(responseBody);
    final message = jsonResp['message'] ?? '';

    if (message.contains("สลิปซ้ำ")) {
      print("❗ สลิปซ้ำ: $message");
      return {
        'error': true,
        'message': "❗ สลิปนี้ถูกใช้ไปแล้ว\nกรุณาอัปโหลดสลิปใหม่"
      };
    }

    print("❌ ตรวจสอบล้มเหลว: ${response.statusCode}");
    print("📄 Response: $responseBody");
    return null;
  }
} catch (e) {
  print("🚨 เกิดข้อผิดพลาด: $e");
  return null;
}

}
