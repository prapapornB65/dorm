import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/config/api_config.dart';

/// หน้าค่าน้ำ-ค่าไฟ (แยกแท็บ) : “ไฟฟ้า” และ “น้ำ”
/// - ด้านบน: กราฟเส้น 12 เดือนล่าสุด (แก้ label ทับกันโดยแสดงเว้นเดือน + หมุน 45°)
/// - ด้านล่าง: รายการรายเดือน (หน่วย, จำนวนเงิน, สถานะจ่ายแล้ว/ค้าง)
class UsageOverviewSplitPage extends StatefulWidget {
  final int tenantId;
  const UsageOverviewSplitPage({super.key, required this.tenantId});

  @override
  State<UsageOverviewSplitPage> createState() => _UsageOverviewSplitPageState();
}

class _UsageOverviewSplitPageState extends State<UsageOverviewSplitPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final DateFormat _monthFmt;
  List<MonthlyUsage> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _monthFmt = DateFormat('MMM yyyy', 'th');
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _fetchUsageData(); // ← ปรับให้ดึง API จริง
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// ดึง series รายเดือนจาก API
  Future<List<MonthlyUsage>> _fetchUsageData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    final url = Uri.parse(
      '$apiBaseUrl/api/tenant/${widget.tenantId}/usage/series?months=12',
    );

    final resp = await http.get(
      url,
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    final List list = (decoded['items'] as List?) ?? const [];

    // ถ้าแบ็กเอนด์ยังไม่ส่ง status มา ให้ถือว่า 'unpaid' เป็นค่า default
    return list.map((it) {
      final ym = (it['month'] as String?) ?? '';
      DateTime m;
      if (RegExp(r'^\d{4}-\d{2}$').hasMatch(ym)) {
        final p = ym.split('-');
        m = DateTime(int.parse(p[0]), int.parse(p[1]), 1);
      } else {
        m = DateTime.now();
      }
      return MonthlyUsage(
        month: m,
        electricKWh: ((it['electricKWh'] ?? 0) as num).toDouble(),
        waterLiters:
            ((it['waterLiters'] ?? 0) as num).toDouble(), // << รับเป็นลิตร
        electricCost: ((it['electricAmount'] ?? 0) as num).toDouble(),
        waterCost: ((it['waterAmount'] ?? 0) as num).toDouble(),
        status: (it['status'] ?? 'unpaid').toString(),
      );
    }).toList();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ค่าน้ำ-ค่าไฟ'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.bolt), text: 'ไฟฟ้า'),
            Tab(icon: Icon(Icons.water_drop), text: 'น้ำ'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('เกิดข้อผิดพลาด: $_error'))
              : RefreshIndicator(
                  onRefresh: _init,
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildElectricTab(theme),
                      _buildWaterTab(theme),
                    ],
                  ),
                ),
    );
  }

  // -------------------- ELECTRIC TAB --------------------
  Widget _buildElectricTab(ThemeData theme) {
    final data = _items;
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].electricKWh));
    }
    final minY = 0.0;
    final maxY = _calcMaxY(spots);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _chartCard(
              theme: theme,
              title: 'ไฟฟ้า (kWh) รายเดือน',
              unit: 'kWh',
              spots: spots,
              minY: minY,
              maxY: maxY,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final m = data[i];
              final total = m.electricCost; // เฉพาะไฟ
              final paid =
                  m.status.toLowerCase() == 'paid' || m.status == 'จ่ายแล้ว';
              final color = paid ? Colors.green : Colors.redAccent;
              final label = paid ? 'จ่ายแล้ว' : 'ค้างชำระ';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _monthFmt.format(m.month),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _statusChip(label: label, color: color),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.bolt, size: 16),
                          const SizedBox(width: 6),
                          Text(
                              'หน่วยไฟ: ${m.electricKWh.toStringAsFixed(0)} kWh'),
                          const Spacer(),
                          Text('${total.toStringAsFixed(0)} ฿'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------- WATER TAB --------------------
  Widget _buildWaterTab(ThemeData theme) {
    final data = _items;
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].waterLiters));
    }
    final minY = 0.0;
    final maxY = _calcMaxY(spots);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _chartCard(
              theme: theme,
              title: 'น้ำ (ลิตร) รายเดือน', // << เปลี่ยนชื่อกราฟ
              unit: 'L', // << หน่วยแกน/tooltip
              spots: spots,
              minY: minY,
              maxY: maxY,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final m = data[i];
              final total = m.waterCost; // เฉพาะน้ำ
              final paid =
                  m.status.toLowerCase() == 'paid' || m.status == 'จ่ายแล้ว';
              final color = paid ? Colors.green : Colors.redAccent;
              final label = paid ? 'จ่ายแล้ว' : 'ค้างชำระ';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _monthFmt.format(m.month),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _statusChip(label: label, color: color),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.water_drop, size: 16),
                          const SizedBox(width: 6),
                          Text(
                              'หน่วยน้ำ: ${m.waterLiters.toStringAsFixed(0)} L'),
                          const Spacer(),
                          Text('${total.toStringAsFixed(0)} ฿'),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------- Shared Widgets --------------------

  Widget _chartCard({
    required ThemeData theme,
    required String title,
    required String unit,
    required List<FlSpot> spots,
    required double minY,
    required double maxY,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart, size: 20),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: (spots.isEmpty ? 0 : spots.last.x),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY - minY) / 4,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 1,
                        getTitlesWidget: (value, _) {
                          // ลดความถี่: โชว์ทุก “เว้นหนึ่งเดือน”
                          final idx = value.round();
                          if (idx < 0 || idx >= _items.length) {
                            return const SizedBox.shrink();
                          }
                          // แสดงเฉพาะเดือนคู่ (หรือจะใช้ %3 ก็ได้)
                          if (idx % 2 != 0) return const SizedBox.shrink();

                          final text = _monthFmt.format(_items[idx].month);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Transform.rotate(
                              angle: -0.785398, // -45°
                              child: Text(text,
                                  style: const TextStyle(fontSize: 10)),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border.fromBorderSide(
                        BorderSide(color: Colors.black12)),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipPadding: const EdgeInsets.all(8),
                      getTooltipItems: (items) {
                        return items
                            .map((s) {
                              final idx = s.x.round();
                              if (idx < 0 || idx >= _items.length) return null;
                              final m = _monthFmt.format(_items[idx].month);
                              return LineTooltipItem(
                                '$m\n${s.y.toStringAsFixed(unit == "kWh" ? 0 : 1)} $unit',
                                const TextStyle(color: Colors.white),
                              );
                            })
                            .whereType<LineTooltipItem>()
                            .toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  double _calcMaxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 10;
    final raw = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final step = raw < 50
        ? 10
        : raw < 200
            ? 20
            : 50;
    return (raw / step).ceil() * step.toDouble();
  }
}

class MonthlyUsage {
  final DateTime month;
  final double electricKWh;
  final double waterLiters; // เปลี่ยนจาก waterM3 -> waterLiters
  final double electricCost;
  final double waterCost;
  final String status;

  const MonthlyUsage({
    required this.month,
    required this.electricKWh,
    required this.waterLiters,
    required this.electricCost,
    required this.waterCost,
    required this.status,
  });
}
