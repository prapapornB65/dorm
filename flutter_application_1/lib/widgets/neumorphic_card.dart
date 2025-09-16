import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';

class NeumorphicCard extends StatelessWidget {
  const NeumorphicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000), // เงานุ่ม
            offset: Offset(4, 8),
            blurRadius: 20,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white,       // ไฮไลท์เบาๆ
            offset: Offset(-2, -2),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );

    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: card,
    );
  }
}
