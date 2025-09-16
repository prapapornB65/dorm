import 'package:flutter/material.dart';

void handleSlipOkErrorCode({
  required int code,
  String? message,
  required BuildContext context,
  required void Function({required bool success, required String message})
      showResultDialog,
  required bool mounted,
}) {
  if (code == 0) {
    // ไม่มี error ไม่ต้องแสดงอะไรเลย
    return;
  }
  String userMessage;

  switch (code) {
    case 1000:
      userMessage =
          "กรุณาใส่ข้อมูล QR Code ให้ครบใน field data, files หรือ url";
      break;
    case 1001:
      userMessage = "ไม่พบข้อมูลสาขา กรุณาตรวจสอบไอดีสาขา";
      break;
    case 1002:
      userMessage = "Authorization Header ไม่ถูกต้อง";
      break;
    case 1003:
      userMessage = "Package ของคุณหมดอายุแล้ว";
      break;
    case 1004:
      userMessage =
          "Package ของคุณใช้เกินโควต้ามาแล้ว 400 บาท กรุณาต่อสมาชิกแพ็กเกจ";
      break;
    case 1005:
      userMessage =
          "ไฟล์ไม่ใช่ไฟล์ภาพ กรุณาอัพโหลดไฟล์เฉพาะนามสกุล .jpg .jpeg .png .jfif หรือ .webp";
      break;
    case 1006:
      userMessage = "รูปภาพไม่ถูกต้อง";
      break;
    case 1007:
      userMessage = "รูปภาพไม่มี QR Code";
      break;
    case 1008:
      userMessage = "QR ดังกล่าวไม่ใช่ QR สำหรับการตรวจสอบการชำระเงิน";
      break;
    case 1009:
      userMessage =
          "ขออภัยในความไม่สะดวก ขณะนี้ข้อมูลธนาคารเกิดขัดข้องชั่วคราว โปรดตรวจใหม่อีกครั้งใน 15 นาทีถัดไป (ไม่เสียโควต้าสลิป)";
      break;
    case 1010:
      userMessage =
          "เนื่องจากเป็นสลิปจากธนาคาร กรุณารอการตรวจสอบสลิปหลังการโอนประมาณ {จำนวนนาที} นาที";
      break;
    case 1011:
      userMessage = "QR Code หมดอายุ หรือ ไม่มีรายการอยู่จริง";
      break;
    case 1012:
      userMessage = "สลิปซ้ำ สลิปนี้เคยส่งเข้ามาในระบบเมื่อ $message";
      break;
    case 1013:
      userMessage = "ยอดที่ส่งมาไม่ตรงกับยอดสลิป";
      break;
    case 1014:
      userMessage =
          "บัญชีผู้รับไม่ตรงกับบัญชีหลักของร้าน กรุณาตรวจสอบบัญชีเจ้าของหอพัก";
      break;
    default:
      userMessage = "เกิดข้อผิดพลาดไม่ทราบสาเหตุ (Code: $code)";
  }

  if (!mounted) return;
  showResultDialog(success: false, message: userMessage);
}
