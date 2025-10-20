import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/color_app.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;
  const GradientAppBar({
    super.key,
    required this.title,
    this.centerTitle = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      centerTitle: centerTitle,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
      ),
    );
  }
}
