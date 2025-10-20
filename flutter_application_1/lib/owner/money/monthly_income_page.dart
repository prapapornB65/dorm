import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/page_header_card.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/color_app.dart';

class MonthlyIncomePage extends StatefulWidget {
  final int buildingId;
  final String buildingName;
  const MonthlyIncomePage({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<MonthlyIncomePage> createState() => _MonthlyIncomePageState();
}

class _MonthlyIncomePageState extends State<MonthlyIncomePage> {
  bool isLoading = true;
  bool isError = false;
  String? errorText;

  late int selectedYear;
  late int selectedMonth; // 1..12

  double monthTotal = 0.0;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      isLoading = true;
      isError = false;
      errorText = null;
    });

    try {
      final url = Uri.parse(
        '$apiBaseUrl/api/building/${widget.buildingId}/monthly-income-detail'
        '?year=$selectedYear&month=$selectedMonth',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        String msg = 'HTTP ${res.statusCode}';
        try {
          final j = json.decode(res.body);
          final m = (j['error'] ?? j['message'])?.toString();
          if (m != null && m.isNotEmpty) msg = m;
        } catch (_) {}
        throw Exception(msg);
      }

      final data = json.decode(res.body);
      monthTotal = _asDouble(data['total']);

      final list = (data['items'] as List?) ?? const [];
      items = list.map<Map<String, dynamic>>((e) {
        final map = e as Map;
        return {
          'id': map['id'],
          'date': (map['date'] ?? '').toString(),
          'roomNumber': (map['roomNumber'] ?? '-').toString(),
          'tenantName': (map['tenantName'] ?? '-').toString(),
          'amount': _asDouble(map['amount']),
          'note': (map['note'] ?? '').toString(),
        };
      }).toList();
    } on TimeoutException {
      isError = true;
      errorText = 'การเชื่อมต่อช้า (timeout)';
    } catch (e) {
      isError = true;
      errorText = 'โหลดข้อมูลไม่สำเร็จ: $e';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String)
      return double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
    return 0.0;
  }

  String _thMonth(int m) {
    const th = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.'
    ];
    return th[m.clamp(1, 12)];
  }

  String _thYear(int y) => '${y + 543}';

  Future<void> _pickMonthYear() async {
    final now = DateTime.now();
    final years =
        List<int>.generate(7, (i) => now.year - 5 + i); // ปีก่อนหน้า 5 ถึง +1
    int tempYear = selectedYear;
    int tempMonth = selectedMonth;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        // 👇 เพิ่ม StatefulBuilder
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    width: 44,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.date_range,
                          color: AppColors.primaryDark),
                      const SizedBox(width: 8),
                      const Text('เลือกเดือน/ปี',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          )),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          // อัปเดต state จริงของหน้า + โหลดข้อมูล
                          setState(() {
                            selectedYear = tempYear;
                            selectedMonth = tempMonth;
                            isLoading = true; // ให้มีฟีดแบ็กทันที
                          });
                          Navigator.pop(context);
                          _loadMonth();
                        },
                        child: const Text('ตกลง'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('ปี',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: tempYear,
                        underline: const SizedBox.shrink(),
                        items: List<int>.generate(
                                7, (i) => DateTime.now().year - 5 + i)
                            .map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text('${_thYear(y)}'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            // 👇 ใช้ setModalState เพื่อรีเฟรชเฉพาะในโมดัล
                            setModalState(() => tempYear = v);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: List.generate(12, (i) {
                      final m = i + 1;
                      final selected = m == tempMonth;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        // 👇 ใช้ setModalState เพื่อให้ “เลือกแล้ว” ขึ้นทันที
                        onTap: () => setModalState(() => tempMonth = m),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primaryLight
                                : Colors.white,
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _thMonth(m),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? AppColors.primaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

 @override
Widget build(BuildContext context) {
  final title = 'รายรับเดือน ${_thMonth(selectedMonth)} ${_thYear(selectedYear)}';
  final sumChip = 'รวม ${monthTotal.toStringAsFixed(2)} บาท';

  return Scaffold(
    // กันไม่ให้ AppBar ใส่ปุ่มย้อนกลับเอง
    appBar: AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 0,
      elevation: 0,
      backgroundColor: Colors.transparent,
    ),
    backgroundColor: AppColors.surface,
    body: RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadMonth,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ───────────── Header กล่องขาว ─────────────
          PageHeaderCard(
            showBack: false,                       // ไม่มีปุ่มย้อนกลับ
            leadingIcon: Icons.payments_rounded,   // ไอคอนหัวข้อ
            title: title,                          // ชื่อเดือน/ปี + ตึก
            chipText: sumChip,                     // แสดงยอดรวมเดือน
            actions: [
              IconButton(
                tooltip: 'เลือกเดือน/ปี',
                onPressed: isLoading ? null : _pickMonthYear,
                icon: const Icon(Icons.calendar_month_rounded, color: AppColors.primaryDark),
              ),
              IconButton(
                tooltip: 'รีเฟรช',
                onPressed: isLoading ? null : _loadMonth,
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryDark),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ───────────── การ์ดสรุป (จะคงไว้ก็ได้ เผื่ออยากเห็นอีกชั้น) ─────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primaryLight,
                  child: Icon(Icons.attach_money, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ยอดเงินเข้าเดือนนี้ • ${widget.buildingName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          )),
                      const SizedBox(height: 4),
                      Text(sumChip, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: isLoading ? null : _pickMonthYear,
                  style: TextButton.styleFrom(
                    overlayColor: AppColors.primaryLight.withOpacity(.25),
                  ),
                  icon: const Icon(Icons.edit_calendar_rounded),
                  label: const Text('เปลี่ยนเดือน/ปี'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ───────────── รายการธุรกรรม ─────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: isLoading
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ))
                : isError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(errorText ?? 'โหลดข้อมูลไม่สำเร็จ',
                              style: const TextStyle(color: Colors.red)),
                        ),
                      )
                    : items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('ไม่มีรายการในเดือนนี้',
                                  style: TextStyle(color: AppColors.textSecondary)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final it = items[i];
                              return _TxnTile(
                                date: _fmtDate(it['date']),
                                room: it['roomNumber'],
                                tenant: it['tenantName'],
                                amount: (it['amount'] as double),
                                note: it['note'],
                              );
                            },
                          ),
          ),
        ],
      ),
    ),
  );
}


  String _fmtDate(String iso) {
    // รับ ISO -> แสดง dd/MM/YY เวลา (แบบย่อ)
    DateTime? t;
    try {
      t = DateTime.parse(iso).toLocal();
    } catch (_) {}
    if (t == null) return '-';
    final dd = t.day.toString().padLeft(2, '0');
    final mm = t.month.toString().padLeft(2, '0');
    final yy = (t.year + 543).toString().substring(2);
    final hh = t.hour.toString().padLeft(2, '0');
    final mn = t.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$mn';
    // ถ้าอยากแสดงเฉพาะวัน: return '$dd/$mm/${t.year + 543}';
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({
    required this.date,
    required this.room,
    required this.tenant,
    required this.amount,
    required this.note,
  });

  final String date;
  final String room;
  final String tenant;
  final double amount;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // ซ้าย: วันเวลา + ผู้เช่า/ห้อง
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '$tenant • ห้อง $room',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(note,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
          // ขวา: ยอดเงิน
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '+ ${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatefulWidget {
  const _MonthChip(
      {required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MonthChip> createState() => _MonthChipState();
}

class _MonthChipState extends State<_MonthChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: Material(
        color: sel ? AppColors.primaryLight : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashColor: AppColors.primary.withOpacity(.2),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                widget.text,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: sel ? AppColors.primaryDark : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
