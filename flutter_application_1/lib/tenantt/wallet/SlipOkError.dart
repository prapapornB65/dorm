import 'package:flutter/material.dart';

DateTime? _parseServerDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  final i = int.tryParse(s);
  if (i != null && s.length >= 10) {
    // epoch millis
    return DateTime.fromMillisecondsSinceEpoch(i, isUtc: true).toLocal();
  }
  final dt = DateTime.tryParse(s);
  return dt?.toLocal();
}

String _fmtLocal(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// ถ้าเป็น ISO/epoch -> ฟอร์แมตเอง, ถ้าเป็นสตริงยาวที่มี GMT/\n -> ตัดให้เหลือบรรทัดเดียว
String _oneLinePretty(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '-';
  final dt = _parseServerDate(raw);
  if (dt != null) return _fmtLocal(dt);
  final cleaned = raw.replaceAll(RegExp(r'\s*GMT[^\n\r]*$'), '').trim();
  return cleaned.replaceAll('\n', ' ').replaceAll('\r', ' ');
}

/// แปลงรหัสธนาคารยอดฮิตเป็นชื่อ (เติมเพิ่มได้)
String _bankName(String? code) {
  const Map<String, String> bankNames = {
    '002': 'กรุงไทย',
    '004': 'กสิกรไทย',
    '006': 'กรุงเทพ',
    '011': 'ทหารไทยธนชาต',
    '014': 'ไทยพาณิชย์',
    '017': 'ซีไอเอ็มบี',
    '020': 'ออมสิน',
  };
  final c = (code ?? '').trim();
  return bankNames[c] ?? (c.isEmpty ? '-' : c);
}

/// สร้างข้อความสรุป "ผู้รับจากสลิป" (แบบย่อ ไม่ใส่โค้ดธนาคาร)
String _receiverSummary(Map<String, dynamic>? slipData) {
  final bankCode = (slipData?['receivingBank'] ?? '').toString();
  final bank = _bankName(bankCode);

  final recv = (slipData?['receiver'] as Map?) ?? const {};
  final name = (recv['displayName'] ?? recv['name'] ?? '-').toString();
  final acc  = ((recv['account'] as Map?)?['value'] ?? '').toString();
  final pType  = ((recv['proxy'] as Map?)?['type']  ?? '').toString();
  final pValue = ((recv['proxy'] as Map?)?['value'] ?? '').toString();

  final parts = <String>[
    'ชื่อ: $name',
    'ธนาคาร: ${bank.isEmpty ? '-' : bank}',
  ];
  if (acc.isNotEmpty) parts.add('เลขบัญชี: $acc');
  if (pType.isNotEmpty || pValue.isNotEmpty) {
    parts.add('Proxy: ${pType.isEmpty ? "-" : pType}${pValue.isEmpty ? "" : " ($pValue)"}');
  }
  return parts.join('\n');
}

/// โชว์ error จาก SlipOK แบบย่อ (ไม่มีการเปรียบเทียบ/expected)
void handleSlipOkErrorCode({
  required int code,
  String? message,

  Map<String, dynamic>? slipData, // ส่ง result['data'] มาได้ (ถ้ามี)
  required BuildContext context,
  required void Function({required bool success, required String message}) showResultDialog,
  required bool mounted,
}) {
  if (code == 0) return;

  String userMessage;

  switch (code) {
    case 1000:
      userMessage = "กรุณาใส่ข้อมูล QR Code ให้ครบ";
      break;
    case 1001:
      userMessage = "ไม่พบข้อมูลสาขา กรุณาตรวจสอบไอดีสาขา";
      break;
    case 1002:
      userMessage = "Authorization Header ไม่ถูกต้อง";
      break;
    case 1003:
      userMessage = "Package หมดอายุ";
      break;
    case 1004:
      userMessage = "ใช้เกินโควต้าที่กำหนด กรุณาต่อสมาชิกแพ็กเกจ";
      break;
    case 1005:
      userMessage = "ไฟล์ไม่ใช่รูปภาพ (.jpg .jpeg .png .jfif .webp)";
      break;
    case 1006:
      userMessage = "รูปภาพไม่ถูกต้อง";
      break;
    case 1007:
      userMessage = "รูปภาพไม่มี QR Code";
      break;
    case 1008:
      userMessage = "QR นี้ไม่ใช่สำหรับตรวจสอบการชำระเงิน";
      break;
    case 1009:
      userMessage = "ธนาคารขัดข้องชั่วคราว โปรดลองใหม่อีกครั้งใน ~15 นาที";
      break;
    case 1010:
      userMessage = "สลิปเพิ่งทำรายการ อาจต้องรอสักครู่ กรุณาลองใหม่ในไม่กี่นาที";
      break;
    case 1011:
      userMessage = "QR Code หมดอายุ หรือไม่มีรายการอยู่จริง";
      break;

    case 1012: {
      // duplicate slip
      final whenStr = _oneLinePretty(message);
      final cleaned = whenStr.replaceFirst(RegExp(r'^สลิปซ้ำ\s*[:\-]?\s*'), '');
      userMessage = 'สลิปซ้ำ: เคยบันทึกไว้แล้วเมื่อ $cleaned';
      break;
    }

    case 1013: {
      // amount mismatch (แบบย่อ ไม่โชว์ expected)
      final paid = (slipData?['paidLocalAmount'] ?? slipData?['amount'])?.toString() ?? '';
      final tsLocal = _oneLinePretty((slipData?['transTimestamp'] ?? '').toString());
      userMessage =
          'ยอดไม่ตรงกับสลิป\n'
          '• จากสลิป: ${paid.isEmpty ? '-' : paid} บาท (เวลา $tsLocal)\n'
          'กรุณาตรวจสอบยอดที่ต้องชำระอีกครั้ง';
      break;
    }

    case 1014: {
      // receiver mismatch (แบบย่อ ไม่เทียบ expected)
      final tsLocal = _oneLinePretty((slipData?['transTimestamp'] ?? '').toString());
      final recv = _receiverSummary(slipData);
      userMessage =
          'บัญชีผู้รับไม่ตรงกับ “บัญชีหลักของร้าน”\n'
          '— รายละเอียดจากสลิป (เวลา $tsLocal)\n$recv';
      break;
    }

    default:
      final detail = (message != null && message.trim().isNotEmpty)
          ? '\nรายละเอียด: ${_oneLinePretty(message)}'
          : '';
      userMessage = "เกิดข้อผิดพลาด (Code: $code)$detail";
  }

  if (!mounted) return;
  showResultDialog(success: false, message: userMessage);
}
