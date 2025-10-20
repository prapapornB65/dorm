import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'unit_purchase_page.dart';
import '../wallet/top_up_page.dart';
import 'package:flutter_application_1/config/api_config.dart';

// ✅ ใช้ธีม/วิจเจ็ตดีไซน์ใหม่
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/stat_tile.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/gradient_app_bar.dart';

final url = '$apiBaseUrl/api/some-endpoint';

class WalletPage extends StatefulWidget {
  final int tenantId;

  const WalletPage({super.key, required this.tenantId});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  double? walletBalance;
  int? waterUnit;
  int? electricUnit;
  double? waterUnitPrice;
  double? electricUnitPrice;
  String? buildingName;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchWalletData();
  }

  Future<void> fetchWalletData() async {
    try {
      final tenantId = widget.tenantId;

      // 1) Wallet
      final walletUrl = Uri.parse('$apiBaseUrl/api/wallet/$tenantId');
      final walletRes = await http.get(walletUrl);
      if (walletRes.statusCode == 200) {
        final walletJson = jsonDecode(walletRes.body);
        walletBalance = walletJson.containsKey('Balance')
            ? double.tryParse(walletJson['Balance'].toString())
            : null;
      }

      // 2) Unit balance
      final unitUrl = Uri.parse('$apiBaseUrl/api/unit-balance/$tenantId');
      final unitRes = await http.get(unitUrl);
      if (unitRes.statusCode == 200) {
        final unitJson = jsonDecode(unitRes.body);
        waterUnit = unitJson['WaterUnit'];
        electricUnit = unitJson['ElectricUnit'];
      }

      // 3) Rate + building name
      final rateUrl = Uri.parse('$apiBaseUrl/api/utility-rate/$tenantId');
      final rateRes = await http.get(rateUrl);
      if (rateRes.statusCode == 200) {
        final rateJson = jsonDecode(rateRes.body);
        waterUnitPrice = rateJson['WaterUnitPrice'] != null
            ? double.tryParse(rateJson['WaterUnitPrice'].toString())
            : null;
        electricUnitPrice = rateJson['ElectricUnitPrice'] != null
            ? double.tryParse(rateJson['ElectricUnitPrice'].toString())
            : null;
        buildingName = rateJson['BuildingName'];
      }

      setState(() => isLoading = false);
    } catch (e) {
      debugPrint('❌ Error in fetchWalletData: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ ใช้ GradientScaffold เพื่อได้พื้นหลังไล่สี + แผ่นพื้นขาวโค้งด้านใน
    return GradientScaffold(
      appBar: const GradientAppBar(
          title: 'กระเป๋าเงิน'), // ✅ หัวแบบเดียวกับ Profile
      topRadius: 0, // ✅ ชนขอบบน ไม่โค้ง
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (buildingName != null) ...[
                    Text(
                      'หอพัก: $buildingName',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // การ์ดยอดเงิน + ปุ่มเติมเงิน
                  Row(
                    children: [
                      Expanded(child: _balanceCard(walletBalance)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: AppButton(
                          label: 'เติมเงิน',
                          icon: Icons.add,
                          expand: false,
                          onPressed: () async {
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TopUpPage(tenantId: widget.tenantId),
                              ),
                            );
                            if (!mounted) return;
                            if (ok == true) {
                              await fetchWalletData();
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  // หน่วยคงเหลือ: น้ำบน / ไฟล่าง (ตามที่คุยกัน)
                  Column(
                    children: [
                      StatTile(
                        title: 'น้ำคงเหลือ',
                        value: waterUnit != null
                            ? '${waterUnit!} หน่วย'
                            : 'กำลังโหลด...',
                        subtitle: waterUnitPrice != null
                            ? 'ราคาน้ำ: ${waterUnitPrice!.toStringAsFixed(2)} ฿/หน่วย'
                            : 'กำลังโหลดราคา...',
                        leading: _iconBadge(Icons.water_drop),
                      ),
                      const SizedBox(height: 12),
                      StatTile(
                        title: 'ไฟฟ้าคงเหลือ',
                        value: electricUnit != null
                            ? '${electricUnit!} หน่วย'
                            : 'กำลังโหลด...',
                        subtitle: electricUnitPrice != null
                            ? 'ราคาไฟ: ${electricUnitPrice!.toStringAsFixed(2)} ฿/หน่วย'
                            : 'กำลังโหลดราคา...',
                        leading: _iconBadge(Icons.flash_on),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  AppButton(
                    label: 'ซื้อหน่วยเพิ่มเติม',
                    icon: Icons.shopping_bag_outlined,
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UnitPurchasePage(
                            tenantId: widget.tenantId,
                            walletBalance: walletBalance ?? 0,
                            waterRate: waterUnitPrice ?? 0,
                            electricRate: electricUnitPrice ?? 0,
                          ),
                        ),
                      );
                      if (result == true) {
                        setState(() => isLoading = true);
                        await fetchWalletData();
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // ---------- UI Helpers (ดีไซน์เท่านั้น ไม่แตะ logic) ----------

  Widget _balanceCard(double? amount) {
    return NeumorphicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ยอดเงินคงเหลือ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amount != null ? '฿ ${amount.toStringAsFixed(2)}' : 'กำลังโหลด...',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          // ✅ ลบ progress/กราฟ 70% ออกเรียบร้อย (ไม่มีอะไรต่อท้าย)
        ],
      ),
    );
  }

  Widget _iconBadge(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.primary),
    );
  }
}
