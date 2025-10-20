import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,   // ใช้ได้ใน Column/Container ที่มีความกว้างจำกัด
    this.height = 52,
    this.radius = 20,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,           // สำคัญ: อย่าบานใน Row
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );

    final btn = SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(child: labelRow),
        ),
      ),
    );

    // ขยายเต็มความกว้างเฉพาะเมื่อ “กว้างถูกจำกัด”
    return LayoutBuilder(
      builder: (context, c) {
        final canExpand = c.hasBoundedWidth && c.maxWidth < double.infinity;
        if (expand && canExpand) {
          return SizedBox(width: double.infinity, child: btn);
        }
        // กรณีอยู่ใน Row/Wrap (unbounded) จะไม่พยายามขยาย
        return btn;
      },
    );
  }
}
