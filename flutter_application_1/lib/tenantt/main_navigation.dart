import 'package:flutter/material.dart';
import '../tenantt/home/RoomOverviewPage.dart';
import '../tenantt/buy/wallet_page.dart';
import '../tenantt/service/service_quick_page.dart';
import '../tenantt/profile_page.dart';

class MainNavigation extends StatefulWidget {
  final int tenantId;

  const MainNavigation({super.key, required this.tenantId});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  // ✅ โทนสีใหม่
  final Color primaryColor = const Color(0xFF4C7C5A); // เขียวทันสมัย
  final Color secondaryColor = const Color(0xFFF7D060); // เหลืองเน้น
  final Color unselectedColor = const Color(0xFFB0BEC5); // เทาอ่อน
  final Color bgColor = Colors.grey.shade100;

  @override
  void initState() {
    super.initState();
    _pages = [
      const RoomOverviewPage(),
      WalletPage(tenantId: widget.tenantId),
      ServiceQuickPage(tenantId: widget.tenantId),
      ProfilePage(tenantId: widget.tenantId),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          border: Border(
            top: BorderSide(color: primaryColor.withOpacity(0.1), width: 1),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: primaryColor,
            unselectedItemColor: unselectedColor,
            selectedFontSize: 13,
            unselectedFontSize: 12,
            iconSize: 24,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            onTap: _onItemTapped,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'หน้าหลัก',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet),
                label: 'กระเป๋า',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.build_outlined),
                activeIcon: Icon(Icons.build),
                label: 'บริการ',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'โปรไฟล์',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
