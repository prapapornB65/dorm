import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/auth/login_page.dart' hide AppColors;
import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/widgets/gradient_app_bar.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/widgets/app_button.dart'; // ถ้าจะใช้ปุ่มแอป

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 24),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    return GradientScaffold(
      appBar: const GradientAppBar(title: 'โปรไฟล์'),
      topRadius: 0, // ชนหัว ไม่โค้งด้านบน
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                color: AppColors.card,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 64,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: (profileData?['ProfileImage']
                                    is String &&
                                (profileData!['ProfileImage'] as String)
                                    .trim()
                                    .isNotEmpty)
                            ? NetworkImage(
                                (profileData!['ProfileImage'] as String)
                                        .startsWith('http')
                                    ? profileData!['ProfileImage']
                                    : Uri.parse(apiBaseUrl)
                                        .resolve(profileData!['ProfileImage'])
                                        .toString(),
                              )
                            : null,
                        child: (profileData?['ProfileImage'] == null ||
                                (profileData!['ProfileImage'] as String)
                                    .trim()
                                    .isEmpty)
                            ? const Icon(Icons.person,
                                size: 64, color: AppColors.textSecondary)
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // ปุ่มแก้รูป (ธีมเดียวกัน)
                      SizedBox(
                        width: 200,
                        child: AppButton(
                          label:
                              isUploading ? 'กำลังอัปโหลด…' : 'แก้ไขรูปโปรไฟล์',
                          icon: isUploading ? Icons.hourglass_top : Icons.edit,
                          onPressed: isUploading ? null : pickAndUploadImage,
                          height: 46,
                          radius: 28, // 👈 มุมฉากแบบเดียวกับ square
                        ),
                      ),

                      const SizedBox(height: 26),

                      // หัวข้อ
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ข้อมูลผู้เช่า',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: AppColors.border, thickness: 1),

                      // รายการข้อมูล
                      _buildProfileInfo(Icons.person, 'ชื่อ',
                          '${profileData?['FirstName'] ?? '-'} ${profileData?['LastName'] ?? ''}'),
                      _buildProfileInfo(Icons.cake, 'วันเกิด',
                          formatDateOnly(profileData?['BirthDate'])),
                      _buildProfileInfo(Icons.phone, 'เบอร์โทร',
                          profileData?['Phone']?.toString() ?? '-'),
                      _buildProfileInfo(Icons.meeting_room, 'ห้องพัก',
                          profileData?['RoomNumber']?.toString() ?? '-'),
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
