import 'package:flutter/material.dart';
import 'dart:math'; // Moved import to the top as it's required by _MockLineChartPainter
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:flutter_application_1/auth/login_page.dart'; // Import LoginPage

// You might need to import other screens here if you want to navigate
import 'package:flutter_application_1/admin/home/ownerlist.dart'; // Import for the OwnerListScreen
import 'package:flutter_application_1/admin/home/dormlist.dart'; // <<<--- เพิ่ม import สำหรับ DormListScreen
import 'package:flutter_application_1/admin/home/noti.dart'; // <<<--- เพิ่ม import สำหรับ NotiScreen
import 'package:flutter_application_1/admin/home/security_screen.dart'; // Import the new SecurityScreen

class CentralAdminDashboardScreen extends StatefulWidget {
  final int adminId;

  const CentralAdminDashboardScreen({Key? key, required this.adminId})
      : super(key: key);

  @override
  State<CentralAdminDashboardScreen> createState() =>
      _CentralAdminDashboardScreenState();
}

class _CentralAdminDashboardScreenState
    extends State<CentralAdminDashboardScreen> {
  String _activeMenuItem = 'dashboard'; // State to manage active menu item

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFE3F2FD), // Light blue background for the whole screen
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Main content area
          Expanded(
            child: _buildMainContent(context),
          ),
        ],
      ),
    );
  }

  // Helper method to build the sidebar
  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: const Color(0xFFBBDEFB), // Slightly darker blue for sidebar
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo and title section (มุมซ้ายบนสำหรับโลโก้)
          Padding(
            padding: const EdgeInsets.only(bottom: 40, left: 8, top: 16),
            child: Row(
              children: [
                // Replaced Icon with Image.asset for the logo
                Container(
                  width: 48, // Adjust size as needed
                  height: 48, // Adjust size as needed
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF64B5F6), // Blue for the icon background
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    // ClipRRect to apply border radius to the image
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/Opor.png', // Path to your logo image
                      fit: BoxFit.cover, // Adjust fit as needed
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback in case image fails to load
                        return const Icon(
                          Icons.error,
                          color: Colors.white,
                          size: 32,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'ผู้ดูแลระบบกลาง',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0), // Darker blue text
                  ),
                ),
              ],
            ),
          ),
          // Menu items
          _buildMenuItem(
            label: 'แดชบอร์ด',
            icon: Icons.dashboard,
            menuKey: 'dashboard',
          ),
          _buildMenuItem(
            label: 'เจ้าของหอพัก',
            icon: Icons.person_outline,
            menuKey: 'owners',
          ),
          _buildMenuItem(
            label: 'รายการหอพักทั้งหมด',
            icon: Icons.apartment_outlined,
            menuKey: 'allDorms', // This is the new menu item for dorms
          ),
          _buildMenuItem(
            label: 'การแจ้งเตือนระบบ',
            icon: Icons.notifications_none,
            menuKey: 'notifications', // Updated menuKey for notifications
          ),
          _buildMenuItem(
            label: 'ระบบและความปลอดภัย',
            icon: Icons.security_outlined,
            menuKey: 'security',
          ),
          _buildMenuItem(
            label: 'ตั้งค่าระบบ',
            icon: Icons.settings_outlined,
            menuKey: 'settings',
          ),
          const Spacer(), // Pushes logout to the bottom
          _buildMenuItem(
            label: 'ออกจากระบบ',
            icon: Icons.exit_to_app,
            menuKey: 'logout',
            isLogout: true, // Special styling for logout
          ),
        ],
      ),
    );
  }

  // Helper method to build each menu item in the sidebar
  Widget _buildMenuItem({
    required String label,
    required IconData icon,
    required String menuKey,
    bool isLogout = false,
  }) {
    final bool isActive = _activeMenuItem == menuKey;
    return GestureDetector(
      onTap: () async { // Make onTap async for signOut()
        setState(() {
          _activeMenuItem = menuKey;
        });
        // Add navigation logic here based on menuKey
        if (isLogout) {
          try {
            await FirebaseAuth.instance.signOut(); // Sign out from Firebase
            if (!mounted) return; // Check if widget is still mounted
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LoginPage()), // Navigate to LoginPage
            );
          } catch (e) {
            print('Error signing out: $e');
            // Optionally show a SnackBar or dialog for error
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('เกิดข้อผิดพลาดในการออกจากระบบ: $e')),
            );
          }
        } else if (menuKey == 'owners') {
          // Navigate to OwnerListScreen when "เจ้าของหอพัก" is clicked
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    const OwnerListScreen()), // OwnerListScreen
          );
        } else if (menuKey == 'allDorms') {
          // Navigate to DormListScreen when "รายการหอพักทั้งหมด" is clicked
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const DormListScreen()), // DormListScreen
          );
        } else if (menuKey == 'notifications') {
          // <<<--- เงื่อนไขสำหรับ "การแจ้งเตือนระบบ"
          // Navigate to NotificationListScreen
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    const NotificationListScreen()), // Go to noti.dart
          );
        } else if (menuKey == 'security') { // <<<--- เพิ่มเงื่อนไขสำหรับ "ระบบและความปลอดภัย"
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    const SecurityScreen()), // Navigate to SecurityScreen
          );
        } else {
          print('$label clicked');
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive
              ? (isLogout
                  ? const Color(0xFFFFCDD2)
                  : const Color(
                      0xFF90CAF9)) // Red for logout, light blue for others
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive
                  ? (isLogout
                      ? const Color(0xFFC62828)
                      : const Color(
                          0xFF1565C0)) // Dark red for logout, dark blue for others
                  : const Color(0xFF42A5F5), // Medium blue for inactive
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive
                    ? (isLogout
                        ? const Color(0xFFC62828)
                        : const Color(0xFF1565C0))
                    : const Color(0xFF42A5F5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build the main content area
  Widget _buildMainContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Removed the top bar Logout button as requested
          // Align(
          //   alignment: Alignment.topRight,
          //   child: ElevatedButton(
          //     onPressed: () {
          //       // Handle logout
          //       print('Logout button pressed');
          //     },
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: const Color(0xFFEF5350), // Red button
          //       foregroundColor: Colors.white, // White text
          //       padding:
          //           const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(25),
          //       ),
          //       elevation: 5,
          //     ),
          //     child: const Text(
          //       'ออกจากระบบ',
          //       style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          //     ),
          //   ),
          // ),
          const SizedBox(height: 32), // Keep some spacing if needed

          // Summary Cards
          Wrap(
            spacing: 24, // Horizontal spacing
            runSpacing: 24, // Vertical spacing
            children: [
              _buildSummaryCard(value: '20', label: 'เจ้าของหอพักทั้งหมด'),
              _buildSummaryCard(value: '120', label: 'จำนวนผู้ใช้แพลตฟอร์ม'),
              _buildSummaryCard(value: '60,000', label: 'รายได้/เดือน'),
              _buildSummaryCard(value: '15', label: 'จำนวนผู้ใช้ใหม่'),
            ],
          ),
          const SizedBox(height: 48),

          // Graphs Section
          LayoutBuilder(
            builder: (context, constraints) {
              // Adjust layout based on screen width
              if (constraints.maxWidth > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 2,
                        child: _buildMonthlyIncomeGraph()), // 2/3 width
                    const SizedBox(width: 24),
                    Expanded(
                        flex: 1,
                        child: Column(
                          // 1/3 width
                          children: [
                            _buildNewUsersGraph(),
                            const SizedBox(height: 24),
                            _buildPlatformUsersGraph(),
                          ],
                        )),
                  ],
                );
              } else {
                // Stack graphs on smaller screens
                return Column(
                  children: [
                    _buildMonthlyIncomeGraph(),
                    const SizedBox(height: 24),
                    _buildNewUsersGraph(),
                    const SizedBox(height: 24),
                    _buildPlatformUsersGraph(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // Helper method to build a summary card
  Widget _buildSummaryCard({required String value, required String label}) {
    return Container(
      width: 220, // Fixed width for consistency
      height: 120, // Fixed height
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4), // changes position of shadow
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0), // Dark blue for value
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build the monthly income graph placeholder
  Widget _buildMonthlyIncomeGraph() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          const Text(
            'กราฟรายได้/เดือน',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 20),
          // Placeholder for the bar chart
          SizedBox(
            height: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Mock data for bars (adjust height for visual representation)
                _buildBar('ม.ค.', 0.5), // Example height: 50% of max
                _buildBar('ก.พ.', 0.8),
                _buildBar('มี.ค.', 0.6),
                _buildBar('เม.ย.', 0.4),
                _buildBar('พ.ค.', 0.7),
                _buildBar('มิ.ย.', 0.5),
                _buildBar('ก.ค.', 0.8),
                _buildBar('ส.ค.', 0.6),
                _buildBar('ก.ย.', 0.4),
                _buildBar('ต.ค.', 0.7),
                _buildBar('พ.ย.', 0.5),
                _buildBar('ธ.ค.', 0.3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build a single bar in the bar chart
  Widget _buildBar(String month, double heightFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            width: 25,
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5), // Blue color for bars
              borderRadius: BorderRadius.circular(5),
            ),
            height: heightFactor * 200, // Max height is 200, scale accordingly
          ),
        ),
        const SizedBox(height: 8),
        Text(
          month,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  // Helper method to build the new users graph placeholder
  Widget _buildNewUsersGraph() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          const Text(
            'กราฟจำนวนผู้ใช้ใหม่เดือนนี้',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _MockLineChartPainter(
                // Mock data for the line chart
                points: const [
                  Offset(0.1, 0.9),
                  Offset(0.2, 0.7),
                  Offset(0.3, 0.8),
                  Offset(0.4, 0.6),
                  Offset(0.5, 0.75),
                  Offset(0.6, 0.55),
                  Offset(0.7, 0.65),
                  Offset(0.8, 0.5),
                  Offset(0.9, 0.4)
                ],
                lineColor: const Color(0xFF64B5F6), // Blue line
                gradientColors: const [
                  Color(0xFFE3F2FD), // Light blue for gradient
                  Colors.white,
                ],
                showArrow: true, // Show an upward arrow for growth
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build the platform users graph placeholder
  Widget _buildPlatformUsersGraph() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          const Text(
            'กราฟจำนวนผู้ใช้แพลตฟอร์มวันนี้',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _MockLineChartPainter(
                // Mock data for the line chart
                points: const [
                  Offset(0.1, 0.7),
                  Offset(0.2, 0.6),
                  Offset(0.3, 0.5),
                  Offset(0.4, 0.4),
                  Offset(0.5, 0.5),
                  Offset(0.6, 0.6),
                  Offset(0.7, 0.7),
                  Offset(0.8, 0.8),
                  Offset(0.9, 0.7)
                ],
                lineColor: const Color(0xFFFF8A65), // Orange line
                gradientColors: const [
                  Color(0xFFFFF3E0), // Light orange for gradient
                  Colors.white,
                ],
                showArrow: false, // No arrow for this graph
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// CustomPainter for drawing mock line charts
class _MockLineChartPainter extends CustomPainter {
  final List<Offset> points;
  final Color lineColor;
  final List<Color> gradientColors;
  final bool showArrow;

  _MockLineChartPainter({
    required this.points,
    required this.lineColor,
    required this.gradientColors,
    this.showArrow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path();
    final Path fillPath = Path();

    // Scale points to the canvas size
    final List<Offset> scaledPoints = points
        .map((p) => Offset(p.dx * size.width, (1 - p.dy) * size.height))
        .toList();

    if (scaledPoints.isEmpty) return;

    // Start drawing the line
    path.moveTo(scaledPoints[0].dx, scaledPoints[0].dy);
    fillPath.moveTo(scaledPoints[0].dx, scaledPoints[0].dy);

    for (int i = 1; i < scaledPoints.length; i++) {
      path.lineTo(scaledPoints[i].dx, scaledPoints[i].dy);
      fillPath.lineTo(scaledPoints[i].dx, scaledPoints[i].dy);
    }

    // Close the fill path to create a shape for the gradient
    fillPath.lineTo(scaledPoints.last.dx, size.height);
    fillPath.lineTo(scaledPoints.first.dx, size.height);
    fillPath.close();

    // Paint for the gradient fill
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gradientColors,
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Paint for the line
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw arrow if required (mock arrow)
    if (showArrow && scaledPoints.length >= 2) {
      final Offset lastPoint = scaledPoints.last;
      final Offset secondLastPoint = scaledPoints[scaledPoints.length - 2];

      final double angle = _getAngle(secondLastPoint, lastPoint);

      final Path arrowPath = Path();
      const double arrowSize = 10;

      // Rotate and translate arrow head
      arrowPath.moveTo(lastPoint.dx, lastPoint.dy);
      arrowPath.lineTo(
        lastPoint.dx - arrowSize * (0.8 * cos(angle) - 0.5 * sin(angle)),
        lastPoint.dy - arrowSize * (0.8 * sin(angle) + 0.5 * cos(angle)),
      );
      arrowPath.lineTo(
        lastPoint.dx - arrowSize * (0.8 * cos(angle) + 0.5 * sin(angle)),
        lastPoint.dy - arrowSize * (0.8 * sin(angle) - 0.5 * cos(angle)),
      );
      arrowPath.close();

      final Paint arrowPaint = Paint()
        ..color = const Color(0xFFFF8A65) // Orange-red for arrow
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MockLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gradientColors != gradientColors ||
        oldDelegate.showArrow != showArrow;
  }

  // Helper to calculate angle for arrow (simplified)
  double _getAngle(Offset p1, Offset p2) {
    return atan2(p2.dy - p1.dy, p2.dx - p1.dx);
  }
}
