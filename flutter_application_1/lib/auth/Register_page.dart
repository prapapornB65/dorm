// Register_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ✅ เพิ่ม import Firebase Auth
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_application_1/auth/login_page.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // --------- FORM ---------
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _citizenIdController = TextEditingController();
  final _roomNumberController = TextEditingController();

  // (สำหรับ owner)
  final _apiKeyController = TextEditingController();
  final _projectIdController = TextEditingController();

  String _selectedRole = 'tenant';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _citizenIdController.dispose();
    _roomNumberController.dispose();
    _apiKeyController.dispose();
    _projectIdController.dispose();
    super.dispose();
  }

  // --------- VALIDATION ---------
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'กรุณากรอกอีเมล';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) return 'รูปแบบอีเมลไม่ถูกต้อง';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    if (value.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    return null;
  }

  (String first, String last) _splitFullName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return ('', '');
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return (first, last);
  }

  Map<String, dynamic> _safeJson(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  // --------- SUBMIT (แก้หลักอยู่ตรงนี้) ---------
  Future<void> _register() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'รหัสผ่านไม่ตรงกัน');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _nameController.text.trim();
    final parts = fullName.split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    UserCredential? cred;

    try {
      // 1) สมัคร Firebase
      cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      await cred.user?.updateDisplayName(fullName);

      // 2) เลือก endpoint ตาม role
      late Uri url;
      late Map<String, dynamic> payload;

      if (_selectedRole == 'tenant') {
        url = Uri.parse('$apiBaseUrl/api/tenant/register');
        payload = {
          'firstName': firstName,
          'lastName': lastName,
          'citizenID': _citizenIdController.text.trim(),
          'email': email,
          'phone': _phoneController.text.trim(),
          'username': _usernameController.text.trim(),
          'password': password,
          'roomNumber': _roomNumberController.text.trim(),
        };
      } else if (_selectedRole == 'owner') {
        url = Uri.parse('$apiBaseUrl/api/owner/register');
        payload = {
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'phone': _phoneController.text.trim(),
          'citizenId': _citizenIdController.text.trim(),
          'username': _usernameController.text.trim(),
          'password': password,
          'apiKey': _apiKeyController.text.trim(),
          'projectId': _projectIdController.text.trim(),
        };
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'สมัครผู้ดูแลระบบทำในระบบหลังบ้าน';
        });
        return;
      }

      // 3) ยิง backend “ครั้งเดียว”
      final resp = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('[REGISTER] ${url.path} -> ${resp.statusCode} ${resp.body}');

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        // rollback firebase ถ้าหลังบ้านไม่ผ่าน
        try {
          await cred.user?.delete();
        } catch (_) {}
        final msg = resp.body.isNotEmpty
            ? (jsonDecode(resp.body)['error'] ?? resp.body)
            : '';
        setState(
            () => _errorMessage = 'สมัครไม่สำเร็จ (${resp.statusCode}) ${msg}');
        return;
      }

      // 4) นำทางกลับหน้า Login (ยังคง session ไว้ เพื่อให้ LoginPage โชว์การ์ด "รออนุมัติ")
      if (!mounted) return;
      if (_selectedRole == 'tenant') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งคำขอสมัครแล้ว กำลังรออนุมัติ')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ส่งคำขอสมัครเจ้าของหอแล้ว รอผู้ดูแลอนุมัติ')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      // แสดง error ที่เข้าใจง่าย + rollback ถ้าจำเป็น
      String msg = 'สมัครไม่สำเร็จ';
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'อีเมลนี้ถูกใช้ไปแล้ว';
          break;
        case 'invalid-email':
          msg = 'อีเมลไม่ถูกต้อง';
          break;
        case 'weak-password':
          msg = 'รหัสผ่านอ่อนเกินไป (อย่างน้อย 8 ตัวอักษร)';
          break;
        case 'operation-not-allowed':
          msg = 'โปรดเปิด Email/Password ใน Firebase Console';
          break;
        default:
          msg = e.message ?? msg;
      }
      try {
        await cred?.user?.delete();
      } catch (_) {}
      if (mounted) setState(() => _errorMessage = msg);
    } on TimeoutException {
      try {
        await cred?.user?.delete();
      } catch (_) {}
      if (mounted) setState(() => _errorMessage = 'เชื่อมต่อช้า โปรดลองใหม่');
    } catch (e) {
      try {
        await cred?.user?.delete();
      } catch (_) {}
      if (mounted) setState(() => _errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- UI (DESIGN) ----------
  static const Color _gStart = Color(0xFF0F6B54);
  static const Color _gEnd = Color(0xFF57D2A3);
  static const Color _textPrimary = Color(0xFF10443B);
  static const Color _textSecondary = Color(0xFF6A8F86);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width.clamp(320.0, 520.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_gStart, _gEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F6B54), Color(0xFF2FB78F)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(0, 10),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          _ring(96),
                          _ring(66),
                          _ring(40),
                          const Icon(Icons.person_add_alt_1,
                              color: Colors.white, size: 36),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'สมัครสมาชิก',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _selectedRole == 'tenant'
                            ? 'กรอกข้อมูลเพื่อสมัครผู้เช่า (รอเจ้าของหออนุมัติ)'
                            : _selectedRole == 'owner'
                                ? 'กรอกข้อมูลเพื่อสมัครเจ้าของหอพัก (รอผู้ดูแลระบบอนุมัติ)'
                                : 'สมัครผู้ดูแลระบบทำในระบบหลังบ้าน',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9), height: 1.25),
                      ),
                      const SizedBox(height: 22),
                      _pillField(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<String>(
                            value: _selectedRole,
                            decoration: _pillDecoration(
                              hint: 'บทบาทผู้ใช้',
                              icon: Icons.badge_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'tenant', child: Text('ผู้เช่า')),
                              DropdownMenuItem(
                                  value: 'owner', child: Text('เจ้าของหอพัก')),
                              DropdownMenuItem(
                                  value: 'admin', child: Text('ผู้ดูแลระบบ')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedRole = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _nameController,
                          decoration: _pillDecoration(
                              hint: 'ชื่อ - นามสกุล', icon: Icons.person),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'กรุณากรอกชื่อ - นามสกุล';
                            final parts = v.trim().split(RegExp(r'\s+'));
                            if (parts.length < 2)
                              return 'กรุณากรอกทั้งชื่อและนามสกุล';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _usernameController,
                          decoration: _pillDecoration(
                              hint: 'ชื่อผู้ใช้ (ถ้ามี)',
                              icon: Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _pillDecoration(
                              hint: 'อีเมล', icon: Icons.alternate_email),
                          validator: _validateEmail,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _pillDecoration(
                              hint: 'เบอร์โทรศัพท์', icon: Icons.phone),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'กรุณากรอกเบอร์โทรศัพท์'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _citizenIdController,
                          keyboardType: TextInputType.number,
                          decoration: _pillDecoration(
                              hint: 'รหัสบัตรประชาชน', icon: Icons.credit_card),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'กรุณากรอกรหัสบัตรประชาชน'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedRole == 'tenant') ...[
                        _pillField(
                          child: TextFormField(
                            controller: _roomNumberController,
                            decoration: _pillDecoration(
                                hint: 'หมายเลขห้องพัก',
                                icon: Icons.meeting_room_outlined),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'กรุณากรอกหมายเลขห้องพัก'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_selectedRole == 'owner') ...[
                        _pillField(
                          child: TextFormField(
                            controller: _apiKeyController,
                            decoration: _pillDecoration(
                                hint: 'Tuya Api Key', icon: Icons.vpn_key),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'กรุณากรอก Api Key'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _pillField(
                          child: TextFormField(
                            controller: _projectIdController,
                            decoration: _pillDecoration(
                                hint: 'Tuya Project ID',
                                icon: Icons.settings_applications),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'กรุณากรอก Project ID'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _pillField(
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: _pillDecoration(
                              hint: 'รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)',
                              icon: Icons.lock_outline),
                          validator: _validatePassword,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pillField(
                        child: TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: _pillDecoration(
                              hint: 'ยืนยันรหัสผ่าน', icon: Icons.lock_reset),
                          validator: _validatePassword,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B6B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _isLoading ? null : _register,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: _isLoading ? 0.0 : 1.0,
                                child: const Text(
                                  'ลงทะเบียน',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              if (_isLoading)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => LoginPage()),
                          );
                        },
                        child: Text(
                          'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------- UI helpers --------
  Widget _ring(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 2,
        ),
      ),
    );
  }

  Widget _pillField({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: child,
    );
  }

  InputDecoration _pillDecoration({
    required String hint,
    required IconData icon,
    Widget? trailing,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _textSecondary),
      prefixIcon: Icon(icon, color: _textSecondary),
      suffixIcon: trailing,
      border: InputBorder.none,
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );
  }
}
