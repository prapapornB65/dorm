import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

class OwnerElectricPage extends StatefulWidget {
  final int buildingId;
  final int? ownerId; // เก็บเผื่อส่งไปบันทึก
  final String buildingName;

  const OwnerElectricPage({
    super.key,
    required this.buildingId,
    required this.buildingName,
    this.ownerId,
  });

  @override
  State<OwnerElectricPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<OwnerElectricPage> {
  bool loading = true;
  bool saving = false;
  String _month = ''; // ว่าง = เดือนปัจจุบัน

  List<Map<String, dynamic>> _elecRows = [];
  List<Map<String, dynamic>> _waterRows = [];

  double _elecTotalKwh = 0, _elecTotalAmt = 0;
  double _waterTotalM3 = 0, _waterTotalAmt = 0;
  double _elecRate = 0.0;

  String? error;

  final electricRateC = TextEditingController();
  final waterRateC = TextEditingController();
  String? effectiveDate;

  String get _yyyymm {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadElectricCharges() async {
    final month = _yyyymm;
    final url = Uri.parse(
        '$apiBaseUrl/api/building/${widget.buildingId}/electric/charges?month=$month');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        setState(() => error = 'HTTP ${res.statusCode}');
        return;
      }

      final m = json.decode(res.body) as Map<String, dynamic>;
      final list = (m['items'] as List?) ?? [];

      _elecRate = _asDouble(m['rate']);
      _elecTotalKwh = _asDouble(m['totalKwh']);
      _elecTotalAmt = _asDouble(m['totalAmount']);

      _elecRows = list.map<Map<String, dynamic>>((raw) {
        final e = Map<String, dynamic>.from(raw as Map);
        return {
          'room': e['roomNumber'],
          'start': _asDouble(e['startKwh']), // <-- map เป็น 'start'
          'end': _asDouble(e['endKwh']), // <-- map เป็น 'end'
          'kwh': _asDouble(e['kwh']),
          'unitPrice': _asDouble(e['pricePerUnit']),
          'amount': _asDouble(e['amount']),
        };
      }).toList();

      setState(() {});
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final url = Uri.parse(
          '$apiBaseUrl/api/building/${widget.buildingId}/utility-rate');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        setState(() {
          error = 'HTTP ${res.statusCode}';
          loading = false;
        });
        return;
      }
      final m = (json.decode(res.body) ?? {}) as Map<String, dynamic>;
      electricRateC.text =
          _asDouble(m['electricUnitPrice'] ?? m['electricPrice'])
              .toStringAsFixed(2);
      waterRateC.text =
          _asDouble(m['waterUnitPrice'] ?? m['waterPrice']).toStringAsFixed(2);
      effectiveDate = (m['effectiveDate'] ?? m['EffectiveDate'])?.toString();

      setState(() => loading = false);
    } on TimeoutException {
      setState(() {
        error = 'โหลดช้าเกินไป (timeout)';
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _save() async {
    final e = _asDouble(electricRateC.text.trim());
    final w = _asDouble(waterRateC.text.trim());
    if (e < 0 || w < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกราคา/หน่วยให้ถูกต้อง')),
      );
      return;
    }

    setState(() => saving = true);
    try {
      // ⬇️ ใช้ endpoint ตัวเดียวกับฝั่ง GET
      final url = Uri.parse(
          '$apiBaseUrl/api/building/${widget.buildingId}/utility-rate');
      final res = await http
          .put(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              // ให้ฝั่ง backend รองรับคีย์ชื่อเดิมนี้ (ที่เคยใช้ตอน GET: electricPrice / waterPrice)
              'electricPrice': e,
              'waterPrice': w,
              // ไม่จำเป็นต้องส่ง ownerId ถ้า backend ไม่ได้ใช้
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกอัตราค่าน้ำ/ไฟ สำเร็จ')),
        );
        await _load();
        await _loadElectricCharges(); // ⬅️ รีโหลดตารางค่าไฟ
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ (${res.statusCode})')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _openDevTools() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('ดูอุปกรณ์ที่แม็พในตึกนี้'),
              subtitle: Text('BuildingID: ${widget.buildingId}'),
              onTap: () {
                Navigator.pop(context);
                _debugListDevicesInBuilding();
              },
            ),
            ListTile(
              leading: const Icon(Icons.electric_meter),
              title: const Text('ทดสอบอ่านสถานะ Tuya (ใส่ deviceId)'),
              onTap: () {
                Navigator.pop(context);
                _promptAndTestTuyaStatus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline),
              title: const Text('ดึงจากมิเตอร์ (ทั้งตึก) + log'),
              onTap: () async {
                Navigator.pop(context);
                await _pullFromTuya(debugToast: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _debugListDevicesInBuilding() async {
    final url = Uri.parse(
        '$apiBaseUrl/api/owner-electric/meters?buildingId=${widget.buildingId}');
    try {
      final r = await http.get(url).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('HTTP ${r.statusCode}: ${r.reasonPhrase ?? ""}')),
        );
        return;
      }
      final raw = jsonDecode(r.body);
      final List list = (raw is List) ? raw : (raw['items'] ?? []);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('อุปกรณ์ในตึกนี้'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: list.map<Widget>((e) {
                  final m = Map<String, dynamic>.from(e as Map);
                  final room =
                      (m['room_no'] ?? m['RoomNumber'] ?? '-').toString();
                  final dev = (m['deviceId'] ?? m['DeviceID'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• ห้อง $room → $dev'),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'))
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  Future<void> _promptAndTestTuyaStatus() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ใส่ Device ID (Tuya)'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: 'เช่น vdevo1750709890573536',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ทดสอบ')),
        ],
      ),
    );
    if (ok != true) return;
    final deviceId = c.text.trim();
    if (deviceId.isEmpty) return;

    final url = Uri.parse('$apiBaseUrl/api/tuya/status/$deviceId');
    try {
      final r = await http.get(url).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HTTP ${r.statusCode}: ${r.body}')),
        );
        return;
      }
      final body = jsonDecode(r.body);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('DP / Status ที่อ่านได้'),
          content: SingleChildScrollView(
            child: Text(const JsonEncoder.withIndent('  ').convert(body)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'))
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  Future<void> _pullFromTuya({bool debugToast = false}) async {
    final url = Uri.parse(
        '$apiBaseUrl/api/building/${widget.buildingId}/tuya/pull-electric');
    try {
      final r = await http.post(url).timeout(const Duration(seconds: 20));
      final ok = r.statusCode == 200 || r.statusCode == 201;
      final body = r.body.isNotEmpty ? jsonDecode(r.body) : {};
      final inserted = body['inserted'] ?? 0;
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok
                ? 'ดึงสำเร็จ: inserted = $inserted'
                : 'ดึงไม่สำเร็จ (${r.statusCode})')),
      );

      // ถ้าต้องการดู log ดิบ
      if (debugToast) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('ผลลัพธ์จากแบ็กเอนด์'),
            content: SingleChildScrollView(
                child: Text(const JsonEncoder.withIndent('  ').convert(body))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ปิด'))
            ],
          ),
        );
      }

      if (ok && inserted > 0) {
        await _loadElectricCharges(); // รีโหลดตารางหน่วย/ยอดเงิน
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    }
  }

  Future<void> _loadAll() async {
    // โหลดสองอย่างพร้อมกันพอ ไม่ต้องยุ่ง state ซ้ำ เพราะ _load() ตั้งค่าให้แล้ว
    await Future.wait([
      _load(),
      _loadElectricCharges(),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadElectricCharges(); // << เพิ่ม
  }

  @override
  void dispose() {
    electricRateC.dispose();
    waterRateC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ===== Header =====
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.tungsten_rounded, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Text(
                'ค่าน้ำ/ไฟ • ${widget.buildingName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              if (effectiveDate != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'มีผล: $effectiveDate',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('บันทึก'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _pullFromTuya,
                icon: const Icon(Icons.electric_bolt_rounded),
                label: const Text('ดึงจากมิเตอร์'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'รีเฟรช',
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Dev Tools',
                icon: const Icon(Icons.bug_report),
                onPressed: _openDevTools,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ===== states =====
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),

        if (!loading && error != null)
          _ErrorBanner(message: error!, onRetry: _load),

        // ===== content เมื่อโหลดเสร็จและไม่มี error =====
        if (!loading && error == null) ...[
          // แถวแก้ไขราคา/หน่วย
          Row(
            children: [
              Expanded(
                child: _rateCard(
                  icon: Icons.electric_bolt_rounded,
                  title: 'ค่าไฟ (บาท/หน่วย kWh)',
                  controller: electricRateC,
                  unitHint: 'เช่น 4.50 บาท / kWh',
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _rateCard(
                  icon: Icons.opacity_rounded,
                  title: 'ค่าน้ำ (บาท/ม³)',
                  controller: waterRateC,
                  unitHint: 'เช่น 18.00 บาท / ม³',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ตารางสรุปการใช้งาน
          Row(
            children: [
              Expanded(
                child: _usageCard(
                  title: 'ค่าไฟฟ้าตามห้อง',
                  unitLabel: 'kWh',
                  rows: _elecRows,
                  startKey: 'start',
                  endKey: 'end',
                  qtyKey: 'kwh',
                  priceKey: 'unitPrice',
                  amountKey: 'amount',
                  totalLine:
                      'รวมไฟฟ้า: ${_elecTotalKwh.toStringAsFixed(2)} kWh = ${_elecTotalAmt.toStringAsFixed(2)} บาท',
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _usageCard(
                  title: 'ค่าน้ำตามห้อง',
                  unitLabel: 'm³',
                  rows: _waterRows,
                  qtyKey: 'm3',
                  priceKey: 'unitPrice',
                  amountKey: 'amount',
                  totalLine:
                      'รวมน้ำ: ${_waterTotalM3.toStringAsFixed(2)} m³ = ${_waterTotalAmt.toStringAsFixed(2)} บาท',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _usageCard({
    required String title,
    required String unitLabel,
    required List<Map<String, dynamic>> rows,
    String? startKey, // 'start' สำหรับไฟฟ้า
    String? endKey, // 'end'   สำหรับไฟฟ้า
    required String qtyKey, // 'kwh' หรือ 'm3'
    required String priceKey, // 'unitPrice'
    required String amountKey, // 'amount'
    required String totalLine,
  }) {
    final columns = <DataColumn>[
      const DataColumn(label: Text('ห้อง')),
      if (startKey != null) const DataColumn(label: Text('หน่วยต้นเดือน')),
      if (endKey != null) const DataColumn(label: Text('หน่วยปลายเดือน')),
      const DataColumn(label: Text('หน่วยที่ใช้')),
      const DataColumn(label: Text('ราคา/หน่วย')),
      const DataColumn(label: Text('จำนวนเงิน')),
    ];

    DataRow buildRow(Map<String, dynamic> r) {
      final start = startKey != null ? _asDouble(r[startKey]) : null;
      final end = endKey != null ? _asDouble(r[endKey]) : null;
      final qty = _asDouble(r[qtyKey]);
      final price = _asDouble(r[priceKey]);
      final amt = _asDouble(r[amountKey]);

      final cells = <DataCell>[
        DataCell(Text('${r['room']}')),
        if (startKey != null)
          DataCell(Text('${start!.toStringAsFixed(2)} $unitLabel')),
        if (endKey != null)
          DataCell(Text('${end!.toStringAsFixed(2)} $unitLabel')),
        DataCell(Text('${qty.toStringAsFixed(2)} $unitLabel')),
        DataCell(Text(price.toStringAsFixed(2))),
        DataCell(Text(amt.toStringAsFixed(2))),
      ];
      return DataRow(cells: cells);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns,
              rows: rows.map(buildRow).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(totalLine,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('ไม่มีข้อมูลเดือนนี้',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _rateCard({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    required String unitHint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd]),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'ราคา / หน่วย',
              helperText: unitHint,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
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
              child: Text(message, style: const TextStyle(color: Colors.red))),
          const SizedBox(width: 10),
          ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองอีกครั้ง')),
        ],
      ),
    );
  }
}
