import 'package:flutter/material.dart';
import 'package:flutter_application_1/login/register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final roomController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    roomController.dispose();
    super.dispose();
  }

  void login() {
    if (_formKey.currentState!.validate()) {
      final username = usernameController.text.trim();
      final password = passwordController.text.trim();
      final room = roomController.text.trim();

      print("✅ Login with: $username / $password / Room: $room");
      // TODO: ทำระบบ login ที่นี่ (Firebase หรือเช็คภายใน)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 60),
              Image.asset("assets/images/Opor.png", width: 100, height: 100),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          "LOGIN",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text("ชื่อผู้ใช้"),
                      TextFormField(
                        controller: usernameController,
                        validator: (value) => value == null || value.isEmpty
                            ? "กรุณากรอกชื่อผู้ใช้"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      const Text("รหัสผ่าน"),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        validator: (value) => value == null || value.isEmpty
                            ? "กรุณากรอกรหัสผ่าน"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      const Text("เลขห้อง"),
                      TextFormField(
                        controller: roomController,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // TODO: forgot password
                          },
                          child: const Text(
                            "ลืมรหัสผ่าน?",
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                            ),
                            onPressed: login,
                            child: const Text("SIGN IN"),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegScreen()),
                              );
                            },
                            child: const Text("SIGN UP"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
