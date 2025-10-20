import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

class OwnerElectricPage extends StatefulWidget {
  final int buildingId;
  final int? ownerId;
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
  bool _refreshing = false;
  bool _firstLoad = true;

  List<Map<String, dynamic>> _elecRows = [];
  List<Map<String, dynamic>> _waterRows = [];

  double _elecTotalKwh = 0, _elecTotalAmt = 0;
  double _waterTotalLiters = 0, _waterTotalAmt = 0;

  double _elecRate = 0.0;
  double _waterRate = 0.0;
  String? error;
  final Set<String> _occupiedRooms = {};

  final electricRateC = TextEditingController();
  final waterRateC = TextEditingController();
  String? effectiveDate;

  Timer? _autoTimer;
  final Duration _autoEvery = const Duration(seconds: 60);
  DateTime? _lastUpdated;

  String get _yyyymm {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String _fmtQty(double v, String unit) => '${v.toStringAsFixed(3)} $unit';
  String _fmtMoney(double v) => v.toStringAsFixed(2);

  String _normRoom(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return cleaned.trim().toUpperCase();
  }

  Future<Map<String, String>> _authHeaders({bool jsonBody = false}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  void _logRequest({
    required String tag,
    required Uri url,
    required String method,
    required Map<String, String> headers,
    String? body,
  }) {
    final auth = headers['Authorization'];
    final masked = (auth != null && auth.startsWith('Bearer '))
        ? 'Bearer ${auth.substring(7).replaceRange(1, auth.length - 8, '***')}'
        : '(none)';
    debugPrint('[$tag] → $method $url');
    debugPrint(
        '[$tag]   headers { Authorization: $masked, Content-Type: ${headers['Content-Type']} }');
    if (body != null)
      debugPrint(
          '[$tag]   body ${body.length > 900 ? body.substring(0, 900) + "…(truncated)" : body}');
  }

  void _logResponse({
    required String tag,
    required int status,
    required Duration elapsed,
    required Map<String, String> headers,
    required String body,
  }) {
    debugPrint('[$tag] ← $status in ${elapsed.inMilliseconds} ms');
    debugPrint('[$tag]   respHeaders: $headers');
    debugPrint(
        '[$tag]   respBody: ${body.length > 900 ? body.substring(0, 900) + "…(truncated)" : body}');
  }

  String _statusHint(int status, String body) {
    if (status == 401) return 'ไม่ได้ส่ง/ส่ง token ผิด หรือหมดอายุ';
    if (status == 404) return 'เส้นทาง/ข้อมูลไม่พบ';
    if (status == 502) return 'Bad Gateway — ปลายทางล้ม (อาจ Tuya ไม่ตอบ)';
    return '';
  }

  Future<void> _loadOccupiedRooms() async {
    final url = Uri.parse(
        '$apiBaseUrl/api/owner/buildings/${widget.buildingId}/occupied-rooms');
    const tag = 'OCC_ROOMS';
    try {
      final headers = await _authHeaders();
      final sw = Stopwatch()..start();
      _logRequest(tag: tag, url: url, method: 'GET', headers: headers);

      final r = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      sw.stop();
      _logResponse(
          tag: tag,
          status: r.statusCode,
          elapsed: sw.elapsed,
          headers: r.headers,
          body: r.body);

      if (r.statusCode != 200) return;
      final data = json.decode(r.body);
      
      // ✅ แก้ตรงนี้: รองรับทั้ง array ตรง ๆ และ object ที่มี items/rows
      final List list = (data is List)
          ? data
          : (data is Map && data['items'] is List)
              ? data['items']
              : (data is Map && data['rows'] is List)
                  ? data['rows']
                  : [];

      _occupiedRooms
        ..clear()
        ..addAll(list.map((e) => _normRoom('$e')).where((s) => s.isNotEmpty));
    } catch (_) {}
  }

  void _recalcElecTotals() {
    double k = 0.0, a = 0.0;
    for (final r in _elecRows) {
      k += _asDouble(r['kwh']);
      a += _asDouble(r['amount']);
    }
    _elecTotalKwh = k;
    _elecTotalAmt = double.parse(a.toStringAsFixed(2));
  }

  void _recalcWaterTotals() {
    double liters = 0.0, a = 0.0;
    for (final r in _waterRows) {
      liters += _asDouble(r['liters']);
      a += _asDouble(r['amount']);
    }
    _waterTotalLiters = double.parse(liters.toStringAsFixed(3));
    _waterTotalAmt = double.parse(a.toStringAsFixed(2));
  }

  Future<void> _loadElectricCharges() async {
    if (_occupiedRooms.isEmpty) {
      await _loadOccupiedRooms();
    }

    final month = _yyyymm;
    final url = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/electric/charges?month=$month');
    const tag = 'ELEC_CHARGES';
    try {
      final headers = await _authHeaders();
      final sw = Stopwatch()..start();
      _logRequest(tag: tag, url: url, method: 'GET', headers: headers);

      final res = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      sw.stop();
      _logResponse(
          tag: tag,
          status: res.statusCode,
          elapsed: sw.elapsed,
          headers: res.headers,
          body: res.body);

      if (res.statusCode != 200) {
        setState(() => error =
            'HTTP ${res.statusCode} ${_statusHint(res.statusCode, res.body)}');
        return;
      }

      final m = json.decode(res.body) as Map<String, dynamic>;
      
      // ✅ แก้ตรงนี้: รองรับทั้ง items และ rows
      final List items = (m['items'] as List?)
          ?? (m['rows'] as List?)
          ?? [];
      
      _elecRate = _asDouble(m['rate']);
      final rows = <Map<String, dynamic>>[];

      for (final raw in items) {
        final e = Map<String, dynamic>.from(raw as Map);
        final roomRaw =
            (e['roomNumber'] ?? e['room_no'] ?? e['room'] ?? '').toString();
        if (roomRaw.isEmpty) continue;
        final roomNo = _normRoom(roomRaw);
        if (!_occupiedRooms.contains(roomNo)) continue;

        final start = _asDouble(e['startKwh']);
        final end = _asDouble(e['endKwh']);
        final used = (end - start);
        final usedSafe = used.isNaN || used < 0 ? 0.0 : used;

        final unitPrice = _asDouble(e['pricePerUnit']);
        final price = unitPrice > 0 ? unitPrice : _elecRate;
        final amount = double.parse((usedSafe * price).toStringAsFixed(2));

        rows.add({
          'room': roomNo,
          'occupied': true,
          'start': start,
          'end': end,
          'kwh': usedSafe,
          'unitPrice': price,
          'amount': amount,
        });
      }

      rows.sort((a, b) => (a['room'] as String).compareTo(b['room'] as String));
      _elecRows = rows;
      _recalcElecTotals();
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _loadWaterCharges() async {
    if (_occupiedRooms.isEmpty) {
      await _loadOccupiedRooms();
    }

    final month = _yyyymm;
    final url = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/water/charges?month=$month');
    const tag = 'WATER_CHARGES';
    try {
      final headers = await _authHeaders();
      final sw = Stopwatch()..start();
      _logRequest(tag: tag, url: url, method: 'GET', headers: headers);

      final res = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      sw.stop();
      _logResponse(
          tag: tag,
          status: res.statusCode,
          elapsed: sw.elapsed,
          headers: res.headers,
          body: res.body);

      if (res.statusCode != 200) return;

      final m = json.decode(res.body) as Map<String, dynamic>;
      
      // ✅ แก้ตรงนี้: รองรับทั้ง items และ rows
      final List items = (m['items'] as List?)
          ?? (m['rows'] as List?)
          ?? [];
      
      final monthRate = _asDouble(m['pricePerLiter'] ?? m['rate']);
      _waterRate = monthRate;

      final rows = <Map<String, dynamic>>[];
      for (final raw in items) {
        final e = Map<String, dynamic>.from(raw as Map);
        final roomRaw =
            (e['roomNumber'] ?? e['room_no'] ?? e['room'] ?? '').toString();
        if (roomRaw.isEmpty) continue;
        final roomNo = _normRoom(roomRaw);
        if (!_occupiedRooms.contains(roomNo)) continue;

        final startLiters = _asDouble(e['startLiters'] ?? e['start_liters']);
        final endLiters = _asDouble(e['endLiters'] ?? e['end_liters']);
        double usedLiters = _asDouble(
            e['usedLiters'] ?? e['liters'] ?? (endLiters - startLiters));
        if (usedLiters.isNaN || usedLiters < 0) usedLiters = 0.0;

        final itemRate = _asDouble(e['pricePerLiter'] ?? e['pricePerUnit']);
        final price = itemRate > 0
            ? itemRate
            : (monthRate > 0 ? monthRate : _asDouble(waterRateC.text.trim()));
        final usedRounded = double.parse(usedLiters.toStringAsFixed(3));
        final amount = double.parse((usedRounded * price).toStringAsFixed(2));

        rows.add({
          'room': roomNo,
          'occupied': true,
          'start': startLiters,
          'end': endLiters,
          'liters': usedRounded,
          'unitPrice': price,
          'amount': amount,
        });
      }

      rows.sort((a, b) => (a['room'] as String).compareTo(b['room'] as String));
      _waterRows = rows;
      _recalcWaterTotals();
    } catch (_) {}
  }

  Future<void> _loadRates() async {
    try {
      final url = Uri.parse(
          '$apiBaseUrl/api/owner/building/${widget.buildingId}/utility-rate');
      
      final headers = await _authHeaders();
      const tag = 'LOAD_RATES';
      final sw = Stopwatch()..start();
      _logRequest(tag: tag, url: url, method: 'GET', headers: headers);
      
      final res = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 20));
      sw.stop();
      _logResponse(
          tag: tag,
          status: res.statusCode,
          elapsed: sw.elapsed,
          headers: res.headers,
          body: res.body);
      
      if (res.statusCode != 200) {
        debugPrint('[LOAD_RATES] Warning: ${res.statusCode}');
        return;
      }

      final m = (json.decode(res.body) ?? {}) as Map<String, dynamic>;
      electricRateC.text =
          _asDouble(m['electricUnitPrice'] ?? m['electricPrice'])
              .toStringAsFixed(2);
      waterRateC.text =
          _asDouble(m['waterUnitPrice'] ?? m['waterPrice']).toStringAsFixed(6);
      effectiveDate = (m['effectiveDate'] ?? m['EffectiveDate'])?.toString();
    } catch (e) {
      debugPrint('[LOAD_RATES] Error (non-blocking): $e');
    }
  }

  Future<void> _save() async {
    final e = _asDouble(electricRateC.text.trim());
    final w = _asDouble(waterRateC.text.trim());
    if (e < 0 || w < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณากรอกราคา/หน่วยให้ถูกต้อง')));
      return;
    }

    setState(() => saving = true);
    final url = Uri.parse(
        '$apiBaseUrl/api/owner/building/${widget.buildingId}/utility-rate');
    const tag = 'SAVE_RATE';
    try {
      final headers = await _authHeaders(jsonBody: true);
      final body = json.encode({'electricUnitPrice': e, 'waterUnitPrice': w});
      final sw = Stopwatch()..start();
      _logRequest(
          tag: tag, url: url, method: 'PUT', headers: headers, body: body);

      final res = await http
          .put(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      sw.stop();
      _logResponse(
          tag: tag,
          status: res.statusCode,
          elapsed: sw.elapsed,
          headers: res.headers,
          body: res.body);

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกอัตราค่าน้ำ/ไฟ สำเร็จ')));
        await _refreshAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'บันทึกไม่สำเร็จ (${res.statusCode}) ${_statusHint(res.statusCode, res.body)}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    _refreshing = true;

    if (_firstLoad)
      setState(() {
        loading = true;
        error = null;
      });

    try {
      await _loadRates();
      await _loadOccupiedRooms();
      await _loadElectricCharges();
      await _loadWaterCharges();

      if (!mounted) return;
      setState(() {
        loading = false;
        _firstLoad = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
        _firstLoad = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  static const int _anchorMinute = 2;

  Duration _untilNextAnchor() {
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour)
        .add(const Duration(hours: 1));
    final anchor = DateTime(nextHour.year, nextHour.month, nextHour.day,
        nextHour.hour, _anchorMinute);
    return anchor.difference(now).isNegative
        ? const Duration(minutes: 1)
        : anchor.difference(now);
  }

  void _startAutoRefresh() {
    _autoTimer?.cancel();

    _autoTimer = Timer(const Duration(seconds: 3), () {
      _refreshAll();

      _autoTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _refreshAll();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    electricRateC.dispose();
    waterRateC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastTxt = _lastUpdated != null
        ? 'อัปเดตล่าสุด: ${_lastUpdated!.toLocal().toString().substring(0, 19)}'
        : '—';

    return Column(
      children: [
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  effectiveDate != null ? 'มีผล: $effectiveDate' : lastTxt,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('บันทึก'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'รีเฟรช',
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Dev Tools',
                onPressed: _openDevTools,
                icon: const Icon(Icons.bug_report),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                if (!loading && error != null)
                  _ErrorBanner(message: error!, onRetry: _refreshAll),
                if (!loading && error == null) ...[
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
                          title: 'ค่าน้ำ (บาท/ลิตร)',
                          unitHint: 'เช่น 0.020000 บาท / ลิตร',
                          controller: waterRateC,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _usageCard(
                          title: 'ค่าไฟฟ้าตามห้อง (เฉพาะห้องที่มีผู้เช่า)',
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
                          title: 'ค่าน้ำตามห้อง (เฉพาะห้องที่มีผู้เช่า)',
                          unitLabel: 'L',
                          rows: _waterRows,
                          startKey: 'start',
                          endKey: 'end',
                          qtyKey: 'liters',
                          priceKey: 'unitPrice',
                          amountKey: 'amount',
                          totalLine:
                              'รวมน้ำ: ${_waterTotalLiters.toStringAsFixed(3)} L = ${_waterTotalAmt.toStringAsFixed(2)} บาท',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _usageCard({
    required String title,
    required String unitLabel,
    required List<Map<String, dynamic>> rows,
    String? startKey,
    String? endKey,
    required String qtyKey,
    required String priceKey,
    required String amountKey,
    required String totalLine,
  }) {
    final columns = <DataColumn>[
      const DataColumn(label: Text('ห้อง')),
      const DataColumn(label: Text('สถานะ')),
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
        const DataCell(_StatusChipOccupied()),
        if (startKey != null) DataCell(Text(_fmtQty(start!, unitLabel))),
        if (endKey != null) DataCell(Text(_fmtQty(end!, unitLabel))),
        DataCell(Text(_fmtQty(qty, unitLabel))),
        DataCell(Text(_fmtMoney(price))),
        DataCell(Text(_fmtMoney(amt))),
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
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
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
            child: Text(
              totalLine,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'ไม่มีห้องที่มีผู้เช่าในเดือนนี้',
                style: TextStyle(color: AppColors.textSecondary),
              ),
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
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
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
          ],
        ),
      ),
    );
  }

  Future<void> _debugListDevicesInBuilding() async {
    final url = Uri.parse(
        '$apiBaseUrl/api/owner-electric/meters?buildingId=${widget.buildingId}');
    try {
      final headers = await _authHeaders();
      final r = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        if (!mounted) return;
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
                  final room = (m['roomNumber'] ??
                          m['RoomNumber'] ??
                          m['room_no'] ??
                          '-')
                      .toString();
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
          decoration:
              const InputDecoration(hintText: 'เช่น vdevo1750709890573536'),
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

    final url =
        Uri.parse('$apiBaseUrl/api/owner/tuya/devices/$deviceId/status');
    try {
      final headers = await _authHeaders();
      final r = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('HTTP ${r.statusCode}: ${r.body}')));
        return;
      }
      final body = jsonDecode(r.body);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('DP / Status ที่อ่านได้'),
          content: SingleChildScrollView(
              child: Text(const JsonEncoder.withIndent('  ').convert(body))),
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
}

class _StatusChipOccupied extends StatelessWidget {
  const _StatusChipOccupied();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'มีผู้เช่า',
        style: TextStyle(
          color: Colors.green.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
            label: const Text('ลองอีกครั้ง'),
          ),
        ],
      ),
    );
  }
}