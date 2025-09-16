import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON decoding

// Data Model for Notification
class NotificationItem {
  final String id;
  final String time; // e.g., "09:30 น."
  final String date; // e.g., "12/05/67"
  final String type; // e.g., "ระบบ", "ประกาศ", "ความปลอดภัย"
  final String detail; // Message content
  final String status; // "อ่านแล้ว" or "ยังไม่อ่าน"
  final DateTime rawDateTime; // For internal sorting if needed

  NotificationItem({
    required this.id,
    required this.time,
    required this.date,
    required this.type,
    required this.detail,
    required this.status,
    required this.rawDateTime,
  });

  // Factory constructor for creating a NotificationItem object from JSON
  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      time: json['time'] as String,
      date: json['date'] as String,
      type: json['type'] as String,
      detail: json['detail'] as String,
      status: json['status'] as String,
      rawDateTime: DateTime.parse(json['rawDateTime']), // Parse from ISO 8601 string
    );
  }
}

class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  late Future<List<NotificationItem>> _notificationsFuture;
  List<NotificationItem> _allNotifications = []; // To store all fetched notifications
  List<NotificationItem> _filteredNotifications = []; // To store currently displayed notifications

  final TextEditingController _searchController = TextEditingController();
  String _selectedType = 'ทั้งหมด'; // For filter by type
  String _selectedDate = 'ทั้งหมด'; // For filter by date

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _fetchNotifications();
    _searchController.addListener(_filterNotifications);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Method to fetch notification data from the Backend API with logging
  Future<List<NotificationItem>> _fetchNotifications() async {
    final apiUrl = Uri.parse('http://127.0.0.1:3000/api/admin-notifications'); // Change to your actual Backend URL
    print('Attempting to fetch admin notifications from: $apiUrl');

    try {
      final response = await http.get(apiUrl);

      print('Notification List Response Status Code: ${response.statusCode}');
      print('Notification List Response Body: ${response.body}');

      if (response.statusCode == 200) {
        List jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        _allNotifications = jsonResponse.map((item) => NotificationItem.fromJson(item)).toList();
        _allNotifications.sort((a, b) => b.rawDateTime.compareTo(a.rawDateTime)); // Sort by date (newest first)
        _filterNotifications(); // Apply initial filters/search
        return _allNotifications;
      } else {
        print('Error: API returned a non-200 status code for notifications list.');
        throw Exception('Failed to load notifications: ${response.statusCode}');
      }
    } catch (e) {
      print('Network or other error occurred while fetching notifications: $e');
      throw Exception('Failed to connect to API or other network issue for notifications: $e');
    }
  }

  void _filterNotifications() {
    setState(() {
      _filteredNotifications = _allNotifications.where((notification) {
        final query = _searchController.text.toLowerCase();
        final matchesSearch = notification.type.toLowerCase().contains(query) ||
                              notification.detail.toLowerCase().contains(query) ||
                              notification.status.toLowerCase().contains(query);

        final matchesType = _selectedType == 'ทั้งหมด' || notification.type == _selectedType;

        // Simplified date filter for demonstration. For complex date filtering,
        // you might need a date picker and more robust logic.
        final matchesDate = _selectedDate == 'ทั้งหมด' || (notification.date == _selectedDate);

        return matchesSearch && matchesType && matchesDate;
      }).toList();
    });
  }

  // Handle marking notification as read
  Future<void> _markAsRead(String id) async {
    final apiUrl = Uri.parse('http://127.0.0.1:3000/api/notifications/mark-read/$id');
    try {
      final response = await http.post(apiUrl);
      if (response.statusCode == 200) {
        setState(() {
          // Update the status locally without re-fetching all data
          final index = _allNotifications.indexWhere((noti) => noti.id == id);
          if (index != -1) {
            final updatedNoti = NotificationItem(
              id: _allNotifications[index].id,
              time: _allNotifications[index].time,
              date: _allNotifications[index].date,
              type: _allNotifications[index].type,
              detail: _allNotifications[index].detail,
              status: 'อ่านแล้ว', // Mark as read
              rawDateTime: _allNotifications[index].rawDateTime,
            );
            _allNotifications[index] = updatedNoti;
            _filterNotifications(); // Re-apply filters to update UI
          }
        });
        _showMessage(context, 'แจ้งเตือนถูกทำเครื่องหมายว่าอ่านแล้ว');
      } else {
        _showMessage(context, 'ไม่สามารถทำเครื่องหมายว่าอ่านแล้วได้: ${response.statusCode}');
      }
    } catch (e) {
      _showMessage(context, 'เกิดข้อผิดพลาดในการทำเครื่องหมายว่าอ่านแล้ว: $e');
    }
  }

  // Handle deleting notification
  Future<void> _deleteNotification(String id) async {
    // Show a confirmation dialog before deleting
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบการแจ้งเตือนนี้?'),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('ลบ'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      final apiUrl = Uri.parse('http://127.0.0.1:3000/api/notifications/$id');
      try {
        final response = await http.delete(apiUrl);
        if (response.statusCode == 200) {
          setState(() {
            _allNotifications.removeWhere((noti) => noti.id == id);
            _filterNotifications(); // Re-apply filters to update UI
          });
          _showMessage(context, 'แจ้งเตือนถูกลบเรียบร้อยแล้ว');
        } else {
          _showMessage(context, 'ไม่สามารถลบแจ้งเตือนได้: ${response.statusCode}');
        }
      } catch (e) {
        _showMessage(context, 'เกิดข้อผิดพลาดในการลบแจ้งเตือน: $e');
      }
    }
  }

  // Helper function to show a simple message (instead of alert)
  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      appBar: AppBar(
        backgroundColor: const Color(0xFFBBDEFB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1565C0)),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'การแจ้งเตือนระบบ',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.95, // Wider for notifications table
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilterAndSearchRow(), // Search and filter row
                const SizedBox(height: 20),
                FutureBuilder<List<NotificationItem>>(
                  future: _notificationsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'เกิดข้อผิดพลาดในการโหลดข้อมูลการแจ้งเตือน: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      );
                    } else if (!snapshot.hasData || _filteredNotifications.isEmpty) {
                      return const Center(child: Text('ไม่พบข้อมูลการแจ้งเตือน'));
                    } else {
                      return _buildNotificationTable(_filteredNotifications);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterAndSearchRow() {
    // A simplified list of notification types for filtering
    final List<String> notificationTypes = ['ทั้งหมด', 'ระบบ', 'ประกาศ', 'ความปลอดภัย', 'ซ่อมระบบ'];
    // For date filter, you might want a date picker or specific date options
    final List<String> dateOptions = ['ทั้งหมด', 'วันนี้', 'เมื่อวาน']; // Simplified

    return Row(
      children: [
        // Search bar
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ค้นหา',
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Color(0xFF42A5F5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Type filter dropdown
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedType,
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF42A5F5)),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedType = newValue!;
                    _filterNotifications();
                  });
                },
                items: notificationTypes.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Date filter dropdown (simplified for now)
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDate,
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF42A5F5)),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedDate = newValue!;
                    // Implement more complex date filtering logic here if needed
                    _filterNotifications();
                  });
                },
                items: dateOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Select button (if needed for manual trigger)
        // ElevatedButton(
        //   onPressed: _filterNotifications,
        //   child: const Text('เลือก'),
        // ),
      ],
    );
  }

  Widget _buildNotificationTable(List<NotificationItem> notifications) {
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
        borderRadius: BorderRadius.circular(15),
        child: DataTable(
          headingRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              return const Color(0xFFE3F2FD); // Light blue for header row
            },
          ),
          dataRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              return Colors.white; // Default for all data rows
            },
          ),
          columnSpacing: 20,
          horizontalMargin: 20,
          columns: const <DataColumn>[
            DataColumn(
              label: Text(
                'เวลา',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ประเภท',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'รายละเอียด',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'สถานะ',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'การจัดการ',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
          ],
          rows: List<DataRow>.generate(
            notifications.length,
            (index) {
              final notification = notifications[index];
              final isOddRow = index % 2 != 0;

              Color statusColor;
              switch (notification.status) {
                case 'อ่านแล้ว':
                  statusColor = Colors.grey; // Gray for read
                  break;
                case 'ยังไม่อ่าน':
                  statusColor = Colors.red; // Red for unread
                  break;
                default:
                  statusColor = Colors.black;
              }

              return DataRow(
                key: ValueKey(notification.id),
                color: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFBBDEFB);
                    }
                    return isOddRow ? Colors.grey.withOpacity(0.05) : Colors.white;
                  },
                ),
                cells: <DataCell>[
                  DataCell(Text('${notification.time}\n${notification.date}')), // Combine time and date
                  DataCell(Text(notification.type)),
                  DataCell(Text(notification.detail)),
                  DataCell(
                    Text(
                      notification.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        if (notification.status == 'ยังไม่อ่าน')
                          ElevatedButton(
                            onPressed: () => _markAsRead(notification.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              minimumSize: Size.zero, // Remove fixed size constraints
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Shrink wrap tap area
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('อ่านแล้ว', style: TextStyle(fontSize: 12)),
                          ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _deleteNotification(notification.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            minimumSize: Size.zero, // Remove fixed size constraints
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Shrink wrap tap area
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('ลบ', style: TextStyle(fontSize: 12)),
                        ),
                      ],
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
