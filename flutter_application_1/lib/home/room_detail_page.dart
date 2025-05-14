import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RoomDetailPage extends StatefulWidget {
  final int roomId; // ส่งเข้ามาจากหน้า overview

  const RoomDetailPage({super.key, required this.roomId});

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  Map<String, dynamic>? roomData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchRoomDetail();
  }

  Future<void> fetchRoomDetail() async {
    final url = Uri.parse('http://10.0.2.2:3000/api/room/${widget.roomId}');

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        setState(() {
          roomData = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        debugPrint("❌ ไม่พบข้อมูลห้อง");
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("🚨 Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("รายละเอียดห้อง")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : roomData == null
              ? const Center(child: Text("ไม่พบข้อมูลห้อง"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(roomData!['image_url'] ?? ''),
                      const SizedBox(height: 16),
                      Text("ห้อง ${roomData!['room_number']}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("ขนาด: ${roomData!['size']} ตร.ม."),
                      Text("ราคา: ${roomData!['price']} บาท/เดือน"),
                      Text("เฟอร์นิเจอร์: ${roomData!['furniture']}"),
                    ],
                  ),
                ),
    );
  }
}
