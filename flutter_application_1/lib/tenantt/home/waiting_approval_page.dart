// lib/tenantt/waiting_approval_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/tenantt/main_navigation.dart'; // ปรับชื่อ/พาธให้ตรงโปรเจกต์คุณ

class WaitingApprovalPage extends StatefulWidget {
  final int tenantId;
  const WaitingApprovalPage({super.key, required this.tenantId});

  @override
  State<WaitingApprovalPage> createState() => _WaitingApprovalPageState();
}

class _WaitingApprovalPageState extends State<WaitingApprovalPage> {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    _check(); // เช็กครั้งแรกทันที
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/tenant/${widget.tenantId}/status'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final status =
            (jsonDecode(res.body)['status'] ?? '').toString().toLowerCase();
        if (status == 'approved' && mounted) {
          _timer?.cancel(); // กันโพลซ้ำก่อนนำทาง
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MainNavigation(tenantId: widget.tenantId),
            ),
          );
        }
      }
    } catch (_) {
      // จะโชว์ snackBar/alert แจ้งเน็ตหลุดก็ได้
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.hourglass_empty, size: 72, color: Colors.orange),
              SizedBox(height: 16),
              Text('คำขอของคุณกำลังรอการอนุมัติ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                  'เมื่อเจ้าของหออนุมัติแล้ว ระบบจะพาคุณเข้าสู่หน้าใช้งานอัตโนมัติ',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
