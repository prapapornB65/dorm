import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'firebase_options.dart';
import 'auth/login_page.dart';
import 'tenantt/main_navigation.dart';
import 'owner/building/building.dart' hide apiBaseUrl;
import 'admin/home/AdminDashboard.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Sign out ผู้ใช้ทุกครั้งตอนเปิดแอป (สำหรับ dev)
  await FirebaseAuth.instance.signOut();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-role Auth App',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const AuthWrapper(),
      routes: {
        '/LoginPage': (context) => LoginPage(),
        '/MainNavigation': (context) => MainNavigation(tenantId: 0), // ตัวอย่าง
        '/BuildingSelection': (context) =>
            BuildingSelectionScreen(ownerId: 0), // ตัวอย่าง
        '/AdminDashboard': (context) =>
            CentralAdminDashboardScreen(adminId: 0), // ตัวอย่าง
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!authSnapshot.hasData || authSnapshot.data == null) {
          return LoginPage();
        }

        final firebaseUser = authSnapshot.data!;
        final uid = firebaseUser.uid;

        return FutureBuilder<Map<String, dynamic>>(
          future: fetchUserRoleByUID(uid),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (roleSnapshot.hasError) {
              return Scaffold(
                body: Center(
                    child: Text("เกิดข้อผิดพลาด: ${roleSnapshot.error}")),
              );
            }

            final roleData = roleSnapshot.data!;
            final role = roleData['role'];
            final userId = roleData['userId'];

            switch (role) {
              case 'tenant':
                return MainNavigation(tenantId: userId);
              case 'owner':
                return BuildingSelectionScreen(ownerId: userId);
              case 'admin':
                return CentralAdminDashboardScreen(adminId: userId);
              default:
                return const Scaffold(
                  body: Center(child: Text("ไม่รู้จักบทบาทผู้ใช้")),
                );
            }
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> fetchUserRoleByUID(String uid) async {
    final baseUrl = _resolveBaseUrl();
    final url = Uri.parse('$baseUrl/api/user-role-by-uid/$uid');

    print('[DEBUG] Request URL: $url');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      print('[DEBUG] Response status: ${response.statusCode}');
      print('[DEBUG] Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
            'ไม่สามารถดึง role ได้: ${response.statusCode} ${response.body}');
      }
    } on Exception catch (e) {
      print('[ERROR] Fetch user role failed: $e');
      throw Exception('เกิดข้อผิดพลาดขณะดึง role: $e');
    }
  }

  /// อ่านจาก api_config.dart และแก้กรณี Android emulator ถ้า config เป็น localhost
  String _resolveBaseUrl() {
    var base = apiBaseUrl.trim();
    final uri = Uri.tryParse(base);

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid &&
        uri != null &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      base = uri.replace(host: '10.0.2.2').toString();
    }
    return base;
  }
}
