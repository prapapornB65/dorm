// login.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'Register_page.dart';
import 'package:flutter_application_1/tenantt/main_navigation.dart';
import 'package:flutter_application_1/owner/building/building.dart'
    hide apiBaseUrl;
import 'package:flutter_application_1/utils/shared_prefs_helper.dart';
import 'package:flutter_application_1/config/api_config.dart';

class ApiClient {
  final http.Client _client = http.Client();

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final base = {'Content-Type': 'application/json'};
    if (!auth) return base;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken(); // auto refresh
    return {...base, 'Authorization': 'Bearer $token'};
  }

  Future<http.Response> get(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.get(Uri.parse('$apiBaseUrl$path'), headers: headers);
  }

  Future<http.Response> post(String path,
      {Object? body, bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.post(Uri.parse('$apiBaseUrl$path'),
        headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> put(String path,
      {Object? body, bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.put(Uri.parse('$apiBaseUrl$path'),
        headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> delete(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.delete(Uri.parse('$apiBaseUrl$path'), headers: headers);
  }
}

/// ===== Palette / Theme =====
class AppColors {
  static const gradientStart = Color(0xFF0F6B54);
  static const gradientEnd = Color(0xFF57D2A3);

  static const primary = Color(0xFF2AAE84);
  static const primaryDark = Color(0xFF0E7A60);
  static const primaryLight = Color(0xFFE8F7F2);

  static const surface = Color(0xFFF2FAF7);
  static const card = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF10443B);
  static const textSecondary = Color(0xFF6A8F86);

  static const border = Color(0xFFE1F1EB);
  static const accent = Color(0xFFA7EAD8);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        surface: AppColors.surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.primaryDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
    );
  }
}

/// ===== Reusable Card =====
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0E7A60),
            offset: Offset(0, 10),
            blurRadius: 28,
            spreadRadius: -6,
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// ===== Login Page (NEW DESIGN) =====
class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final ApiClient api = ApiClient();

  String? _errorMessage;
  String? _emailError;
  String? _passwordError;
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _loginSuccess = false;

  int? _pendingTenantId;
  String _pendingStatus = 'pending';
  Timer? _statusTimer;
  int? _approvalId;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();

    // ถ้ายังล็อกอินค้างไว้ ให้ลองเช็ค role+status อัตโนมัติ
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      try {
        final idToken = await user.getIdToken(true);
        final resp = await api
            .post('/api/login', auth: false, body: {'idToken': idToken});
        if (resp.statusCode != 200) return;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final role = (data['role'] ?? '').toString();
        final int? id = (data['id'] as num?)?.toInt(); // ✅ อาจเป็น null
        final int? approvalId =
            (data['approvalId'] as num?)?.toInt(); // ✅ สำหรับคิวอนุมัติ
        final status = (data['status'] ?? '').toString().toLowerCase();

        if (role == 'tenant') {
          // ⬅️ อยู่ในคิวอนุมัติ (ยังไม่มี TenantID)
          if (id == null && approvalId != null) {
            if (!mounted) return;
            setState(() {
              _approvalId = approvalId;
              _pendingTenantId = null;
              _pendingStatus = status.isEmpty ? 'pending' : status;
            });
            _statusTimer?.cancel();
            _statusTimer = Timer.periodic(
                const Duration(seconds: 25), (_) => _pollApproval());
            return;
          }

          // ⬅️ มี TenantID แล้ว -> เช็กสถานะจากตาราง Tenant
          if (id != null) {
            final st = await api.get('/api/tenant/$id/status');
            if (st.statusCode == 200) {
              final s = (jsonDecode(st.body)['status'] ?? '')
                  .toString()
                  .toLowerCase();
              if (s == 'approved') {
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MainNavigation(tenantId: id)),
                );
              } else {
                if (!mounted) return;
                setState(() {
                  _pendingTenantId = id;
                  _pendingStatus = s.isEmpty ? 'pending' : s;
                });
                _statusTimer?.cancel();
                _statusTimer = Timer.periodic(const Duration(seconds: 25),
                    (_) => _checkPendingStatusOnce());
              }
            }
            return;
          }
        }

        // Owner
        if (role == 'owner' && id != null) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => BuildingSelectionScreen(ownerId: id)),
          );
          return;
        }
        // อื่น ๆ: ค้างที่หน้า Login เงียบ ๆ
      } catch (_) {
        // เงียบไว้
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pollApproval() async {
    if (_approvalId == null) return;
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken(true);
      final r = await http.get(
        Uri.parse('$apiBaseUrl/api/tenant-approval/${_approvalId}/status'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));

      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final s = (j['status'] ?? '').toString().toLowerCase();
        final tenantId = (j['tenantId'] as num?)?.toInt();

        setState(() => _pendingStatus = s);

        if (s == 'approved' && tenantId != null) {
          _statusTimer?.cancel();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => MainNavigation(tenantId: tenantId)),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _checkPendingStatusOnce() async {
    if (_pendingTenantId == null) return;
    try {
      final resp = await api.get('/api/tenant/${_pendingTenantId!}/status');
      if (resp.statusCode == 200) {
        final s =
            (jsonDecode(resp.body)['status'] ?? '').toString().toLowerCase();
        if (s == 'approved') {
          _statusTimer?.cancel();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => MainNavigation(tenantId: _pendingTenantId!)),
          );
          return;
        }
        if (mounted) setState(() => _pendingStatus = s);
      }
    } catch (_) {}
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await SharedPrefsHelper.getSavedEmail();
    if (!mounted) return;
    if (savedEmail != null) setState(() => _emailController.text = savedEmail);
  }

  Future<void> _signInWithEmailAndPassword() async {
    setState(() {
      _errorMessage = null;
      _emailError = null;
      _passwordError = null;
      _isLoading = true;
      _loginSuccess = false;
    });

    try {
      // 1) Firebase auth
      final cred = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final email = cred.user?.email ?? '';
      final idToken = await cred.user!.getIdToken(true);

      // 2) แลก token กับ backend (ไม่ต้องส่ง Bearer)
      final resp = await api.post(
        '/api/login',
        auth: false,
        body: {'idToken': idToken},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        throw Exception(body['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final role = (data['role'] ?? '').toString();
      final int? id = (data['id'] as num?)?.toInt(); // ✅ อาจเป็น null
      final int? approvalId =
          (data['approvalId'] as num?)?.toInt(); // ✅ สำหรับคิวอนุมัติ
      final statusFromLogin = (data['status'] ?? '').toString().toLowerCase();

      // 3) บันทึกค่าเบื้องต้น
      await SharedPrefsHelper.saveSavedEmail(email);
      if (role == 'tenant' && id != null) {
        await SharedPrefsHelper.saveTenantId(id);
      } else if (role == 'owner' && id != null) {
        await SharedPrefsHelper.saveOwnerId(id);
      }

      // 4) (เฉพาะ tenant) กรณี "รออนุมัติ" — ยังไม่มี TenantID แต่มี approvalId
      if (role == 'tenant' && id == null && approvalId != null) {
        if (!mounted) return;
        setState(() {
          _approvalId = approvalId;
          _pendingTenantId = null; // ยังไม่มี TenantID
          _pendingStatus =
              statusFromLogin.isEmpty ? 'pending' : statusFromLogin;
        });
        _statusTimer?.cancel();
        _statusTimer =
            Timer.periodic(const Duration(seconds: 25), (_) => _pollApproval());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บัญชีกำลังรออนุมัติ')),
        );
        return; // หยุดที่นี่ ไม่ต้องไปต่อ
      }

      // 4.1) (เฉพาะ tenant) มี TenantID แล้ว → เช็คสถานะที่ตาราง Tenant
      if (role == 'tenant' && id != null) {
        // ดึงชื่อ/owner เพิ่ม (ออปชัน)
        try {
          final infoResp = await http
              .get(Uri.parse('$apiBaseUrl/api/tenant-info?email=$email'))
              .timeout(const Duration(seconds: 12));
          if (infoResp.statusCode == 200) {
            final info = jsonDecode(infoResp.body) as Map<String, dynamic>;
            final tenantIdX = (info['TenantID'] as num?)?.toInt();
            final ownerId = (info['OwnerID'] as num?)?.toInt();
            final tenantName = (info['TenantName'] ?? '').toString();
            if (tenantIdX != null)
              await SharedPrefsHelper.saveTenantId(tenantIdX);
            if (ownerId != null) await SharedPrefsHelper.saveOwnerId(ownerId);
            await SharedPrefsHelper.saveTenantName(tenantName);
          }
        } catch (_) {}

        try {
          final statusResp = await api.get('/api/tenant/$id/status');
          if (statusResp.statusCode == 200) {
            final statusJson =
                jsonDecode(statusResp.body) as Map<String, dynamic>;
            final s = (statusJson['status'] ?? '').toString().toLowerCase();

            if (s != 'approved') {
              if (!mounted) return;
              setState(() {
                _pendingTenantId = id;
                _pendingStatus = s.isEmpty ? 'pending' : s;
              });
              _statusTimer?.cancel();
              _statusTimer = Timer.periodic(const Duration(seconds: 25),
                  (_) => _checkPendingStatusOnce());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บัญชีกำลังรออนุมัติ')),
              );
              return; // รออนุมัติที่หน้า Login
            }
            // approved → ไปต่อด้านล่าง
          } else {
            if (!mounted) return;
            setState(() {
              _pendingTenantId = id;
              _pendingStatus = 'pending';
            });
            _statusTimer?.cancel();
            _statusTimer = Timer.periodic(
                const Duration(seconds: 25), (_) => _checkPendingStatusOnce());
            return;
          }
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _pendingTenantId = id;
            _pendingStatus = 'pending';
          });
          _statusTimer?.cancel();
          _statusTimer = Timer.periodic(
              const Duration(seconds: 25), (_) => _checkPendingStatusOnce());
          return;
        }
      }

      // 5) เอฟเฟกต์ success + นำทาง
      if (!mounted) return;
      setState(() => _loginSuccess = true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      if (role == 'tenant' && id != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainNavigation(tenantId: id)),
        );
      } else if (role == 'owner' && id != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => BuildingSelectionScreen(ownerId: id)),
        );
      } else if (role == 'admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ล็อกอินเป็น Admin สำเร็จ (ยังไม่มีหน้าจอ)')),
        );
      } else {
        // โค้ดมาถึงตรงนี้แปลว่าไม่ได้เข้ากลุ่มไหน (เช่น tenant pending แต่ดันไม่มี approvalId)
        setState(() =>
            _errorMessage = 'ไม่สามารถกำหนดหน้าถัดไปได้ (role/id ไม่ครบ)');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'invalid-email':
            _emailError = 'รูปแบบอีเมลไม่ถูกต้อง';
            break;
          case 'user-not-found':
            _emailError = 'ไม่พบผู้ใช้ในระบบ';
            break;
          case 'wrong-password':
            _passwordError = 'รหัสผ่านไม่ถูกต้อง';
            break;
          case 'user-disabled':
            _errorMessage = 'บัญชีถูกปิดการใช้งาน';
            break;
          default:
            _errorMessage = 'เกิดข้อผิดพลาด: ${e.message}';
        }
      });
    } on http.ClientException {
      if (!mounted) return;
      setState(() => _errorMessage = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _errorMessage = 'การเชื่อมต่อหมดเวลา');
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ---------------- UI (DESIGN ONLY) ----------------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width.clamp(320.0, 420.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // วงแหวนโลโก้
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        _ring(96),
                        _ring(66),
                        _ring(40),
                        const Icon(Icons.home_outlined,
                            color: Colors.white, size: 36),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Dorm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'เข้าสู่ระบบด้วยอีเมลและรหัสผ่าน',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Email (pill)
                    _pillField(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _pillDecoration(
                          hint: 'Email',
                          icon: Icons.alternate_email,
                        ),
                      ),
                    ),
                    if (_emailError != null) ...[
                      const SizedBox(height: 6),
                      Text(_emailError!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 12),

                    // Password (pill)
                    _pillField(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _pillDecoration(
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          trailing: IconButton(
                            onPressed: () => setState(
                                () => _isPasswordVisible = !_isPasswordVisible),
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_passwordError != null) ...[
                      const SizedBox(height: 6),
                      Text(_passwordError!,
                          style: const TextStyle(color: Colors.red)),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                    ],

                    const SizedBox(height: 22),

                    // ปุ่มชมพูวงรี (เข้าสู่ระบบ)
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
                        // ถ้ากำลังโหลด หรือกำลัง "รออนุมัติ" → ปิดปุ่มไว้
                        onPressed: (_isLoading ||
                                _approvalId != null ||
                                _pendingTenantId != null)
                            ? null
                            : _signInWithEmailAndPassword,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: _isLoading ? 0.0 : 1.0,
                              child: Text(
                                _loginSuccess ? 'สำเร็จ' : 'เข้าสู่ระบบ',
                                style: const TextStyle(
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
                    const SizedBox(height: 12),

                    // === Pending Card (รองรับ approvalId, tenantId) ===
                    if (_approvalId != null || _pendingTenantId != null) ...[
                      const SizedBox(height: 14),
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: const [
                              Icon(Icons.hourglass_bottom,
                                  color: AppColors.primaryDark),
                              SizedBox(width: 8),
                              Text('บัญชีกำลังรออนุมัติ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 8),
                            if (_approvalId != null)
                              Text('หมายเลขคำขอ: #$_approvalId'),
                            Text('สถานะปัจจุบัน: $_pendingStatus'),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: (_approvalId != null)
                                      ? _pollApproval
                                      : _checkPendingStatusOnce,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('เช็คอีกครั้ง'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    _statusTimer?.cancel();
                                    await FirebaseAuth.instance.signOut();
                                    if (!mounted) return;
                                    setState(() {
                                      _approvalId = null;
                                      _pendingTenantId = null;
                                      _pendingStatus = 'pending';
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('ออกจากระบบแล้ว')),
                                    );
                                  },
                                  icon: const Icon(Icons.logout),
                                  label: const Text('ออกจากระบบ'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'เมื่อเจ้าของหออนุมัติแล้ว ระบบจะเด้งเข้าหน้าใช้งานให้อัตโนมัติ',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // ลิงก์สมัครสมาชิกเล็ก ๆ ด้านล่าง
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RegisterPage()),
                        );
                      },
                      child: Text(
                        'สมัครสมาชิก',
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
      hintStyle: TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      suffixIcon: trailing,
      border: InputBorder.none,
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );
  }
}
