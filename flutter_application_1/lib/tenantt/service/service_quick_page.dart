import 'package:flutter/material.dart';

// ดีไซน์/ธีม
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/gradient_app_bar.dart';

// ปลายทาง
import 'package:flutter_application_1/tenantt/service/ContactOwnerPage.dart';
import 'package:flutter_application_1/tenantt/service/UsageHistoryPage.dart';
import 'package:flutter_application_1/tenantt/Usage/Usage Overview Page.dart';

// ถ้ามีหน้าฟอร์มแจ้งซ่อมเฉพาะ ให้ import หน้านั้นแทน service_page.dart
import 'package:flutter_application_1/tenantt/service/service_page.dart';

class ServiceQuickPage extends StatelessWidget {
  final int tenantId;
  const ServiceQuickPage({super.key, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const GradientAppBar(title: 'บริการทั้งหมด'),
      topRadius: 0, // ชนขอบบน ไม่โค้ง
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _serviceTile(
            context,
            icon: Icons.support_agent,
            title: 'ติดต่อผู้ดูแล',
            subtitle: 'แจ้งปัญหา / สอบถามข้อมูล',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContactOwnerPage(tenantId: tenantId),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _serviceTile(
            context,
            icon: Icons.history,
            title: 'ประวัติการใช้งาน',
            subtitle: 'ดูการใช้น้ำ/ไฟย้อนหลัง',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UsageHistoryPage(tenantId: tenantId),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _serviceTile(
            context,
            icon: Icons.build,
            title: 'การแจ้งซ่อม',
            subtitle: 'กรอกอาการชำรุด / นัดหมาย',
            onTap: () {
              // TODO: ถ้ามีหน้าฟอร์มแจ้งซ่อม (เช่น RepairRequestPage) ให้ชี้ไปหน้านั้น
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServicePage(tenantId: tenantId),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _serviceTile(
            context,
            icon: Icons.bolt, // ไอคอนสื่อถึงไฟฟ้า
            title: 'ค่าน้ำ-ค่าไฟ',
            subtitle: 'ดูหน่วยและค่าใช้จ่ายรายเดือน',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UsageOverviewSplitPage(
                      tenantId: tenantId), // หน้ากราฟและรายการรายเดือน
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _serviceTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: NeumorphicCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
