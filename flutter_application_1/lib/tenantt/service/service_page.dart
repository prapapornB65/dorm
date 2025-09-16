import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import 'ContactOwnerPage.dart';
import 'UsageHistoryPage.dart';
import 'package:flutter_application_1/config/api_config.dart';

// ✅ ดีไซน์
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/color_app.dart';

final url = '$apiBaseUrl/api/some-endpoint';

class ServicePage extends StatefulWidget {
  final int tenantId;
  const ServicePage({super.key, required this.tenantId});

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  bool isLoading = true;
  Map<String, dynamic>? tenantData;
  List<dynamic> repairHistory = [];
  List<String> availableEquipments = [];
  Map<String, List<String>> symptomMap = {};

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController additionalController = TextEditingController();

  String selectedSection = 'repair';
  String selectedEquipment = '';
  String selectedSymptom = '';

  // ✅ ใหม่: toggle แสดงทั้งหมด/แสดงแค่ 5
  bool _showAllRepairs = false;

  @override
  void initState() {
    super.initState();
    fetchTenantService();
  }

  Future<void> fetchTenantService() async {
    final uri = Uri.parse('$apiBaseUrl/api/tenant-room-detail/${widget.tenantId}');
    try {
      final response = await http.get(uri);
      debugPrint('📦 Raw response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Decoded JSON: $data');

        setState(() {
          tenantData = data['tenant'];
          repairHistory = data['repairs'] ?? [];
          phoneController.text = data['tenant']?['phone'] ?? '';
          availableEquipments = List<String>.from(data['equipments'] ?? []);

          final rawSymptomMap = data['symptomMap'] ?? {};
          symptomMap = Map<String, List<String>>.from(
            rawSymptomMap.map((k, v) => MapEntry(k, List<String>.from(v))),
          );

          if (availableEquipments.isNotEmpty) {
            selectedEquipment = availableEquipments.first;
            selectedSymptom = symptomMap[selectedEquipment]?.first ?? '';
          }

          isLoading = false;
        });
      } else {
        throw Exception('โหลดข้อมูลล้มเหลว (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ fetchTenantService error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> submitRepairRequest() async {
    final uri = Uri.parse('$apiBaseUrl/api/repair-request');
    final body = {
      'tenantId': widget.tenantId,
      'roomNumber': tenantData?['RoomNumber'],
      'equipment': selectedEquipment,
      'issueDetail': selectedSymptom,
      'additional': additionalController.text,
      'phone': phoneController.text,
    };

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แจ้งซ่อมสำเร็จ ✅')),
        );
        await fetchTenantService();
      } else {
        throw Exception('แจ้งซ่อมไม่สำเร็จ');
      }
    } catch (e) {
      debugPrint('❌ submitRepairRequest error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  String formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    return date != null ? DateFormat('dd/MM/yyyy').format(date) : '-';
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('การบริการ'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: AppColors.card,
            onSelected: (value) {
              if (value == 'repair') {
                setState(() => selectedSection = value);
              } else if (value == 'contact') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ContactOwnerPage(tenantId: widget.tenantId),
                  ),
                );
              } else if (value == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UsageHistoryPage(tenantId: widget.tenantId),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'repair', child: Text('แจ้งซ่อม')),
              PopupMenuItem(value: 'contact', child: Text('ติดต่อเจ้าของหอพัก')),
              PopupMenuItem(value: 'history', child: Text('ประวัติการใช้งาน')),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRepairForm(),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text(
                        'รายละเอียดการแจ้งซ่อม',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      if (repairHistory.length > 5 && !_showAllRepairs)
                        TextButton(
                          onPressed: () => setState(() => _showAllRepairs = true),
                          child: const Text('ดูทั้งหมด'),
                        ),
                      if (_showAllRepairs && repairHistory.length > 5)
                        TextButton(
                          onPressed: () => setState(() => _showAllRepairs = false),
                          child: const Text('ย่อ'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ✅ แสดงสูงสุด 5 รายการก่อน ถ้ามีมากกว่าให้กด "ดูทั้งหมด"
                  ..._visibleRepairs().map((repair) {
                    final status = (repair['status'] ?? '-') as String;
                    final isDone = status == 'เสร็จ';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NeumorphicCard(
                        child: ListTile(
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.build, color: AppColors.primary),
                          ),
                          title: Text(
                            repair['equipment'] ?? '',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            'วันที่แจ้ง: ${formatDate(repair['requestdate'] ?? '')}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            status,
                            style: TextStyle(
                              color: isDone ? Colors.green : AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
    );
  }

  // ---------- UI เฉพาะฟอร์ม (เปลี่ยนแต่ดีไซน์ ไม่แตะ logic) ----------
  Widget _buildRepairForm() {
    return NeumorphicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'เลขห้อง : ${tenantData?['RoomNumber'] ?? '-'}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          // ชื่ออุปกรณ์
          Row(
            children: [
              Text('ชื่ออุปกรณ์ : ', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedEquipment.isEmpty && availableEquipments.isNotEmpty
                          ? availableEquipments.first
                          : selectedEquipment,
                      isExpanded: true,
                      onChanged: (value) {
                        setState(() {
                          selectedEquipment = value ?? '';
                          selectedSymptom = symptomMap[selectedEquipment]?.first ?? '';
                        });
                      },
                      items: availableEquipments
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // อาการชำรุด
          Row(
            children: [
              Text('อาการชำรุด : ', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSymptom,
                      isExpanded: true,
                      onChanged: (value) => setState(() => selectedSymptom = value ?? ''),
                      items: (symptomMap[selectedEquipment] ?? [])
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // เพิ่มเติม
          Text('เพิ่มเติม :', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: additionalController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'กรอกรายละเอียดเพิ่มเติม',
            ),
          ),
          const SizedBox(height: 12),

          // เบอร์โทร
          Text('เบอร์โทร :', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: phoneController,
            decoration: const InputDecoration(
              labelText: 'เบอร์โทร',
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),

          // วันที่
          Text(
            'วันที่แจ้งซ่อม : ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // ปุ่มยืนยัน
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 150,
              child: AppButton(
                label: 'ยืนยัน',
                icon: Icons.send,
                onPressed: submitRepairRequest,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  // ✅ คำนวณรายการที่จะแสดง (สูงสุด 5 ถ้าไม่ได้กด "ดูทั้งหมด")
  List<dynamic> _visibleRepairs() {
    if (_showAllRepairs) return repairHistory;
    if (repairHistory.length <= 5) return repairHistory;
    return repairHistory.take(5).toList();
  }
}
