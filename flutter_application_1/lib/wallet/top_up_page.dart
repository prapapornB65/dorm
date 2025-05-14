import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../wallet/slipok_api.dart';
import '../wallet/save_to_server.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  Uint8List? _pickedImageBytes;
  String? _fileName;

  Future<void> _pickSlipFile() async {
    var status = await Permission.photos.request();

    if (status.isGranted) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null) {
        final file = result.files.single;

        if (file.bytes != null) {
          setState(() {
            _pickedImageBytes = file.bytes;
            _fileName = file.name;
          });
          debugPrint(
              "✅ ได้ bytes จาก memory: ${file.name} (${file.bytes!.lengthInBytes} bytes)");
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          setState(() {
            _pickedImageBytes = bytes;
            _fileName = file.name;
          });
          debugPrint(
              "✅ ได้ bytes จาก path: ${file.name} (${bytes.lengthInBytes} bytes)");
        } else {
          debugPrint("❌ ไม่พบข้อมูลภาพทั้งจาก memory และ path");
          _showResultDialog(success: false, message: "ไม่สามารถอ่านไฟล์ภาพได้");
        }
      }
    } else {
      _showResultDialog(
          success: false, message: "⚠️ กรุณาอนุญาตเข้าถึงไฟล์ก่อนอัปโหลด");
    }
  }

  void _submitSlip() async {
    if (_pickedImageBytes != null && _fileName != null) {
      debugPrint("🚀 เริ่มอัปโหลด...");

      try {
        final result = await uploadToSlipOK(_pickedImageBytes!, _fileName!);
        debugPrint("📥 ได้ผลลัพธ์จาก SlipOK: $result");

        if (result != null && result['error'] != true) {
          final data = result;
          String bank = data['sendingBank'].toString();
          String amount = data['amount'].toString();
          String date = data['transDate'].toString();
          String time = data['transTime'].toString();
          String datetime = "$date $time";

          await saveSlipToServer(
            bank: bank,
            amount: amount,
            datetime: datetime,
            filename: _fileName!,
          );

          if (!mounted) return;
          _showResultDialog(
            success: true,
            message: "✅ ตรวจสอบสลิปสำเร็จ\n\n"
                "ธนาคาร: $bank\n"
                "ยอด: $amount บาท\n"
                "เวลา: $datetime",
          );
        } else {
          if (!mounted) return;
          final message = result?['message'] ?? "❌ ไม่สามารถตรวจสอบสลิปได้";
          _showResultDialog(success: false, message: message);
        }
      } catch (e) {
        debugPrint("🚨 เกิดข้อผิดพลาด: $e");
        if (!mounted) return;
        _showResultDialog(success: false, message: "🚨 เกิดข้อผิดพลาด:\n$e");
      }
    } else {
      debugPrint("⚠️ ยังไม่ได้เลือกรูปสลิป");
      _showResultDialog(success: false, message: "กรุณาเลือกไฟล์สลิปของคุณ");
    }
  }

  void _showResultDialog({required bool success, required String message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Icon(
          success ? Icons.check_circle : Icons.cancel,
          color: success ? Colors.green : Colors.red,
          size: 60,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            child: Text("OK",
                style: TextStyle(color: success ? Colors.green : Colors.red)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // หัวข้อ
              const Text("เติมเงิน",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),

              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("ช่องทางชำระเงิน",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),

              // QR พร้อมเพย์ กล่องมีเงา + พื้นหลัง
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7FF),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset('assets/qrcode_sample.jpg', height: 200),
                    const SizedBox(height: 12),
                    const Text("ชื่อบัญชี : นางสาว ประภาภรณ์ บุญนิยม",
                        style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("ยืนยันการชำระเงิน",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),

              // ปุ่มอัปโหลด
              ElevatedButton.icon(
                onPressed: _pickSlipFile,
                icon: const Icon(Icons.upload_file, color: Colors.purple),
                label: Text(
                  _fileName ?? 'อัปโหลดสลิป',
                  style: TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFFF3EFFF), // สีพื้นหลังปุ่ม
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.purple),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              if (_pickedImageBytes != null)
                Column(
                  children: [
                    const Text("แสดงตัวอย่างสลิป:"),
                    const SizedBox(height: 8),
                    Image.memory(_pickedImageBytes!, height: 200),
                    const SizedBox(height: 10),
                    Text("ไฟล์: $_fileName"),
                  ],
                ),

              // ปุ่มส่ง
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 50, vertical: 14),
                ),
                onPressed: _submitSlip,
                child: const Text("ส่ง",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
