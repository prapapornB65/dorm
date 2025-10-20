import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // สำหรับ Clipboard
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/config/api_config.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/neumorphic_card.dart';
import 'package:flutter_application_1/color_app.dart';

class ContactOwnerPage extends StatefulWidget {
  final int? tenantId; // ⬅︎ เดิมเป็น int เปลี่ยนเป็น int?
  final String? roomNumber; // ⬅︎ เพิ่ม
  final String? buildingName; // ⬅︎ เพิ่ม
  

  const ContactOwnerPage({
    super.key,
    this.tenantId, // ⬅︎ เดิม required เปลี่ยนเป็น optional
    this.roomNumber, // ⬅︎ เพิ่ม
    this.buildingName, // ⬅︎ เพิ่ม
  });

  @override
  State<ContactOwnerPage> createState() => _ContactOwnerPageState();
}

class _ContactOwnerPageState extends State<ContactOwnerPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await http
        .get(Uri.parse('$apiBaseUrl/api/contact-owner/${widget.tenantId}'))
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception('โหลดข้อมูลไม่สำเร็จ (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('คัดลอก$labelแล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('ติดต่อเจ้าของหอพัก')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              ),
            );
          }

          final d = snap.data!;
          final ownerName = ((d['OwnerName'] ??
                  '${d['FirstName'] ?? ''} ${d['LastName'] ?? ''}')
              .toString()
              .trim());
          final phone = (d['Phone'] ?? '').toString();
          final email = (d['Email'] ?? '').toString();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              NeumorphicCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ข้อมูลติดต่อ',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ชื่อเจ้าของ (คัดลอกได้)
                    _InfoRow(
                      icon: Icons.person,
                      label: 'ชื่อเจ้าของ',
                      value: ownerName.isEmpty ? '—' : ownerName,
                    ),
                    const SizedBox(height: 12),

                    // เบอร์โทร (คัดลอกได้)
                    _CopyRow(
                      icon: Icons.phone,
                      label: 'เบอร์โทร',
                      value: phone.isEmpty ? '—' : phone,
                      enabled: phone.isNotEmpty,
                      onCopy: () => _copy('เบอร์โทร', phone),
                    ),
                    const SizedBox(height: 12),

                    // อีเมล (คัดลอกได้)
                    _CopyRow(
                      icon: Icons.email_outlined,
                      label: 'อีเมล',
                      value: email.isEmpty ? '—' : email,
                      enabled: email.isNotEmpty,
                      onCopy: () => _copy('อีเมล', email),
                    ),

                    if (ownerName.isEmpty && phone.isEmpty && email.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'ยังไม่มีข้อมูลการติดต่อ',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onCopy;

  const _CopyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: enabled ? onCopy : null,
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('คัดลอก'),
          style: TextButton.styleFrom(
            foregroundColor: enabled ? AppColors.primaryDark : Colors.grey,
          ),
        ),
      ],
    );
  }
}
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
