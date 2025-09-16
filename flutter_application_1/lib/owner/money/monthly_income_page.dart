import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_application_1/config/api_config.dart';

final url = '$apiBaseUrl/api/some-endpoint';

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
  double totalMonthlyIncome = 0;
  List<dynamic> tenantPayments = [];

  @override
  void initState() {
    super.initState();
    fetchMonthlyIncome();
  }

  Future<void> fetchMonthlyIncome() async {
    print(
        '📡 เริ่มเรียก API: $apiBaseUrl/api/building/${widget.buildingId}/monthly-income');
    try {
      final url = Uri.parse(
          '$apiBaseUrl/api/building/${widget.buildingId}/monthly-income');
      final res = await http.get(url);

      print('📥 Response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        print('📊 Response body: $data');

        setState(() {
          totalMonthlyIncome =
              double.tryParse(data['totalBalance'].toString()) ?? 0;
          tenantPayments = data['payments'] ?? [];
          isLoading = false;
        });
      } else {
        print("❌ Error: ${res.statusCode}");
        print('📝 Response body: ${res.body}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("❌ Exception: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('รายรับต่อเดือน - ${widget.buildingName}'),
        backgroundColor: Colors.blueAccent,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // การ์ดสรุปรายรับรวม
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'รายรับรวมต่อเดือน',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${totalMonthlyIncome.toStringAsFixed(2)} บาท',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ตารางผู้เช่า
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('ผู้เช่า')),
                        DataColumn(label: Text('จำนวนเงิน')),
                        DataColumn(label: Text('วันที่ชำระ')),
                        DataColumn(label: Text('สถานะ')),
                      ],
                      rows: tenantPayments.map<DataRow>((p) {
                        return DataRow(cells: [
                          DataCell(Text(p['tenantname'] ?? '')),
                          DataCell(Text(p['totalamount']?.toString() ?? '0')),
                          DataCell(Text(p['paymentdate'] ?? '')),
                          DataCell(Text(p['status'] ?? '')),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
