import 'package:flutter/material.dart';
import 'package:fast_validator/fast_validator.dart'; // ✅ สำคัญ
import 'package:flutter_application_1/model/profile.dart';

class RegScreen extends StatefulWidget {
  const RegScreen({super.key});

  @override
  State<RegScreen> createState() => _RegScreenState();
}

class _RegScreenState extends State<RegScreen> {
  final _formKey = GlobalKey<FormState>();

  final usernameController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final roomController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    roomController.dispose();
    super.dispose();
  }

  void submitForm() {
    if (_formKey.currentState!.validate()) {
      final profile = Profile(
        username: usernameController.text.trim(),
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
        roomNumber: roomController.text.trim(),
      );

      print("✅ Profile created: ${profile.toJson()}");

      // ส่งข้อมูลไปเก็บต่อ เช่น Firebase หรือ local storage
      Navigator.pop(context); // กลับไป LoginScreen
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
                          "SIGN UP",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 15),

                      const Text("ชื่อผู้ใช้*"),
                      TextFormField(
                        controller: usernameController,
                        validator: RequiredValidator(errorText: "กรุณากรอกชื่อผู้ใช้"),
                      ),

                      const Text("ชื่อจริง*"),
                      TextFormField(
                        controller: firstNameController,
                        validator: RequiredValidator(errorText: "กรุณากรอกชื่อจริง"),
                      ),

                      const Text("นามสกุล*"),
                      TextFormField(
                        controller: lastNameController,
                        validator: RequiredValidator(errorText: "กรุณากรอกนามสกุล"),
                      ),

                      const Text("อีเมล"),
                      TextFormField(
                        controller: emailController,
                        validator: (value) {
                          if (value != null && value.isNotEmpty && !value.contains('@')) {
                            return 'อีเมลไม่ถูกต้อง';
                          }
                          return null;
                        },
                      ),

                      const Text("รหัสผ่าน*"),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) return "กรุณากรอกรหัสผ่าน";
                          if (value.length < 6) return "รหัสผ่านควรมีอย่างน้อย 6 ตัวอักษร";
                          return null;
                        },
                      ),

                      const Text("เลขห้อง"),
                      TextFormField(
                        controller: roomController,
                      ),

                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: submitForm,
                            child: const Text("SIGN UP"),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Back"),
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
