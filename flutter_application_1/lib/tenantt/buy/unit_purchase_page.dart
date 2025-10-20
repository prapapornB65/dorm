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
  int _qtyWater = 0;
  int _qtyElectric = 0;

  double get _totalWater   => _qtyWater   * widget.waterRate;
  double get _totalElectric=> _qtyElectric* widget.electricRate;
  double get _grandTotal   => _totalWater + _totalElectric;
  double get _balanceAfter => widget.walletBalance - _grandTotal;

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

          // Quantity (ซื้อพร้อมกัน 2 รายการ)
          NeumorphicCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ระบุจำนวนหน่วย',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 12),

                // น้ำประปา
                _lineItem(
                  icon: Icons.water_drop,
                  title: 'น้ำประปา',
                  rate: widget.waterRate,
                  qty: _qtyWater,
                  onDec: () => setState(() { if (_qtyWater > 1) _qtyWater--; }),
                  onInc: () => setState(() { _qtyWater++; }),
                ),
                const Divider(color: AppColors.border, height: 24),

                // ไฟฟ้า
                _lineItem(
                  icon: Icons.flash_on,
                  title: 'ไฟฟ้า',
                  rate: widget.electricRate,
                  qty: _qtyElectric,
                  onDec: () => setState(() { if (_qtyElectric > 1) _qtyElectric--; }),
                  onInc: () => setState(() { _qtyElectric++; }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Summary
          NeumorphicCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sumRow('ค่าน้ำ (${_qtyWater} หน่วย)', _totalWater),
                const SizedBox(height: 6),
                _sumRow('ค่าไฟ (${_qtyElectric} หน่วย)', _totalElectric),
                const SizedBox(height: 10),
                const Divider(color: AppColors.border),
                const SizedBox(height: 10),
                _sumRow('รวมทั้งหมด', _grandTotal, bold: true),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('คงเหลือหลังหัก',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        )),
                    Text(
                      '฿ ${_balanceAfter.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: _balanceAfter >= 0
                            ? AppColors.textPrimary
                            : Colors.red.shade400,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // CTA
          AppButton(
            label: 'ยืนยันการซื้อ',
            icon: Icons.lock_outline,
            onPressed: () {
              if (_qtyWater == 0 && _qtyElectric == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กรุณาเลือกจำนวนหน่วยอย่างน้อย 1 รายการ')),
                );
                return;
              }
              if (_balanceAfter < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('ยอดเงินไม่พอ กรุณาเติมเงินก่อนนะครับ'),
                    backgroundColor: Colors.red.shade400,
                  ),
                );
                return;
              }

              // ✅ ตอนนี้ยังคงส่งค่า true กลับไปเหมือนเดิมเพื่อไม่พังหน้าเรียก
              // ถ้าภายหลังอยากส่งรายละเอียด ให้เปลี่ยนเป็น pop({...})
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
  }

  // ---------- UI helpers ----------

  Widget _lineItem({
    required IconData icon,
    required String title,
    required double rate,
    required int qty,
    required VoidCallback onDec,
    required VoidCallback onInc,
  }) {
    return Row(
      children: [
        _badge(icon),
        const SizedBox(width: 12),
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
              const SizedBox(height: 2),
              Text('ราคา/หน่วย: ฿ ${rate.toStringAsFixed(2)}',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        _qtyBtn(Icons.remove, onTap: onDec),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$qty',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _qtyBtn(Icons.add, onTap: onInc),
      ],
    );
  }

  Widget _sumRow(String label, double value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            )),
        Text(
          '฿ ${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            fontSize: bold ? 18 : 16,
          ),
        ),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
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
