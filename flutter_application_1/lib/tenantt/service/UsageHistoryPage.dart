import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/color_app.dart';

class UsageHistoryPage extends StatelessWidget {
  final int tenantId;
  const UsageHistoryPage({super.key, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    // TODO: ใช้ tenantId ไปดึงประวัติจริงจาก API ของคุณ
    return GradientScaffold(
      appBar: AppBar(title: const Text('ประวัติการใช้งาน')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        itemCount: 10, // แทนด้วยจำนวนรายการจริง
        itemBuilder: (context, i) {
          final isWater = i.isEven; // ตัวอย่าง mock
          final title = isWater ? 'น้ำประปา' : 'ไฟฟ้า';
          final units = isWater ? '-12 หน่วย' : '-6 หน่วย';
          final timeText = '12 ส.ค. 2025 · 18:45';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NeumorphicCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isWater ? Icons.water_drop : Icons.flash_on,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              )),
                          const SizedBox(height: 4),
                          Text(
                            timeText,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      units,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
