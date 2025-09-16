import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Data Model for Latest Activities
class ActivityLog {
  final String date;
  final String account;
  final String activity;

  ActivityLog(
      {required this.date, required this.account, required this.activity});

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      date: json['date'] as String,
      account: json['account'] as String,
      activity: json['activity'] as String,
    );
  }
}

// Data Model for Login History
class LoginHistory {
  final String date;
  final String account;
  final String ip;
  final String status;

  LoginHistory(
      {required this.date,
      required this.account,
      required this.ip,
      required this.status});

  factory LoginHistory.fromJson(Map<String, dynamic> json) {
    return LoginHistory(
      date: json['date'] as String,
      account: json['account'] as String,
      ip: json['ip'] as String,
      status: json['status'] as String,
    );
  }
}

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  // TODO: แก้ไข URL ให้เป็นที่อยู่ของ server ของคุณ
  static const String serverUrl = 'http://<your-backend-ip>:3000';

  List<ActivityLog> _latestActivities = [];
  List<LoginHistory> _loginHistory = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Mock data for Latest Anomalies
  final List<String> _latestAnomalies = [
    'การเข้าสู่ระบบล้มเหลวจาก IP 192.168.1.5 จำนวน 5 ครั้ง',
    'บัญชี Admin001 เข้าถึงข้อมูลส่วนตัวของผู้เช่า OW003',
    'แก้ไขข้อมูลห้อง R001 โดยผู้ใช้ที่ไม่มีสิทธิ์',
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _fetchActivities();
      await _fetchLoginHistory();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load data: $e';
      _latestActivities = [];
      _loginHistory = [];
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchActivities() async {
    final response =
        await http.get(Uri.parse('$serverUrl/api/security/activities'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        _latestActivities =
            data.map((json) => ActivityLog.fromJson(json)).toList();
      });
    } else {
      throw Exception('Failed to load latest activities');
    }
  }

  Future<void> _fetchLoginHistory() async {
    final response =
        await http.get(Uri.parse('$serverUrl/api/security/login-history'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        _loginHistory =
            data.map((json) => LoginHistory.fromJson(json)).toList();
      });
    } else {
      throw Exception('Failed to load login history');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ความปลอดภัยของระบบ',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF4C7C5A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('กิจกรรมล่าสุด'),
                        const SizedBox(height: 12),
                        _buildActivitiesTable(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('ประวัติการเข้าสู่ระบบ'),
                        const SizedBox(height: 12),
                        _buildLoginHistoryTable(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('รายการผิดปกติล่าสุด'),
                        const SizedBox(height: 12),
                        _buildAnomaliesList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF4C7C5A),
      ),
    );
  }

  // Helper method to build the Latest Activities table
  Widget _buildActivitiesTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: MaterialStateColor.resolveWith(
              (states) => const Color(0xFFF0F0F0)),
          columns: const <DataColumn>[
            DataColumn(label: Text('วันที่')),
            DataColumn(label: Text('บัญชีผู้ใช้')),
            DataColumn(label: Text('กิจกรรม')),
          ],
          rows: _latestActivities.map((activity) {
            return DataRow(
              cells: <DataCell>[
                DataCell(Text(activity.date)),
                DataCell(Text(activity.account)),
                DataCell(Text(activity.activity)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helper method to build the Login History table
  Widget _buildLoginHistoryTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: MaterialStateColor.resolveWith(
              (states) => const Color(0xFFF0F0F0)),
          columns: const <DataColumn>[
            DataColumn(label: Text('วันที่')),
            DataColumn(label: Text('บัญชีผู้ใช้')),
            DataColumn(label: Text('IP Address')),
            DataColumn(label: Text('สถานะ')),
          ],
          rows: _loginHistory.map((history) {
            Color statusColor;
            switch (history.status) {
              case 'สำเร็จ':
                statusColor = Colors.green;
                break;
              case 'ล้มเหลว':
                statusColor = Colors.red;
                break;
              default:
                statusColor = Colors.black;
                break;
            }

            return DataRow(
              cells: <DataCell>[
                DataCell(Text(history.date)),
                DataCell(Text(history.account)),
                DataCell(Text(history.ip)),
                DataCell(Text(
                  history.status,
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.bold),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helper method to build the Latest Anomalies list
  Widget _buildAnomaliesList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _latestAnomalies.map((anomaly) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    anomaly,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
