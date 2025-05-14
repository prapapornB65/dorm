import 'package:flutter/material.dart';
import 'wallet/top_up_page.dart';
import 'package:flutter_application_1/home/RoomOverviewPage.dart';


class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 1;

  final List<Widget> _pages = [
    const RoomOverviewPage(), // Home
    const TopUpPage(),                              // Wallet
    const Center(child: Text('🛠️ บริการ')),        // Service
    const Center(child: Text('👤 โปรไฟล์')),        // Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFFFBEAFF), // ชมพูอ่อน
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.black,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'wallet',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build),
            label: 'service',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'profile',
          ),
        ],
      ),
    );
  }
}
