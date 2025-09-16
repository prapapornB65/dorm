import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/widgets/app_button.dart';
import 'package:flutter_application_1/color_app.dart';

class ContactOwnerPage extends StatefulWidget {
  final int tenantId;
  const ContactOwnerPage({super.key, required this.tenantId});

  @override
  State<ContactOwnerPage> createState() => _ContactOwnerPageState();
}

class _ContactOwnerPageState extends State<ContactOwnerPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('ติดต่อผู้ดูแล')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            NeumorphicCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('หัวข้อเรื่อง',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _subjectCtrl,
                    decoration: const InputDecoration(
                      hintText: 'เช่น แจ้งปัญหาน้ำ/ไฟ หรือสอบถามค่าใช้จ่าย',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'กรุณากรอกหัวข้อเรื่อง' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('เบอร์ติดต่อ (ถ้ามี)',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: '08x-xxx-xxxx'),
                  ),
                  const SizedBox(height: 16),
                  Text('รายละเอียด',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _messageCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'พิมพ์รายละเอียดปัญหา/คำถามของคุณ...',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'กรุณากรอกรายละเอียด' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'ส่งข้อความ',
              icon: Icons.send,
              onPressed: () {
                // ดีไซน์เท่านั้น — ตรงนี้ใส่ logic ส่งจริงของคุณได้
                if (_formKey.currentState?.validate() ?? false) {
                  FocusScope.of(context).unfocus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ส่งถึงผู้ดูแลแล้ว (tenantId: ${widget.tenantId})')),
                  );
                  // TODO: เรียก API ส่งข้อความของคุณ พร้อมแนบ widget.tenantId
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
