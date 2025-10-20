import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';

class PageHeaderCard extends StatelessWidget {
  const PageHeaderCard({
    super.key,
    this.showBack = false,
    this.leadingIcon,        // ใช้ปกติ
    this.icon,               // เผื่อหน้าเก่า ๆ ที่ส่ง icon:
    required this.title,
    this.subtitle,
    this.chipText,
    this.actions,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  final bool showBack;
  final IconData? leadingIcon;     // optional
  final IconData? icon;            // optional (compatibility)
  final String title;
  final String? subtitle;
  final String? chipText;
  final List<Widget>? actions;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    // ใช้ leadingIcon ก่อน ถ้าไม่มีค่อย fallback ไปที่ icon
    final IconData? useIcon = leadingIcon ?? icon;

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBack) ...[
            const BackButton(color: AppColors.primaryDark),
            const SizedBox(width: 6),
          ],
          if (useIcon != null)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(useIcon, color: AppColors.primaryDark, size: 20),
            ),
          if (useIcon != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontSize: 18,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (chipText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                chipText!,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ...(actions ?? []),
        ],
      ),
    );
  }
}
