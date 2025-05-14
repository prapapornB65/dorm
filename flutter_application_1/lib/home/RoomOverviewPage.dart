import 'package:flutter/material.dart';
import 'room_detail_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RoomOverviewPage extends StatefulWidget {
  const RoomOverviewPage({super.key});

  @override
  State<RoomOverviewPage> createState() => _RoomOverviewPageState();
}

class _RoomOverviewPageState extends State<RoomOverviewPage> {
  Map<String, dynamic>? roomData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchRoomOverview();
  }

  Future<void> fetchRoomOverview() async {
  final uri = Uri.parse("http://10.0.2.2:3000/api/room-overview/1");

    try {
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() {
          roomData = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("🚨 Error: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("หอพักแสงแดด")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : roomData == null
              ? const Center(child: Text("ไม่พบข้อมูล"))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // ห้อง + ผู้เช่า (ดึงจาก API)
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundImage: NetworkImage(roomData!['avatar_url']),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ห้อง ${roomData!['room_number']}'),
                              Text('ชื่อ: ${roomData!['tenant_name']}'),
                              Text('เข้าเมื่อวันที่ ${roomData!['move_in_date']}'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // รายละเอียดห้อง (Mock)
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        child: Column(
                          children: [
                            Image.asset('assets/images/room.jpg'),
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('ค่าห้อง 3,000 บาท\nค่าส่วนกลาง 1,000 บาท\nพื้นที่ 30.4 ตร.ม.'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const RoomDetailPage(roomId: 1),
                                  ),
                                );
                              },
                              child: const Text("more"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
