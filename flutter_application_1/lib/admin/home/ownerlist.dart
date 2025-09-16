import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // สำหรับการแปลง JSON

// ไม่จำเป็นต้อง import dashboard.dart ใน list.dart เพื่อหลีกเลี่ยง Circular Dependency

// Data Model สำหรับ Owner
class Owner {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String dorm;
  final String date;
  final String status;

  Owner({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.dorm,
    required this.date,
    required this.status,
  });

  // Factory constructor สำหรับการสร้าง Object Owner จาก JSON
  factory Owner.fromJson(Map<String, dynamic> json) {
    return Owner(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String,
      dorm: json['dorm'] as String,
      date: json['date'] as String,
      status: json['status'] as String,
    );
  }
}

class OwnerListScreen extends StatefulWidget {
  const OwnerListScreen({super.key});

  @override
  State<OwnerListScreen> createState() => _OwnerListScreenState();
}

class _OwnerListScreenState extends State<OwnerListScreen> {
  // Future ที่จะเก็บผลลัพธ์การดึงข้อมูลเจ้าของหอพัก
  late Future<List<Owner>> _ownersFuture;

  @override
  void initState() {
    super.initState();
    _ownersFuture = _fetchOwners(); // เริ่มต้นการดึงข้อมูลเมื่อ Widget ถูกสร้าง
  }

  // เมธอดสำหรับดึงข้อมูลเจ้าของหอพักจาก API
  Future<List<Owner>> _fetchOwners() async {
    // นี่คือ URL ตัวอย่าง คุณจะต้องเปลี่ยนเป็น URL API จริงของคุณ
    // ซึ่งควรจะส่ง JSON ที่มีโครงสร้างเหมือนข้อมูล Mock-up กลับมา
    //
    // หากรัน Backend API บนเครื่องเดียวกัน:
    // - สำหรับ Flutter Web (Chrome, Edge ฯลฯ): ใช้ 'http://localhost:<PORT>/your_api_endpoint' หรือ 'http://127.0.0.1:<PORT>/your_api_endpoint'
    // - สำหรับ Android Emulator: ใช้ 'http://10.0.2.2:<PORT>/your_api_endpoint'
    // - สำหรับ iOS Simulator: ใช้ 'http://localhost:<PORT>/your_api_endpoint'
    //
    // ตัวอย่าง JSON ที่คาดหวังจาก API:
    // [
    //   {"id": "OW001", "name": "ธนาคาร เรืองอ้อย", "phone": "081-234-5678", "email": "thanakorn.r@gmail.com", "dorm": "หอพักรุ่งเรือง", "date": "02/02/2568", "status": "ใช้งานอยู่"},
    //   {"id": "OW002", "name": "สุพัตรา อินทร์ชัย", "phone": "086-112-3344", "email": "supatra.i@gmail.com", "dorm": "หอพักอินทร์สุข", "date": "05/02/2568", "status": "ถูกระงับ"}
    // ]
    final response = await http.get(Uri.parse(
        'http://127.0.0.1:3000/api/owners')); // แก้ไข: เปลี่ยน https เป็น http สำหรับ local development (ถ้าไม่มี SSL)

    if (response.statusCode == 200) {
      // หาก API ตอบกลับมาสำเร็จ (Status Code 200)
      List jsonResponse = json.decode(response.body);
      // แปลง List ของ JSON Object ไปเป็น List ของ Owner Object
      return jsonResponse.map((owner) => Owner.fromJson(owner)).toList();
    } else {
      // หาก API ตอบกลับมาด้วย Error
      throw Exception('Failed to load owners: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFE3F2FD), // Light blue background to match dashboard
      appBar: AppBar(
        backgroundColor:
            const Color(0xFFBBDEFB), // Sidebar blue to match dashboard
        elevation: 0, // No shadow for a flat look
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Color(0xFF1565C0)), // Back icon
          onPressed: () {
            Navigator.pop(
                context); // Go back to the previous screen (dashboard)
          },
        ),
        title: const Text(
          'รายชื่อเจ้าของหอพัก',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0), // Dark blue text
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Align(
          // จัดตำแหน่งให้เนื้อหาอยู่ตรงกลางด้านบน
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // กำหนดขนาดสูงสุดสำหรับเนื้อหาในหน้า
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width *
                  0.9, // กำหนดความกว้างสูงสุด 90% ของหน้าจอ
            ),
            child: FutureBuilder<List<Owner>>(
              future: _ownersFuture, // ใช้ Future ที่เราสร้างไว้
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // แสดง Loading Indicator ขณะรอข้อมูล
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  // แสดงข้อความ Error หากเกิดข้อผิดพลาด
                  return Center(
                    child: Text(
                      'เกิดข้อผิดพลาดในการโหลดข้อมูล: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  // แสดงข้อความเมื่อไม่มีข้อมูล
                  return const Center(child: Text('ไม่พบข้อมูลเจ้าของหอพัก'));
                } else {
                  // แสดงตารางเมื่อมีข้อมูล
                  final owners = snapshot.data!;
                  return _buildOwnerTable(owners);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  // อัปเดตเมธอด _buildOwnerTable ให้รับ List<Owner> เข้ามา
  Widget _buildOwnerTable(List<Owner> owners) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        // ClipRRect to ensure rounded corners for the table content
        borderRadius: BorderRadius.circular(15),
        child: DataTable(
          headingRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              return const Color(0xFFE3F2FD); // Light blue for header row
            },
          ),
          dataRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              return Colors.white; // Default for all data rows if not selected
            },
          ),
          columnSpacing: 20,
          horizontalMargin: 20,
          columns: const <DataColumn>[
            DataColumn(
              label: Text(
                'รหัสประจำตัว',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ชื่อ-นามสกุล',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'เบอร์โทร',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'อีเมล',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ชื่อหอพัก',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'วันที่สมัคร',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'สถานะบัญชี',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0)),
              ),
            ),
          ],
          rows: List<DataRow>.generate(
            owners.length,
            (index) {
              final owner = owners[index];
              final isSuspended = owner.status == 'ถูกระงับ';
              final isOddRow = index % 2 != 0; // Check if the row index is odd

              return DataRow(
                key: ValueKey(owner.id), // Unique key for each row
                color: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(
                          0xFFBBDEFB); // Slightly darker blue when selected
                    }
                    return isOddRow
                        ? Colors.grey.withOpacity(0.05)
                        : Colors.white; // Alternating color
                  },
                ),
                cells: <DataCell>[
                  DataCell(Text(owner.id)),
                  DataCell(Text(owner.name)),
                  DataCell(Text(owner.phone)),
                  DataCell(Text(owner.email)),
                  DataCell(Text(owner.dorm)),
                  DataCell(Text(owner.date)),
                  DataCell(
                    Text(
                      owner.status,
                      style: TextStyle(
                        color: isSuspended ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
