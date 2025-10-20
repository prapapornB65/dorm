import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'auth/login_page.dart';

// ปลายทาง (ประกาศ route ไว้เฉย ๆ — จะถูกนำทางจาก LoginPage พร้อม id ที่ถูกต้อง)
import 'tenantt/main_navigation.dart';
import 'owner/building/building.dart' hide apiBaseUrl;
import 'admin/home/AdminDashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dorm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2AAE84),
      ),
      home: LoginPage(), // ✅ ให้ LoginPage จัดการ session + pending เอง
      routes: {
        '/LoginPage': (context) => LoginPage(),
        '/MainNavigation': (context) => MainNavigation(tenantId: 0),        // ตัวอย่าง
        '/BuildingSelection': (context) => BuildingSelectionScreen(ownerId: 0), // ตัวอย่าง
        '/AdminDashboard': (context) => CentralAdminDashboardScreen(adminId: 0), // ตัวอย่าง
      },
    );
  }
}
