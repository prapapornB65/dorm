import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/color_app.dart';
import 'package:flutter_application_1/config/api_config.dart' show apiBaseUrl;

// Helper functions ระดับ global
double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^\d.-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
  return 0.0;
}

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  try {
    if (v is DateTime) return v;
    if (v is String) {
      // ลอง parse format ต่างๆ
      final formats = [
        v, // format เดิม
        v.replaceAll('T', ' ').replaceAll('Z', ''),
        v.replaceAll('T', ' '),
      ];
      
      for (final format in formats) {
        final parsed = DateTime.tryParse(format);
        if (parsed != null) return parsed;
      }
      
      // ลอง parse timestamp (milliseconds)
      final timestamp = int.tryParse(v);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

String _formatDisplayTime(DateTime? dt) {
  if (dt == null) return '-';
  
  final now = DateTime.now();
  final difference = now.difference(dt);
  
  if (difference.inSeconds < 60) return 'เมื่อสักครู่';
  if (difference.inMinutes < 60) return '${difference.inMinutes} นาทีที่แล้ว';
  if (difference.inHours < 24) return '${difference.inHours} ชั่วโมงที่แล้ว';
  if (difference.inDays < 7) return '${difference.inDays} วันที่แล้ว';
  
  return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

class OwnerMetersPage extends StatefulWidget {
  final int buildingId;
  final String? buildingName;
  const OwnerMetersPage({
    super.key, 
    required this.buildingId, 
    this.buildingName
  });

  @override
  State<OwnerMetersPage> createState() => _OwnerMetersPageState();
}

class _OwnerMetersPageState extends State<OwnerMetersPage> {
  bool _loading = true;
  String? _error;
  bool _isRefreshing = false;

  final _searchCtl = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  Map<String, _RoomMeters> _byRoom = {};
  List<_RoomMeters> _filtered = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _searchCtl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _initializeData() async {
    await _fetch();
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ----------------------- DATA FETCHING -----------------------
  Future<void> _fetch() async {
    if (_isRefreshing) return;
    
    _isRefreshing = true;
    if (mounted) {
      setState(() {
        if (!_loading) _loading = true;
        _error = null;
      });
    }

    try {
      final headers = await _authHeaders();
      
      // ลองใช้ endpoint หลัก
      final endpoints = [
        Uri.parse('$apiBaseUrl/api/owner/building/${widget.buildingId}/meters'),
        Uri.parse('$apiBaseUrl/api//owner/owner-electric/meters?buildingId=${widget.buildingId}'),
      ];

      http.Response? successfulResponse;
      
      for (final endpoint in endpoints) {
        try {
          final response = await http.get(endpoint, headers: headers)
              .timeout(const Duration(seconds: 15));
          
          if (response.statusCode == 200) {
            successfulResponse = response;
            break;
          }
        } on TimeoutException {
          continue; // ลอง endpoint ต่อไป
        } catch (e) {
          continue; // ลอง endpoint ต่อไป
        }
      }

      if (successfulResponse == null) {
        throw 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้';
      }

      final normalizedData = _normalizeList(successfulResponse.body);
      
      if (normalizedData.isEmpty) {
        throw 'ไม่พบข้อมูลมิเตอร์สำหรับตึกนี้';
      }

      if (mounted) {
        setState(() {
          _all = normalizedData;
          _groupByRoom();
          _applyFilter();
          _loading = false;
          _isRefreshing = false;
        });
      }

    } on TimeoutException {
      _handleError('การเชื่อมต่อใช้เวลานานเกินไป');
    } catch (e) {
      _handleError('เกิดข้อผิดพลาด: $e');
    }
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() {
        _error = message;
        _loading = false;
        _isRefreshing = false;
      });
    }
  }

  List<Map<String, dynamic>> _normalizeList(String body) {
    try {
      final jsonData = json.decode(body);
      final List<dynamic> rawList;
      
      if (jsonData is List) {
        rawList = jsonData;
      } else if (jsonData is Map) {
        rawList = jsonData['data'] ?? jsonData['items'] ?? [];
      } else {
        return [];
      }

      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        
        final meterId = map['MeterID'] ?? map['meterId'] ?? map['id'];
        final deviceId = map['DeviceID'] ?? map['deviceId'] ?? map['tuyaDeviceId'] ?? map['device_id'];
        final room = map['RoomNumber'] ?? map['roomNumber'] ?? map['room'];
        final typeStr = (map['Type'] ?? map['type'] ?? '').toString().toLowerCase();
        final label = map['Label'] ?? map['label'] ?? map['name'];
        final relayRaw = map['relay_on'] ?? map['RelayOn'];
        final energy = map['energy_kwh'] ?? map['EnergyKwh'] ?? map['kwh'];
        final water = map['water_m3'] ?? map['WaterM3'] ?? map['m3'];
        final updatedAt = map['UpdatedAt'] ?? map['updated_at'] ?? map['At'] ?? map['at'];
        final lastRead = map['last_read_at'] ?? map['lastReadAt'];
        final active = map['Active'] ?? map['active'];
        final isCut = map['is_cut'];

        // กำหนดประเภท
        final type = typeStr.isEmpty 
            ? (water != null ? 'water' : 'electric') 
            : typeStr;

        final lastUpdate = _parseDateTime(updatedAt ?? lastRead);
        final isOnline = lastUpdate != null && 
            DateTime.now().difference(lastUpdate).inMinutes <= 15;

        return {
          'meterId': meterId?.toString(),
          'deviceId': deviceId?.toString(),
          'roomNumber': room?.toString(),
          'type': type,
          'label': label?.toString() ?? '',
          'relay_on': relayRaw is bool ? relayRaw : null,
          'kwh': _asDouble(energy),
          'm3': _asDouble(water),
          'updatedAt': updatedAt?.toString(),
          'lastUpdate': lastUpdate,
          'online': isOnline,
          'active': active is bool ? active : true,
          'is_cut': isCut is bool ? isCut : null,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error normalizing list: $e');
      return [];
    }
  }

  void _groupByRoom() {
    final roomMap = <String, _RoomMeters>{};
    
    for (final meter in _all) {
      final roomNumber = (meter['roomNumber'] ?? '').toString();
      if (roomNumber.isEmpty) continue;
      
      roomMap.putIfAbsent(roomNumber, () => _RoomMeters(roomNumber: roomNumber));
      
      final roomData = roomMap[roomNumber]!;
      if ((meter['type'] ?? 'electric') == 'electric') {
        roomData.electric = meter;
      } else {
        roomData.water = meter;
      }
    }
    
    // เรียงลำดับห้อง
    final sortedEntries = roomMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    _byRoom = Map.fromEntries(sortedEntries);
  }

  void _applyFilter() {
    final query = _searchCtl.text.trim().toLowerCase();
    final allRooms = _byRoom.values.toList();
    
    if (query.isEmpty) {
      _filtered = allRooms;
    } else {
      _filtered = allRooms.where((room) {
        final searchTerms = [
          room.roomNumber,
          room.electric?['deviceId'],
          room.water?['deviceId'],
          room.electric?['label'],
          room.water?['label'],
        ].where((term) => term != null && term.isNotEmpty);
        
        final searchText = searchTerms.join(' ').toLowerCase();
        return searchText.contains(query);
      }).toList();
    }
    
    if (mounted) setState(() {});
  }

  // ----------------------- ACTIONS -----------------------
  Future<void> _pullNow(String roomNumber, {required bool forElectric}) async {
    if (_isRefreshing) return;
    
    try {
      final url = Uri.parse(
          '$apiBaseUrl/api/owner/building/${widget.buildingId}/tuya/pull-electric');
      
      final response = await http
          .post(
            url,
            headers: await _authHeaders(),
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กำลังอัพเดทข้อมูล...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          
          // รอสักครู่แล้วโหลดข้อมูลใหม่
          await Future.delayed(const Duration(seconds: 3));
          await _fetch();
        }
      } else {
        throw 'เซิร์ฟเวอร์ตอบกลับด้วยสถานะ: ${response.statusCode}';
      }
    } on TimeoutException {
      _showSnackBar('การดึงข้อมูลใช้เวลานานเกินไป', Colors.orange);
    } catch (e) {
      _showSnackBar('ดึงข้อมูลไม่สำเร็จ: $e', Colors.red);
    }
  }

  Future<void> _toggleRelay(String roomNumber, bool on) async {
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/owner/rooms/$roomNumber/relay'),
            headers: await _authHeaders(),
            body: json.encode({'on': on}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnackBar(on ? 'เปิดรีเลย์แล้ว' : 'ปิดรีเลย์แล้ว', Colors.green);
        await _fetch();
      } else {
        throw 'ไม่สามารถสั่งการรีเลย์ได้ (${response.statusCode})';
      }
    } on TimeoutException {
      _showSnackBar('การสั่งการใช้เวลานานเกินไป', Colors.orange);
    } catch (e) {
      _showSnackBar('สั่งการรีเลย์ไม่สำเร็จ: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ----------------------- UI -----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F6),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('กำลังโหลดข้อมูลมิเตอร์...'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetch,
                color: AppColors.primary,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _Header(
                            total: _byRoom.length, 
                            onRefresh: _fetch,
                            buildingName: widget.buildingName,
                          ),
                          const SizedBox(height: 12),
                          _SearchBox(
                            controller: _searchCtl,
                            onClear: () {
                              _searchCtl.clear();
                              _applyFilter();
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_error != null)
                            _ErrorBanner(error: _error!, onRetry: _fetch),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                    
                    if (_filtered.isEmpty)
                      SliverFillRemaining(
                        child: _buildEmptyState(),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final room = _filtered[index];
                            return _RoomCard(
                              data: room,
                              onPullElectric: () => 
                                  _pullNow(room.roomNumber, forElectric: true),
                              onPullWater: () => 
                                  _pullNow(room.roomNumber, forElectric: false),
                              onToggleRelay: (on) => 
                                  _toggleRelay(room.roomNumber, on),
                            );
                          },
                          childCount: _filtered.length,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchCtl.text.isEmpty ? 'ไม่พบมิเตอร์' : 'ไม่พบผลการค้นหา',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchCtl.text.isEmpty 
                  ? 'ยังไม่มีมิเตอร์ที่ผูกกับห้องในตึกนี้'
                  : 'ลองค้นหาด้วยคำอื่นหรือล้างการค้นหา',
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _searchCtl.text.isEmpty ? _fetch : () {
                _searchCtl.clear();
                _applyFilter();
              },
              icon: Icon(_searchCtl.text.isEmpty ? Icons.refresh : Icons.clear),
              label: Text(_searchCtl.text.isEmpty ? 'รีเฟรช' : 'ล้างการค้นหา'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------- MODELS & WIDGETS -----------------------
class _RoomMeters {
  final String roomNumber;
  Map<String, dynamic>? electric;
  Map<String, dynamic>? water;

  _RoomMeters({required this.roomNumber, this.electric, this.water});

  bool get hasElectric => electric != null;
  bool get hasWater => water != null;
}

class _Header extends StatelessWidget {
  final int total;
  final VoidCallback onRefresh;
  final String? buildingName;
  
  const _Header({
    required this.total, 
    required this.onRefresh,
    this.buildingName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000), 
            blurRadius: 16, 
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight, 
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.electric_meter_rounded, 
              color: AppColors.primaryDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'คลังมิเตอร์',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                if (buildingName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    buildingName!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$total ห้อง',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;
  const _SearchBox({required this.controller, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'ค้นหา (เลขห้อง / deviceId / ชื่อ)',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error, style: const TextStyle(color: Colors.red))),
          TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final _RoomMeters data;
  final VoidCallback onPullElectric;
  final VoidCallback onPullWater;
  final ValueChanged<bool> onToggleRelay;

  const _RoomCard({
    required this.data,
    required this.onPullElectric,
    required this.onPullWater,
    required this.onToggleRelay,
  });

  @override
  Widget build(BuildContext context) {
    final elec = data.electric;
    final water = data.water;
    final title = data.roomNumber;
    final relayOn = elec?['relay_on'] as bool?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.meeting_room_rounded,
                  color: AppColors.primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (elec != null)
          _SubMeterCard.electric(
            deviceId: elec['deviceId'],
            label: elec['label'],
            kwh: elec['kwh'],
            updatedAt: elec['updatedAt'],
            online: (elec['online'] == true),
            relayOn: relayOn,
            onPull: onPullElectric,
            onToggleRelay: onToggleRelay,
          ),

        if (elec != null && water != null) const SizedBox(height: 8),

        if (water != null)
          _SubMeterCard.water(
            deviceId: water['deviceId'],
            label: water['label'],
            m3: water['m3'],
            updatedAt: water['updatedAt'],
            online: (water['online'] == true),
            onPull: onPullWater,
          ),

        if (elec == null && water == null)
          const Text('ไม่มีมิเตอร์ผูกกับห้องนี้',
              style: TextStyle(color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _SubMeterCard extends StatelessWidget {
  final String type;
  final String? deviceId;
  final String? label;
  final num? kwh;
  final num? m3;
  final String? updatedAt;
  final bool online;
  final bool? relayOn;
  final VoidCallback onPull;
  final ValueChanged<bool>? onToggleRelay;

  const _SubMeterCard._({
    required this.type,
    required this.deviceId,
    required this.label,
    required this.updatedAt,
    required this.online,
    required this.onPull,
    this.kwh,
    this.m3,
    this.relayOn,
    this.onToggleRelay,
  });

  factory _SubMeterCard.electric({
    required String? deviceId,
    required String? label,
    required num? kwh,
    required String? updatedAt,
    required bool online,
    required bool? relayOn,
    required VoidCallback onPull,
    required ValueChanged<bool> onToggleRelay,
  }) {
    return _SubMeterCard._(
      type: 'electric',
      deviceId: deviceId,
      label: label,
      kwh: kwh,
      updatedAt: updatedAt,
      online: online,
      relayOn: relayOn,
      onPull: onPull,
      onToggleRelay: onToggleRelay,
    );
  }

  factory _SubMeterCard.water({
    required String? deviceId,
    required String? label,
    required num? m3,
    required String? updatedAt,
    required bool online,
    required VoidCallback onPull,
  }) {
    return _SubMeterCard._(
      type: 'water',
      deviceId: deviceId,
      label: label,
      m3: m3,
      updatedAt: updatedAt,
      online: online,
      onPull: onPull,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isElec = type == 'electric';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Icon(isElec ? Icons.bolt_rounded : Icons.opacity_rounded,
                size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isElec
                    ? 'ไฟฟ้า • ${deviceId ?? "-"}'
                    : 'น้ำ • ${deviceId ?? "-"}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusPill(online: online),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'ดึงค่าล่าสุด',
              onPressed: onPull,
              icon: const Icon(Icons.sync_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (label != null && label!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        Text(
          isElec
              ? 'หน่วยไฟ: ${((kwh ?? 0) as num).toStringAsFixed(2)} kWh'
              : 'ปริมาณน้ำ: ${((m3 ?? 0) as num).toStringAsFixed(3)} m³',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text('${updatedAt ?? '-'}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        if (isElec && relayOn != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: relayOn!
                  ? Colors.green.withOpacity(.10)
                  : Colors.red.withOpacity(.10),
              border: Border.all(color: relayOn! ? Colors.green : Colors.red),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(relayOn! ? Icons.power : Icons.power_off,
                  size: 16, color: relayOn! ? Colors.green : Colors.red),
              const SizedBox(width: 6),
              Text(relayOn! ? 'ต่อไฟอยู่' : 'ตัดไฟอยู่',
                  style: TextStyle(
                    color: relayOn! ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => onToggleRelay?.call(!relayOn!),
                child: Text(relayOn! ? 'ตัดไฟ' : 'ต่อไฟ'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool online;
  const _StatusPill({required this.online});

  @override
  Widget build(BuildContext context) {
    final c = online ? Colors.green : Colors.grey;
    final t = online ? 'ออนไลน์' : 'ออฟไลน์';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}