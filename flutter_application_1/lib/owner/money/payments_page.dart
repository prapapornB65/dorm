import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/widgets/page_header_card.dart';

class PaymentRow {
  final String roomNumber;
  final String tenantName;
  final double rent;
  final String rentStatus;
  final double electric;
  final String electricStatus;
  final double water;
  final String waterStatus;

  PaymentRow({
    required this.roomNumber,
    required this.tenantName,
    required this.rent,
    required this.rentStatus,
    required this.electric,
    required this.electricStatus,
    required this.water,
    required this.waterStatus,
  });

  factory PaymentRow.fromJson(Map<String, dynamic> j) {
    double _d(v) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final s = v.replaceAll(',', '').trim();
        return double.tryParse(s) ?? 0.0;
      }
      return 0.0;
    }

    String _s(v) => (v ?? '').toString().trim().toLowerCase();

    return PaymentRow(
      roomNumber: (j['RoomNumber'] ?? j['roomNumber'] ?? '').toString(),
      tenantName: (j['TenantName'] ?? j['FullName'] ?? '').toString(),
      rent: _d(j['RentAmount'] ?? j['rent']),
      rentStatus: _s(j['RentStatus'] ?? j['rentStatus']),
      electric: _d(j['ElectricAmount'] ?? j['electric']),
      electricStatus: _s(j['ElectricStatus'] ?? j['electricStatus']),
      water: _d(j['WaterAmount'] ?? j['water']),
      waterStatus: _s(j['WaterStatus'] ?? j['waterStatus']),
    );
  }
}

class PaymentsPage extends StatefulWidget {
  final int buildingId;
  final int ownerId;
  final String? buildingName;

  const PaymentsPage({
    super.key,
    required this.buildingId,
    required this.ownerId,
    this.buildingName,
  });

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  bool isLoading = true;
  String? errorMessage;

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final searchCtl = TextEditingController();

  List<PaymentRow> all = [];
  List<PaymentRow> filtered = [];

  // สถิติจาก API (ถ้ามี)
  int? dueRentStat, dueElecStat, dueWaterStat;

  String _fmtBaht(num v) {
    final s = v.toStringAsFixed(0);
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return '฿' + s.replaceAllMapped(reg, (m) => ',');
  }

  Color _statusColor(String s) {
    final k = s.trim().toLowerCase();
    switch (k) {
      case 'paid':
      case 'ชำระแล้ว':
        return Colors.green;
      case 'partial':
      case 'ค้างบางส่วน':
        return Colors.orange;
      default:
        return Colors.red; // unpaid
    }
  }

  String _statusLabel(String s) {
    final k = s.trim().toLowerCase();
    switch (k) {
      case 'paid':
        return 'ชำระแล้ว';
      case 'partial':
        return 'ค้างบางส่วน';
      case 'unpaid':
        return 'ค้างชำระ';
      default:
        return s.isEmpty ? '-' : s;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchStats();
  }

  Future<void> _fetch() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final ym =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/bills?month=$ym');

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final raw = jsonDecode(res.body);

      // ---- ดึง list ออกมาแบบยืดหยุ่น ----
      List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is Map) {
        final m = raw as Map;
        final candidate = m['rows'] ?? m['data'] ?? m['items'] ?? const [];
        list = (candidate is List) ? candidate : const [];
      } else {
        list = const [];
      }

      // ---- map เป็น PaymentRow ทีละตัว ----
      final rows = list
          .whereType<Map>() // guard ให้เป็น Map จริง ๆ
          .map((e) => PaymentRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        all = rows;
        _applyFilter();
        isLoading = false;
      });
    } catch (e, st) {
      // ถ้าจะให้เดินต่อด้วย mock ก็ปล่อยไว้; ถ้าไม่ต้องการ mock ให้โยน error ออกเฉย ๆ
      debugPrint('Payments _fetch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        errorMessage = 'โหลดข้อมูลไม่สำเร็จ: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchStats() async {
    final ym = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final u = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/bills-stats?month=$ym');
    try {
      final r = await http.get(u).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          dueRentStat = (j['dueRent'] ?? 0) as int;
          dueElecStat = (j['dueElectric'] ?? 0) as int;
          dueWaterStat = (j['dueWater'] ?? 0) as int;
        });
      }
    } catch (_) {
      // เงียบไปก่อน ใช้คำนวณจาก list แทน
    }
  }

  void _applyFilter() {
    final q = searchCtl.text.trim().toLowerCase();
    filtered = all.where((r) {
      if (q.isEmpty) return true;
      return r.roomNumber.toLowerCase().contains(q) ||
          r.tenantName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(month.year - 2),
      lastDate: DateTime(month.year + 2),
      helpText: 'เลือกเดือน',
    );
    if (picked != null) {
      setState(() => month = DateTime(picked.year, picked.month, 1));
      await _fetch();
      _fetchStats();
    }
  }

  int get dueRent => all.where((e) => e.rentStatus != 'paid').length;
  int get dueElec => all.where((e) => e.electricStatus != 'paid').length;
  int get dueWater => all.where((e) => e.waterStatus != 'paid').length;

  @override
  Widget build(BuildContext context) {
    final ymText = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    // ใช้สถิติที่ดึงจาก API ถ้ามี ไม่งั้นคำนวณจากรายการ
    final rentNum = dueRentStat ?? dueRent;
    final elecNum = dueElecStat ?? dueElec;
    final waterNum = dueWaterStat ?? dueWater;

    return Scaffold(
      // ป้องกันปุ่ม back อัตโนมัติ และตัด AppBar เขียวออก
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await _fetch();
          _fetchStats();
        },
        child: Builder(builder: (_) {
          if (isLoading) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 220),
                Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                SizedBox(height: 400),
              ],
            );
          }

          if (errorMessage != null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                PageHeaderCard(
                  showBack: false,
                  leadingIcon: Icons.payments_rounded,
                  title: 'ชำระเงิน • ${widget.buildingName ?? "-"}',
                  chipText: 'เดือน $ymText',
                  actions: [
                    IconButton(
                      tooltip: 'เลือกเดือน/ปี',
                      onPressed: _pickMonth,
                      icon: const Icon(Icons.calendar_month_rounded,
                          color: AppColors.primaryDark),
                    ),
                    IconButton(
                      tooltip: 'รีเฟรช',
                      onPressed: () async {
                        await _fetch();
                        _fetchStats();
                      },
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.primaryDark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NeumorphicCard(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'เกิดข้อผิดพลาด: ${'${errorMessage!}'}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _fetch();
                    _fetchStats();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ],
            );
          }

          // ปกติ
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ─── หัวกล่องสีขาว ───
              PageHeaderCard(
                showBack: false,
                leadingIcon: Icons.payments_rounded,
                title: 'ชำระเงิน ',
                chipText: 'เดือน $ymText',
                actions: [
                  IconButton(
                    tooltip: 'เลือกเดือน/ปี',
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_month_rounded,
                        color: AppColors.primaryDark),
                  ),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: () async {
                      await _fetch();
                      _fetchStats();
                    },
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.primaryDark),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ─── ตัวนับ ───
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(title: 'ค้างชำระค่าห้อง', value: rentNum),
                  _StatCard(title: 'ค้างชำระค่าไฟ', value: elecNum),
                  _StatCard(title: 'ค้างชำระค่าน้ำ', value: waterNum),
                ],
              ),

              const SizedBox(height: 18),

              // ─── แถบเครื่องมือ ───
              NeumorphicCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickMonth,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(ymText),
                    ),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: searchCtl,
                        onChanged: (_) => setState(_applyFilter),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'ค้นหา ห้อง/ชื่อผู้เช่า',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _fetch();
                        _fetchStats();
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('โหลดใหม่'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ─── ตาราง ───
              NeumorphicCard(
                padding: const EdgeInsets.all(12),
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: Text('ไม่มีข้อมูลในเดือนนี้',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 900),
                          child: DataTable(
                            columnSpacing: 24,
                            horizontalMargin: 12,
                            headingRowColor: MaterialStateProperty.all(
                                AppColors.primaryLight),
                            columns: const [
                              DataColumn(label: Text('ห้อง')),
                              DataColumn(label: Text('ชื่อ-นามสกุล')),
                              DataColumn(label: Text('ค่าเช่า')),
                              DataColumn(label: Text('สถานะ')),
                              DataColumn(label: Text('ค่าไฟ')),
                              DataColumn(label: Text('สถานะ')),
                              DataColumn(label: Text('ค่าน้ำ')),
                              DataColumn(label: Text('สถานะ')),
                            ],
                            rows: filtered.map((r) {
                              return DataRow(cells: [
                                DataCell(Text(r.roomNumber)),
                                DataCell(Text(r.tenantName,
                                    overflow: TextOverflow.ellipsis)),
                                DataCell(Text(_fmtBaht(r.rent))),
                                DataCell(_StatusChip(
                                    label: _statusLabel(r.rentStatus),
                                    color: _statusColor(r.rentStatus))),
                                DataCell(Text(_fmtBaht(r.electric))),
                                DataCell(_StatusChip(
                                    label: _statusLabel(r.electricStatus),
                                    color: _statusColor(r.electricStatus))),
                                DataCell(Text(_fmtBaht(r.water))),
                                DataCell(_StatusChip(
                                    label: _statusLabel(r.waterStatus),
                                    color: _statusColor(r.waterStatus))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NeumorphicCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child:
                  const Icon(Icons.receipt_long, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(title,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
