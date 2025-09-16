import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/color_app.dart';

class UnitPurchasePage extends StatefulWidget {
  final int tenantId;
  final double walletBalance;
  final double waterRate;
  final double electricRate;

  const UnitPurchasePage({
    super.key,
    required this.tenantId,
    required this.walletBalance,
    required this.waterRate,
    required this.electricRate,
  });

  @override
  State<UnitPurchasePage> createState() => _UnitPurchasePageState();
}

class _UnitPurchasePageState extends State<UnitPurchasePage> {
  String _service = 'water'; // 'water' | 'electric'
  int _qty = 0;

  double get _pricePerUnit =>
      _service == 'water' ? widget.waterRate : widget.electricRate;

  double get _total => _qty * _pricePerUnit;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('ซื้อหน่วยเพิ่มเติม')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          // Wallet summary
          NeumorphicCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _badge(Icons.account_balance_wallet),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ยอดเงินคงเหลือ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 6),
                      Text('฿ ${widget.walletBalance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Select service
          NeumorphicCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('เลือกบริการ',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _choiceChip(
                      icon: Icons.water_drop,
                      label: 'น้ำประปา',
                      selected: _service == 'water',
                      onTap: () => setState(() => _service = 'water'),
                    ),
                    _choiceChip(
                      icon: Icons.flash_on,
                      label: 'ไฟฟ้า',
                      selected: _service == 'electric',
                      onTap: () => setState(() => _service = 'electric'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Quantity
          NeumorphicCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('จำนวนหน่วย',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _qtyBtn(Icons.remove, onTap: () {
                      setState(() {
                        if (_qty > 1) _qty--;
                      });
                    }),
                    const Spacer(),
                    Text('$_qty',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        )),
                    const Spacer(),
                    _qtyBtn(Icons.add, onTap: () {
                      setState(() {
                        _qty++;
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'ราคา/หน่วย: ฿ ${_pricePerUnit.toStringAsFixed(2)}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Price summary
          Row(
            children: [
              Expanded(
                child: NeumorphicCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('รวมทั้งหมด',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 6),
                      Text('฿ ${_total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NeumorphicCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('คงเหลือหลังหัก',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 6),
                      Text(
                        '฿ ${(widget.walletBalance - _total).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: (widget.walletBalance - _total) >= 0
                              ? AppColors.textPrimary
                              : Colors.red.shade400,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // CTA
          AppButton(
            label: 'ยืนยันการซื้อ',
            icon: Icons.lock_outline,
            onPressed: () {
              // ✅ ดีไซน์เท่านั้น: ให้หน้า caller ตัดสินใจต่อเมื่อ pop(true)
              if (widget.walletBalance - _total < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('ยอดเงินไม่พอ กรุณาเติมเงินก่อนนะครับ'),
                    backgroundColor: Colors.red.shade400,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
  }

  // ---------- UI Helpers ----------

  Widget _choiceChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? Colors.white : AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
    );
  }

  Widget _badge(IconData icon) {
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
