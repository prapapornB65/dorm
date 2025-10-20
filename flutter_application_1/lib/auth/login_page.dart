// login.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'Register_page.dart';
import 'package:flutter_application_1/tenantt/main_navigation.dart';
import 'package:flutter_application_1/owner/building/building.dart';
import 'package:flutter_application_1/utils/shared_prefs_helper.dart';
import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/admin/home/AdminDashboard.dart';

class ApiClient {
  final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 8);

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final base = {'Content-Type': 'application/json'};
    if (!auth) return base;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken(); // auto refresh
    return {...base, 'Authorization': 'Bearer $token'};
  }

  Uri _u(String path) => Uri.parse('$apiBaseUrl$path');

  Future<http.Response> get(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    debugPrint('[API][GET] ${_u(path)}');
    return _client.get(_u(path), headers: headers).timeout(_timeout);
  }

  Future<http.Response> post(String path,
      {Object? body, bool auth = true}) async {
    final headers = await _headers(auth: auth);
    debugPrint('[API][POST] ${_u(path)} body=$body');
    return _client
        .post(_u(path), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
  }

  Future<http.Response> put(String path,
      {Object? body, bool auth = true}) async {
    final headers = await _headers(auth: auth);
    debugPrint('[API][PUT] ${_u(path)} body=$body');
    return _client
        .put(_u(path), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
  }

  Future<http.Response> delete(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    debugPrint('[API][DELETE] ${_u(path)}');
    return _client.delete(_u(path), headers: headers).timeout(_timeout);
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
  bool _lookupLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();

    // ✅ Silent auto-login: navigate เมื่อ approved เท่านั้น
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      try {
        final idToken = await user.getIdToken(true);
        final resp = await api
            .post('/api/login', auth: false, body: {'idToken': idToken});
        if (resp.statusCode != 200) return;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final role = (data['role'] ?? '').toString().trim().toLowerCase();
        final int? id = (data['id'] is num)
            ? (data['id'] as num).toInt()
            : int.tryParse('${data['id'] ?? data['userId'] ?? ''}');

        if (role == 'tenant' && id != null) {
          // เช็คสถานะตาราง Tenant แบบเงียบ ๆ
          final st = await api.get('/api/tenant/$id/status');
          if (st.statusCode == 200) {
            final s =
                (jsonDecode(st.body)['status'] ?? '').toString().toLowerCase();
            if (s == 'approved' && mounted) {
              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MainNavigation(tenantId: id)));
            }
          }
        } else if (role == 'owner' && id != null && mounted) {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => BuildingSelectionScreen(ownerId: id)));
        }
        // ถ้ายังไม่ approved → เงียบไว้ ไม่โชว์การ์ด
      } catch (_) {/* เงียบ */}
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _lookupApprovalByEmail(String email) async {
    if (email.isEmpty) {
      setState(() => _emailError = 'กรอกอีเมลก่อนตรวจสถานะ');
      return;
    }
    setState(() {
      _lookupLoading = true;
      _errorMessage = null;
    });

    try {
      // ตัวอย่าง endpoint: ปรับ path ให้ตรงกับหลังบ้านคุณ
      final url =
          Uri.parse('$apiBaseUrl/api/tenant-approval/lookup?email=$email');
      final r = await http.get(url).timeout(const Duration(seconds: 12));

      if (r.statusCode == 404) {
        setState(() {
          _approvalId = null;
          _pendingStatus = 'not_found';
          _errorMessage = 'ไม่พบคำขอสมัครด้วยอีเมลนี้';
        });
        return;
      }
      if (r.statusCode != 200) {
        setState(() => _errorMessage = 'ตรวจสถานะไม่สำเร็จ (${r.statusCode})');
        return;
      }

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final status = (j['status'] ?? 'pending').toString().trim().toLowerCase();
      final approvalId = (j['approvalId'] as num?)?.toInt();
      final tenantId = (j['tenantId'] as num?)?.toInt();

      if (status == 'approved' && tenantId != null) {
        // อนุมัติแล้ว ⇒ ตอนนี้คุณควรสามารถล็อกอินได้ปกติด้วยอีเมล/รหัสผ่าน
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติแล้ว • ลองเข้าสู่ระบบได้เลย')),
        );
        setState(() {
          _approvalId = null;
          _pendingStatus = 'approved';
        });
        return;
      }

      // pending / rejected ⇒ โชว์การ์ด + ตั้ง timer poll
      setState(() {
        _approvalId = approvalId;
        _pendingStatus = status;
      });

      _statusTimer?.cancel();
      if (approvalId != null && status == 'pending') {
        _statusTimer =
            Timer.periodic(const Duration(seconds: 25), (_) => _pollApproval());
      }
    } catch (_) {
      setState(() => _errorMessage = 'เชื่อมต่อไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  Future<void> _pollApproval() async {
    if (_approvalId == null) return;
    try {
      // ไม่ต้องใช้ token
      final r = await http
          .get(Uri.parse(
              '$apiBaseUrl/api/tenant-approval/${_approvalId}/status'))
          .timeout(const Duration(seconds: 12));

      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final s = (j['status'] ?? '').toString().trim().toLowerCase();
        final tenantId = (j['tenantId'] as num?)?.toInt();

        setState(() => _pendingStatus = s);

        if (s == 'approved' && tenantId != null) {
          _statusTimer?.cancel();
          if (!mounted) return;

          final signedIn = FirebaseAuth.instance.currentUser != null;
          if (signedIn) {
            // เคสมี session อยู่ → เข้าแอปได้เลย
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => MainNavigation(tenantId: tenantId)),
            );
          } else {
            // ยังไม่ได้ล็อกอิน → แจ้งเตือนและปลดล็อกปุ่ม
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('อนุมัติแล้ว • กรุณาเข้าสู่ระบบ')),
            );
            setState(() {
              _approvalId = null; // ปลดล็อกปุ่มเข้าสู่ระบบ
              _pendingTenantId = null;
              _pendingStatus = 'approved';
            });
          }
        }
      }
    } catch (_) {
      // เงียบได้
    }
  }

  Future<void> _checkPendingStatusOnce() async {
    if (_pendingTenantId == null) return;
    try {
      final resp = await api.get('/api/tenant/${_pendingTenantId!}/status');
      if (resp.statusCode == 200) {
        final s = (jsonDecode(resp.body)['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
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
      debugPrint('[LOGIN] /api/login -> ${resp.statusCode}  body=${resp.body}');
      if (resp.statusCode != 200) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        throw Exception(body['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

// ทำให้ robust ต่อรูปแบบ response ต่างๆ
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      final dynamic _rawId = data['id'] ?? data['userId'];
      final int? id =
          (_rawId is num) ? _rawId.toInt() : int.tryParse(('$_rawId'));
      final dynamic _rawApproval = data['approvalId'] ?? data['approval_id'];
      final int? approvalId = (_rawApproval is num)
          ? _rawApproval.toInt()
          : int.tryParse(('$_rawApproval'));
      final statusFromLogin =
          (data['status'] ?? '').toString().trim().toLowerCase();

      await SharedPrefsHelper.saveSavedEmail(email);
      if (role == 'tenant') {
        await _resolveTenantState(
          email: email,
          tenantId: id,
          approvalId: approvalId,
          statusFromLogin: statusFromLogin,
          showUi: true,
        );
        setState(() => _isLoading = false);
        return; // จบที่นี่ ไม่ต้องไปส่วน owner/admin
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
            final s =
                (statusJson['status'] ?? '').toString().trim().toLowerCase();

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
        // ✅ เรียกโปรวิชัน (ทำครั้งแรก/ซ้ำก็ไม่พัง)
        try {
          await api.post('/api/tenant/$id/provision'); // แค่บรรทัดนี้
        } catch (_) {}

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
      } else if (role == 'admin' && id != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CentralAdminDashboardScreen(adminId: id),
          ),
        );
      } else if (role == 'admin' && id == null) {
        setState(() => _errorMessage = 'ไม่พบ adminId จากเซิร์ฟเวอร์');
      } else {
        // โค้ดมาถึงตรงนี้แปลว่าไม่ได้เข้ากลุ่มไหน (เช่น tenant pending แต่ดันไม่มี approvalId)
        setState(() =>
            _errorMessage = 'ไม่สามารถกำหนดหน้าถัดไปได้ (role/id ไม่ครบ)');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'user-not-found':
          // ✅ ผู้เช่ายังไม่มี Firebase user เพราะยังไม่อนุมัติ
          await _lookupApprovalByEmail(_emailController.text.trim());
          break;
        case 'invalid-email':
          setState(() => _emailError = 'รูปแบบอีเมลไม่ถูกต้อง');
          break;
        case 'wrong-password':
          setState(() => _passwordError = 'รหัสผ่านไม่ถูกต้อง');
          break;
        case 'user-disabled':
          setState(() => _errorMessage = 'บัญชีถูกปิดการใช้งาน');
          break;
        default:
          setState(() => _errorMessage = 'เกิดข้อผิดพลาด: ${e.message}');
      }
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

  Future<void> _resolveTenantState({
    required String email,
    int? tenantId,
    int? approvalId,
    String? statusFromLogin,
    bool showUi = true,
  }) async {
    String norm(String? s) => (s ?? '').trim().toLowerCase();

    // 1) เช็คด้วย tenantId ก่อน
    if (tenantId != null) {
      try {
        final st = await api.get('/api/tenant/$tenantId/status');
        debugPrint(
            '[LOGIN] GET /tenant/$tenantId/status -> ${st.statusCode} ${st.body}');
        if (st.statusCode == 200) {
          final s = norm(jsonDecode(st.body)['status']);
          if (s == 'approved') {
            if (!mounted) return;
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => MainNavigation(tenantId: tenantId)));
            return;
          }
        }
      } catch (_) {}
    }

    // 2) เช็คซ้ำด้วย email (ใช้สถานะจาก TenantApproval เป็นหลัก)
    try {
      final r = await http
          .get(Uri.parse('$apiBaseUrl/api/tenant-status-by-email?email=$email'))
          .timeout(const Duration(seconds: 12));
      debugPrint(
          '[LOGIN] GET /tenant-status-by-email -> ${r.statusCode} ${r.body}');
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final s = norm(j['status']);
        final tid = (j['tenantId'] as num?)?.toInt() ?? tenantId;

        if (s == 'approved' && tid != null) {
          if (!mounted) return;
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => MainNavigation(tenantId: tid)));
          return;
        }

        if (showUi && mounted) {
          setState(() {
            _approvalId = (j['approvalId'] as num?)?.toInt() ?? approvalId;
            _pendingTenantId = tid;
            _pendingStatus = s.isEmpty ? 'pending' : s;
          });
          _statusTimer?.cancel();
          if (_approvalId != null && _pendingStatus == 'pending') {
            _statusTimer = Timer.periodic(
                const Duration(seconds: 25), (_) => _pollApproval());
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บัญชีกำลังรออนุมัติ')),
          );
        }
        return;
      }
    } catch (_) {}

    // 3) กันตก
    if (showUi && mounted) {
      setState(() {
        _approvalId = approvalId;
        _pendingTenantId = tenantId;
        _pendingStatus =
            norm(statusFromLogin).isEmpty ? 'pending' : norm(statusFromLogin);
      });
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
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                _isLoading ? null : _signInWithEmailAndPassword,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: _isLoading ? 0.0 : 1.0,
                                  child: Text(
                                      _loginSuccess ? 'สำเร็จ' : 'เข้าสู่ระบบ',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
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
                      ],
                    ),

                    const SizedBox(height: 12),

                    // === Pending Card (รองรับ approvalId, tenantId) ===
                    if (_approvalId != null || _pendingTenantId != null) ...[
                      const SizedBox(height: 14),
                      SoftCard(
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
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: (_approvalId != null)
                                      ? _pollApproval
                                      : _checkPendingStatusOnce,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('เช็คอีกครั้ง',
                                      overflow: TextOverflow.ellipsis),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    _statusTimer?.cancel();
                                    setState(() {
                                      _approvalId = null;
                                      _pendingTenantId = null;
                                      _pendingStatus = 'pending';
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('ซ่อนการ์ด',
                                      overflow: TextOverflow.ellipsis),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'เมื่อเจ้าของหออนุมัติแล้ว คุณจะสามารถเข้าสู่ระบบได้ทันที',
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
