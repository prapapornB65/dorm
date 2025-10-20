import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';

class NeumorphicCard extends StatelessWidget {
  const NeumorphicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.onTap,
    this.color,        // ⬅️ กำหนดพื้นหลังได้
    this.borderColor,  // ⬅️ กำหนดเส้นขอบได้
    this.showShadow = true, // ⬅️ ปิด/เปิดเงาได้
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  final Color? color;
  final Color? borderColor;
  final bool showShadow;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showShadow
            ? const [
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 8),
                  blurRadius: 18,
                ),
              ]
            : const [],
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );

    // ให้ ripple ทำงานถูกต้อง
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}
