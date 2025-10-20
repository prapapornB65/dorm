import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';

class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: 'SFPro', // เปลี่ยนเป็นฟอนต์ที่คุณใช้จริง

    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
      error: Colors.red.shade400,
      onError: Colors.white,
      background: AppColors.surface,
      onBackground: AppColors.textPrimary,
      surface: AppColors.card,
      onSurface: AppColors.textPrimary,
    ),

    // AppBar โปร่งนิดๆ + โค้งมน
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),

    // ปุ่มหลัก (ใช้ AppButton ด้านล่างจะได้ gradient; ส่วนนี้กำหนด Elevated ให้โค้งไว้ก่อน)
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
    ),

    // ฟิลด์กรอก: โค้ง นุ่ม สีเขียวอ่อน
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.primaryLight,
      hintStyle: TextStyle(color: AppColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
    ),

    // Card โค้งใหญ่ เงานุ่ม
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),

    // ListTile ให้ลุคสะอาด
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
      dense: true,
    ),

    // BottomNavigationBar โค้งนุ่ม
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}

/// พื้นหลังไล่สีแบบในภาพ
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,

    // ⬇️ เพิ่มพารามิเตอร์ควบคุมมุมบน (0 = ไม่โค้ง)
    this.topRadius = 0,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final double topRadius; // ⬅️ เพิ่ม

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: SafeArea(
          child: Container(
            // กันสีพื้นหลัง/เงาไหลเกินขอบเวลาใช้มุมโค้ง
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(topRadius), // ⬅️ ใช้ค่าที่ส่งมา
              ),
            ),
            child: body,
          ),
        ),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
