import 'dart:convert';
import 'package:http/http.dart' as http;

/// ฟังก์ชันสำหรับบันทึกข้อมูลสลิปเข้าสู่ฐานข้อมูล MySQL
Future<void> saveSlipToServer({
  required String bank,
  required String amount,
  required String datetime,
  required String filename,
}) async {
  final url = Uri.parse(
      "http://10.0.2.2:3000/api/save-slip"); // เปลี่ยนเป็น IP จริงหากรันบนเครื่องอื่น

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'bank': bank,
      'amount': amount,
      'datetime': datetime,
      'filename': filename,
    }),
  );

  if (response.statusCode == 200) {
    print("✅ เก็บข้อมูลลง MySQL สำเร็จ");
  } else {
    print("❌ เก็บข้อมูลไม่สำเร็จ: ${response.body}");
  }

}
