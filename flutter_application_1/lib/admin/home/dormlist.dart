import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON decoding

// Data Model for Dorm
class Dorm {
  final String id; // BuildingID
  final String dormName; // BuildingName
  final String ownerName; // Owner's FirstName + LastName
  final String ownerPhone; // Owner's Phone
  final String registeredDate; // Date the building was registered
  final String totalFloors; // Total number of floors
  final String totalRooms; // Total number of rooms
  final String status; // Status of the dorm (e.g., "เปิดให้ใช้งาน", "ปิดปรับปรุง", "ถูกระงับ")

  Dorm({
    required this.id,
    required this.dormName,
    required this.ownerName,
    required this.ownerPhone,
    required this.registeredDate,
    required this.totalFloors,
    required this.totalRooms,
    required this.status,
  });

  // Factory constructor for creating a Dorm object from JSON
  factory Dorm.fromJson(Map<String, dynamic> json) {
    return Dorm(
      id: json['id'] as String,
      dormName: json['dormName'] as String,
      ownerName: json['ownerName'] as String,
      ownerPhone: json['ownerPhone'] as String,
      registeredDate: json['registeredDate'] as String,
      totalFloors: json['totalFloors'] as String,
      totalRooms: json['totalRooms'] as String,
      status: json['status'] as String,
    );
  }
}

class DormListScreen extends StatefulWidget {
  const DormListScreen({super.key});

  @override
  State<DormListScreen> createState() => _DormListScreenState();
}

class _DormListScreenState extends State<DormListScreen> {
  late Future<List<Dorm>> _dormsFuture;

  @override
  void initState() {
    super.initState();
    _dormsFuture = _fetchDorms(); // Start fetching data when the widget is initialized
  }

  // Method to fetch dorm data from the Backend API
  Future<List<Dorm>> _fetchDorms() async {
    // **IMPORTANT: Change this URL to your actual Backend API URL**
    // If running on the same machine:
    //   - For Flutter Web (Chrome): 'http://localhost:3000/api/dorms'
    //   - For Android Emulator: 'http://10.0.2.2:3000/api/dorms'
    //   - For iOS Simulator: 'http://localhost:3000/api/dorms'
    // Change 3000 to your backend's port.
    final apiUrl = Uri.parse('http://localhost:3000/api/dorms'); // TODO: Change this URL to your actual Backend URL
    print('Attempting to fetch dorm data from: $apiUrl'); // Log: Show the URL being called

    try {
      final response = await http.get(apiUrl);

      print('Dorm List Response Status Code: ${response.statusCode}'); // Log: Show Status Code
      print('Dorm List Response Body: ${response.body}'); // Log: Show Response Body

      if (response.statusCode == 200) {
        // If API returns success (Status Code 200)
        List jsonResponse = json.decode(utf8.decode(response.bodyBytes)); // Use utf8.decode for Thai characters
        // Convert List of JSON Objects to List of Dorm Objects
        return jsonResponse.map((dorm) => Dorm.fromJson(dorm)).toList();
      } else {
        // If API returns an error
        print('Error: API returned a non-200 status code for dorms list.'); // Log: Error message
        throw Exception('Failed to load dorms: ${response.statusCode}');
      }
    } catch (e) {
      // Catch network or other connection errors
      print('Network or other error occurred while fetching dorms: $e'); // Log: Show the error details
      throw Exception('Failed to connect to API or other network issue for dorms: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD), // Light blue background
      appBar: AppBar(
        backgroundColor: const Color(0xFFBBDEFB), // Sidebar blue
        elevation: 0, // No shadow for a flat look
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1565C0)), // Back icon
          onPressed: () {
            Navigator.pop(context); // Go back to the previous screen (dashboard)
          },
        ),
        title: const Text(
          'รายการหอพักทั้งหมด',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0), // Dark blue text
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Align( // Align content to top center
          alignment: Alignment.topCenter,
          child: ConstrainedBox( // Constrain max width for responsiveness
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9, // Max width 90% of screen
            ),
            child: FutureBuilder<List<Dorm>>(
              future: _dormsFuture, // Use the Future we created
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Show Loading Indicator while waiting for data
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  // Show error message if an error occurs
                  return Center(
                    child: Text(
                      'เกิดข้อผิดพลาดในการโหลดข้อมูลหอพัก: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  // Show message when no data is found, and an empty table
                  return Column(
                    children: [
                      const Center(child: Text('ไม่พบข้อมูลหอพัก')),
                      const SizedBox(height: 20),
                      _buildDormTable([]) // Show an empty table
                    ],
                  );
                } else {
                  // Show the table when data is available
                  final dorms = snapshot.data!;
                  return _buildDormTable(dorms);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  // Method to build the dorm list table, now accepts List<Dorm>
  Widget _buildDormTable(List<Dorm> dorms) {
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
      child: ClipRRect( // ClipRRect to ensure rounded corners for the table content
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
                'รหัสหอพัก',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ชื่อหอพัก',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ชื่อ-นามสกุล',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'เบอร์โทร',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'วันที่สมัคร',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ชั้น',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'ห้อง',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
            DataColumn(
              label: Text(
                'สถานะหอพัก',
                style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
              ),
            ),
          ],
          rows: List<DataRow>.generate(
            dorms.length,
            (index) {
              final dorm = dorms[index];
              final isOddRow = index % 2 != 0; // Check if the row index is odd

              Color statusColor;
              switch (dorm.status) {
                case 'เปิดให้ใช้งาน':
                  statusColor = Colors.green;
                  break;
                case 'ปิดปรับปรุง':
                  statusColor = Colors.orange;
                  break;
                case 'ถูกระงับ':
                  statusColor = Colors.red;
                  break;
                default:
                  statusColor = Colors.black; // Default color
              }

              return DataRow(
                key: ValueKey(dorm.id), // Unique key for each row
                color: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFBBDEFB); // Slightly darker blue when selected
                    }
                    return isOddRow ? Colors.grey.withOpacity(0.05) : Colors.white; // Alternating color
                  },
                ),
                cells: <DataCell>[
                  DataCell(Text(dorm.id)),
                  DataCell(Text(dorm.dormName)),
                  DataCell(Text(dorm.ownerName)),
                  DataCell(Text(dorm.ownerPhone)),
                  DataCell(Text(dorm.registeredDate)),
                  DataCell(Text(dorm.totalFloors)),
                  DataCell(Text(dorm.totalRooms)),
                  DataCell(
                    Text(
                      dorm.status,
                      style: TextStyle(
                        color: statusColor,
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
