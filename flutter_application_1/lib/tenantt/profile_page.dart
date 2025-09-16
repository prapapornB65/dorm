import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/auth/login_page.dart';
import 'package:flutter_application_1/config/api_config.dart';

final url = '$apiBaseUrl/api/some-endpoint';


class ProfilePage extends StatefulWidget {
  final int tenantId;
  const ProfilePage({super.key, required this.tenantId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

String formatDateOnly(String? rawDate) {
  if (rawDate == null) return '-';
  try {
    final date = DateTime.parse(rawDate);
    return DateFormat('dd/MM/yyyy').format(date);
  } catch (e) {
    return '-';
  }
}

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    initialRoute: '/LoginPage',
    routes: {
      '/LoginPage': (context) => LoginPage(), // ✅ ตรงกับ pushNamed
      '/ProfilePage': (context) => ProfilePage(tenantId: 1), // ตัวอย่าง
    },
  ));
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? profileData;
  bool isLoading = true;
  bool isUploading = false;

  @override
  void initState() {
    super.initState();
    fetchTenantRoomInfo(widget.tenantId);
  }

  Future<void> fetchTenantRoomInfo(int tenantId) async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/tenant/$tenantId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Full profileData: $data'); // เพิ่ม log ทั้ง object
        print('Profile image URL: ${data['ProfileImage']}');
        setState(() {
          profileData = data;
          isLoading = false;
        });
      } else {
        print('❌ Server error: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('❌ fetchTenantRoomInfo error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() => isUploading = true);

    final file = File(pickedFile.path);
    final formData = FormData.fromMap({
      'tenantId': widget.tenantId.toString(),
      'image': await MultipartFile.fromFile(file.path,
          filename: file.path.split('/').last),
    });

    try {
      final response = await Dio().post(
        '$apiBaseUrl/api/upload-profile',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดรูปโปรไฟล์สำเร็จ ✅')),
        );
        await fetchTenantRoomInfo(widget.tenantId);
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      print('❌ Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปโหลด ❌')),
      );
    } finally {
      setState(() => isUploading = false);
    }
  }

  Widget _buildProfileInfo(IconData icon, String label, String value) {
    const primaryColor = Color(0xFF4C7C5A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: '$label: ',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Colors.black87,
                ),
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w400,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF4C7C5A);
    final bgColor = Colors.grey.shade100;

    // เช็คว่า profileData มี ProfileImage ที่เป็น String และไม่ว่างเปล่า
    bool hasProfileImage = profileData != null &&
        profileData!['ProfileImage'] != null &&
        profileData!['ProfileImage'] is String &&
        (profileData!['ProfileImage'] as String).trim().isNotEmpty;

    Uri? imageUri;
    if (hasProfileImage) {
      final profileImage = profileData!['ProfileImage'] as String;
      if (profileImage.startsWith('http')) {
        imageUri = Uri.parse(profileImage);
      } else {
        imageUri = Uri.parse(apiBaseUrl).resolve(profileImage);
      }
    }

    print('Displaying profile image URL: ${profileData?['ProfileImage']}');

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('โปรไฟล์'),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await FirebaseAuth.instance.signOut(); // ✅ สำคัญ

              Navigator.of(context).pushNamedAndRemoveUntil(
                '/LoginPage',
                (Route<dynamic> route) => false,
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 5,
                color: Colors.white,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 70,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: hasProfileImage
                            ? NetworkImage(imageUri.toString())
                            : null,
                        child: hasProfileImage
                            ? null
                            : const Icon(Icons.person,
                                size: 70, color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: isUploading ? null : pickAndUploadImage,
                        icon: isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.edit),
                        label: Text(isUploading
                            ? 'กำลังอัปโหลด...'
                            : 'แก้ไขรูปโปรไฟล์'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 20),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ข้อมูลผู้เช่า',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Divider(
                        thickness: 2,
                        color: Color(0xFF4C7C5A),
                        height: 28,
                      ),
                      _buildProfileInfo(Icons.person, 'ชื่อ',
                          '${profileData?['FirstName']} ${profileData?['LastName']}'),
                      _buildProfileInfo(Icons.cake, 'วันเกิด',
                          formatDateOnly(profileData?['BirthDate'])),
                      _buildProfileInfo(Icons.phone, 'เบอร์โทร',
                          profileData?['Phone'] ?? '-'),
                      _buildProfileInfo(Icons.meeting_room, 'ห้องพัก',
                          profileData?['RoomNumber'] ?? '-'),
                      _buildProfileInfo(Icons.date_range, 'เริ่มสัญญาเช่า',
                          formatDateOnly(profileData?['Start'])),
                      _buildProfileInfo(Icons.event_busy, 'สิ้นสุดสัญญาเช่า',
                          formatDateOnly(profileData?['End'])),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
