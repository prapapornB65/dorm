import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

// ✅ override ได้จาก --dart-define ถ้าต้องการ
const String _envBase = String.fromEnvironment('TENANT_API_BASE_URL');

// ✅ เซ็ต true ตอนรันบน emulator: --dart-define=EMULATOR=true
const bool _isEmulator = bool.fromEnvironment('EMULATOR', defaultValue: false);

// ✅ IP ของ server ใน LAN (ใช้กับมือถือจริง)
const String _fixedBase = 'http://192.168.1.100:3000';

String _detectHostBase() {
  // 0) ถ้าระบุผ่าน --dart-define มาก็ใช้เลย
  if (_envBase.isNotEmpty) return _envBase;

  // 1) Web → localhost:3000
  if (kIsWeb) {
    return 'http://127.0.0.1:3000';
  }

  // 2) Mobile/Desktop
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      // Android Emulator → 10.0.2.2, มือถือจริง → _fixedBase
      return _isEmulator ? 'http://10.0.2.2:3000' : _fixedBase;

    case TargetPlatform.iOS:
      // iOS Simulator ใช้ localhost ได้ แต่เครื่องจริงต้องใช้ IP LAN
      // ถ้าจะบังคับ simulator ให้ใช้ localhost:3000 ให้ปลดคอมเมนต์บรรทัดล่าง
      // return 'http://localhost:3000';
      return _fixedBase;

    default:
      // Desktop dev
      return 'http://127.0.0.1:3000';
  }
}

final String apiBaseUrl = _detectHostBase();

String api(String path) {
  if (!path.startsWith('/')) path = '/$path';
  return '$apiBaseUrl$path';
}
