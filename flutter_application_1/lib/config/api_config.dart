// lib/tenantt/config/api_config.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

// อ่านจาก --dart-define (ถ้ามี)
const String _envBase =
    String.fromEnvironment('TENANT_API_BASE_URL');

// ← ใส่ IP ของเซิร์ฟเวอร์ใน LAN ของคุณตรงนี้
// เช่น http://192.168.1.69:3000
const String _fixedBase = 'http://192.168.1.100:3000';

String _detectHostBase() {
  // 1) ใช้ค่าจาก --dart-define ถ้ามี
  if (_envBase.isNotEmpty) return _envBase;

  // 2) ใช้ค่า IP ตายตัวที่กำหนดไว้
  if (_fixedBase.isNotEmpty) return _fixedBase;

  // 3) ไม่มีก็ fallback ตามแพลตฟอร์ม
  if (kIsWeb) {
    final origin = Uri.base.origin;
    return origin.contains('localhost') ? 'http://localhost:3000' : origin;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:3000'; // สำหรับ Android emulator
    default:
      return 'http://localhost:3000';
  }
}

final String apiBaseUrl = _detectHostBase();

String api(String path) {
  if (!path.startsWith('/')) path = '/$path';
  return '$apiBaseUrl$path';
}
