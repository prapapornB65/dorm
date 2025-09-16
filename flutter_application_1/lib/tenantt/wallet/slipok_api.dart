import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_application_1/config/api_config.dart';

final url = '$apiBaseUrl/api/some-endpoint';

/// ฟังก์ชันดึง API Key ของเจ้าของหอพัก
Future<String?> fetchApiKeyFromServer(int ownerId) async {
  final uri = Uri.parse('$apiBaseUrl/api/owner/$ownerId/apikey');
  try {
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['ApiKey'] as String?;
    } else {
      print('Error fetching API key: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('Exception fetching API key: $e');
    return null;
  }
}

/// ฟังก์ชันช่วยตัด substring อย่างปลอดภัย
String safeSubstring(String? str, int start, int end) {
  if (str == null) return "";
  if (start < 0) start = 0;
  if (end > str.length) end = str.length;
  if (start >= end) return "";
  return str.substring(start, end);
}

String formatDateTime(String? date, String? time) {
  if (date == null || date.length < 8 || time == null) return "";

  try {
    final year = date.substring(0, 4);
    final month = date.substring(4, 6);
    final day = date.substring(6, 8);

    String formattedTime;
    if (time.contains(':')) {
      formattedTime = time;
    } else if (time.length >= 6) {
      final hour = time.substring(0, 2);
      final minute = time.substring(2, 4);
      final second = time.substring(4, 6);
      formattedTime = "$hour:$minute:$second";
    } else {
      formattedTime = time;
    }

    return "$year-$month-$day $formattedTime";
  } catch (e) {
    debugPrint("❌ formatDateTime error: $e");
    return "";
  }
}

Future<dynamic> uploadToSlipOK(Uint8List imageBytes, String fileName,
    String apiKey, String projectId) async {
  final url = 'https://api.slipok.com/api/line/apikey/$projectId';

  final formData = FormData.fromMap({
    'files': MultipartFile.fromBytes(imageBytes, filename: fileName),
    'log': 'true',
  });

  final dio = Dio();

  try {
    debugPrint("📤 กำลังส่งไปยัง SlipOK...");
    debugPrint("📂 ขนาดไฟล์: ${imageBytes.lengthInBytes} bytes");
    debugPrint('URL: $url');
    debugPrint('API Key: $apiKey');
    debugPrint('Filename: $fileName');

    final response = await dio.post(
      url,
      data: formData,
      options: Options(
        headers: {
          'x-authorization': apiKey,
          'projectID': projectId,
        },
        validateStatus: (status) => status != null && status < 500,
      ),
      onSendProgress: (sent, total) {
        debugPrint('📤 กำลังส่ง: $sent / $total bytes');
      },
    );

    debugPrint("📄 Response code: ${response.statusCode}");
    debugPrint("📄 Body: ${response.data}");

    if (response.statusCode == 200) {
      return response.data is String
          ? jsonDecode(response.data)
          : response.data;
    } else {
      debugPrint("❌ ตรวจสอบล้มเหลว: ${response.statusCode}");
      return response.data is String ? jsonDecode(response.data) : response.data;
    }
  } catch (e) {
    debugPrint("❌ Upload ล้มเหลว: $e");
    return null;
  }
}
