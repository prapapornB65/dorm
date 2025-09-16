import 'package:flutter/foundation.dart';

@immutable
class RoomItem {
  final String roomNumber;
  final String buildingName;
  final String status;
  final String roomType;   // อาจว่างได้ถ้า API ไม่ส่ง
  final String price;      // เก็บเป็น string เพราะบาง API ส่งเป็น text/decimal
  final int capacity;
  final int size;
  final String? imageUrl;

  const RoomItem({
    required this.roomNumber,
    required this.buildingName,
    required this.status,
    required this.roomType,
    required this.price,
    required this.capacity,
    required this.size,
    this.imageUrl,
  });

  factory RoomItem.fromJson(Map<String, dynamic> j) => RoomItem(
        roomNumber: j['RoomNumber']?.toString() ?? '',
        buildingName: j['BuildingName']?.toString() ?? '-',
        status: j['Status']?.toString() ?? '-',
        roomType: (j['RoomType'] ?? j['TypeName'])?.toString() ?? '',
        price: (j['Price'] ?? j['PricePerMonth'])?.toString() ?? '0',
        capacity: _toInt(j['Capacity']),
        size: _toInt(j['Size']),
        imageUrl: j['FirstImageURL']?.toString() ?? j['ImageURL']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'RoomNumber': roomNumber,
        'BuildingName': buildingName,
        'Status': status,
        'RoomType': roomType,
        'Price': price,
        'Capacity': capacity,
        'Size': size,
        'ImageURL': imageUrl,
      };

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  RoomItem copyWith({
    String? roomNumber,
    String? buildingName,
    String? status,
    String? roomType,
    String? price,
    int? capacity,
    int? size,
    String? imageUrl,
  }) =>
      RoomItem(
        roomNumber: roomNumber ?? this.roomNumber,
        buildingName: buildingName ?? this.buildingName,
        status: status ?? this.status,
        roomType: roomType ?? this.roomType,
        price: price ?? this.price,
        capacity: capacity ?? this.capacity,
        size: size ?? this.size,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}
