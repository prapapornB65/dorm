import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

class MonthlyExpensesPage extends StatefulWidget {
  final int buildingId;
  final int ownerId;
  final String buildingName;

  const MonthlyExpensesPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    required this.buildingName,
  });

  @override
  State<MonthlyExpensesPage> createState() => _MonthlyExpensesPageState();
}

class _MonthlyExpensesPageState extends State<MonthlyExpensesPage> {
  bool loading = true;
  String? error;

  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  double totalExpenses = 0.0;

  // เก็บผลลัพธ์
  Map<String, double> categoryMap = {
    'water': 0,
    'electricity': 0,
    'maintenance': 0,
    'internet': 0,
    'cleaning': 0,
    'other': 0,
  };
  List<_ExpenseItem> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ปุ่มเลื่อนเดือน
  void _prevMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    });
    _load();
  }

  String get _monthParam =>
      '${selectedMonth.year.toString().padLeft(4, '0')}-${selectedMonth.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    final url = Uri.parse(
      '$apiBaseUrl/api/building/${widget.buildingId}/monthly-expenses?month=$_monthParam',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
      }

      final data = json.decode(res.body);
      // items
      final List list = (data['items'] is List)
          ? data['items']
          : (data['data']?['items'] ?? data['rows'] ?? []);

      items = list.map<_ExpenseItem>((e) {
        return _ExpenseItem(
          date: DateTime.tryParse('${e['date']}'),
          category: '${e['category'] ?? e['type'] ?? 'other'}',
          description: '${e['description'] ?? e['detail'] ?? ''}',
          amount: double.tryParse('${e['amount'] ?? e['value'] ?? 0}') ?? 0.0,
        );
      }).toList();

      // categories จาก backend (อาจไม่มี)
      Map<String, double> cats = {
        'water': _toDouble(data['categories']?['water']),
        'electricity': _toDouble(data['categories']?['electricity']),
        'maintenance': _toDouble(data['categories']?['maintenance']),
        'internet': _toDouble(data['categories']?['internet']),
        'cleaning': _toDouble(data['categories']?['cleaning']),
        'other': _toDouble(data['categories']?['other']),
      };

      // ถ้าว่าง ให้จัดกลุ่มจาก items
      if (cats.values.every((v) => v == 0)) {
        cats = _groupFromItems(items);
      }

      // total
      final backendTotal = double.tryParse('${data['total']}') ?? 0.0;
      final sumFromCats = cats.values.fold<double>(0, (a, b) => a + b);
      final sumFromItems = items.fold<double>(0, (a, b) => a + b.amount);

      setState(() {
        categoryMap = cats;
        totalExpenses = backendTotal > 0 ? backendTotal : (sumFromCats > 0 ? sumFromCats : sumFromItems);
      });
    } catch (e) {
      setState(() => error = 'โหลดรายจ่ายไม่สำเร็จ: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  double _toDouble(dynamic v) => double.tryParse('$v') ?? 0.0;

  // รวมยอดตามหมวดจาก items (รองรับชื่อหมวดหลายแบบ)
  Map<String, double> _groupFromItems(List<_ExpenseItem> list) {
    final map = <String, double>{
      'water': 0,
      'electricity': 0,
      'maintenance': 0,
      'internet': 0,
      'cleaning': 0,
      'other': 0,
    };

    String normalize(String raw) {
      final s = raw.toLowerCase().trim();
      // mapping แบบหยาบ
      if (['water', 'ค่าน้ำ', 'น้ำ'].contains(s)) return 'water';
      if (['electricity', 'ไฟ', 'ค่าไฟ', 'ไฟฟ้า'].contains(s)) return 'electricity';
      if (['maintain', 'maintenance', 'ซ่อม', 'ซ่อมบำรุง', 'อุปกรณ์'].contains(s)) return 'maintenance';
      if (['internet', 'เน็ต', 'อินเทอร์เน็ต', 'wifi'].contains(s)) return 'internet';
      if (['clean', 'cleaning', 'ทำความสะอาด'].contains(s)) return 'cleaning';
      return 'other';
    }

    for (final it in list) {
      map[normalize(it.category)] = (map[normalize(it.category)] ?? 0) + it.amount;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = '${_thaiMonth(selectedMonth.month)} ${selectedMonth.year + 543}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header (เลือกเดือน)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.trending_down_rounded, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Text('รายจ่ายต่อเดือน ',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontSize: 18)),
                const Spacer(),
                IconButton(
                  tooltip: 'เดือนก่อนหน้า',
                  onPressed: _prevMonth,
                  icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primaryDark),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(monthLabel, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'เดือนถัดไป',
                  onPressed: _nextMonth,
                  icon: const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'รีเฟรช',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('$error', style: const TextStyle(color: Colors.red, height: 1.2)),
                  ),
                ],
              ),
            ),

          if (loading) const _Shimmer(),

          if (!loading) ...[
            // สรุปยอดรวม + การ์ดหมวดหมู่
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                _bigCard(
                  title: 'ยอดจ่ายรวมเดือนนี้',
                  value: _money(totalExpenses),
                  icon: Icons.payments_rounded,
                ),
                // การ์ดแสดงสัดส่วนโดยย่อ
                _bigCard(
                  title: 'สัดส่วนรายจ่ายตามหมวด',
                  value: '',
                  icon: Icons.pie_chart_rounded,
                  child: _CategoryBars(data: categoryMap),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ตารางรายละเอียด
            _ExpenseTable(items: items),
          ],
        ],
      ),
    );
  }

  Widget _bigCard({
    required String title,
    required String value,
    required IconData icon,
    Widget? child,
  }) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.gradientStart, AppColors.gradientEnd]),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ],
          if (child != null) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }

  String _thaiMonth(int m) {
    const th = [
      '', 'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return th[m];
  }

  String _money(double v) => v.toStringAsFixed(2);
}

/* -------------------- Models & Widgets -------------------- */

class _ExpenseItem {
  final DateTime? date;
  final String category;
  final String description;
  final double amount;

  _ExpenseItem({
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
  });
}

// แผนภาพแท่งแนวนอนอย่างง่าย (ไม่ใช้แพ็กเกจนอก)
class _CategoryBars extends StatelessWidget {
  final Map<String, double> data;
  const _CategoryBars({required this.data});

  String _labelTH(String key) {
    switch (key) {
      case 'water':
        return 'ค่าน้ำ';
      case 'electricity':
        return 'ค่าไฟ';
      case 'maintenance':
        return 'ซ่อมบำรุง';
      case 'internet':
        return 'อินเทอร์เน็ต';
      case 'cleaning':
        return 'ทำความสะอาด';
      default:
        return 'อื่น ๆ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) {
      return const Text('— ไม่มีข้อมูลหมวดหมู่ —', style: TextStyle(color: AppColors.textSecondary));
    }

    return Column(
      children: entries.map((e) {
        final ratio = (e.value / (entries.first.value == 0 ? 1 : entries.first.value)).clamp(0.05, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 88, child: Text(_labelTH(e.key))),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F8F6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(
                  e.value.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ตารางแสดงรายละเอียด
class _ExpenseTable extends StatelessWidget {
  final List<_ExpenseItem> items;
  const _ExpenseTable({required this.items});

  String _labelTH(String key) {
    switch (key.toLowerCase()) {
      case 'water':
      case 'ค่าน้ำ':
      case 'น้ำ':
        return 'ค่าน้ำ';
      case 'electricity':
      case 'ค่าไฟ':
      case 'ไฟ':
      case 'ไฟฟ้า':
        return 'ค่าไฟ';
      case 'maintenance':
      case 'maintain':
      case 'ซ่อม':
      case 'ซ่อมบำรุง':
        return 'ซ่อมบำรุง';
      case 'internet':
      case 'เน็ต':
      case 'อินเทอร์เน็ต':
      case 'wifi':
        return 'อินเทอร์เน็ต';
      case 'cleaning':
      case 'ทำความสะอาด':
        return 'ทำความสะอาด';
      default:
        return 'อื่น ๆ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = items.isEmpty
        ? [
            const DataRow(cells: [
              DataCell(Text('—')),
              DataCell(Text('—')),
              DataCell(Text('ไม่มีรายการ')),
              DataCell(Text('0.00')),
            ])
          ]
        : items.map((e) {
            final d = e.date;
            final dateStr = (d == null)
                ? '—'
                : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            return DataRow(cells: [
              DataCell(Text(dateStr)),
              DataCell(Text(_labelTH(e.category))),
              DataCell(Text(e.description.isEmpty ? '—' : e.description, overflow: TextOverflow.ellipsis)),
              DataCell(Text(e.amount.toStringAsFixed(2))),
            ]);
          }).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('วันที่')),
            DataColumn(label: Text('หมวด')),
            DataColumn(label: Text('รายละเอียด')),
            DataColumn(label: Text('จำนวนเงิน')),
          ],
          rows: rows,
          headingRowHeight: 44,
          dataRowHeight: 44,
          columnSpacing: 24,
          dividerThickness: 0.6,
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();

  @override
  Widget build(BuildContext context) {
    Widget box({double h = 18, double w = double.infinity, double r = 10}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.04),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return Column(
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            box(h: 140, w: 360, r: 18),
            box(h: 140, w: 360, r: 18),
          ],
        ),
        const SizedBox(height: 16),
        box(h: 200, w: double.infinity, r: 18),
      ],
    );
  }
}
