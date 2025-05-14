import 'package:flutter/material.dart';
import 'main_navigation.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet App',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const MainNavigationPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
