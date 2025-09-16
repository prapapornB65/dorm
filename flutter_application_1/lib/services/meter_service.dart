import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/meter.dart';

class MeterService {
  final String baseUrl;
  final String? token; // JWT

  MeterService(this.baseUrl, {this.token});

  Map<String, String> get _h => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<List<Meter>> getTenantMeters() async {
    final r = await http.get(Uri.parse('$baseUrl/tenant/meters'), headers: _h);
    final data = json.decode(r.body);
    return (data['items'] as List).map((e) => Meter.fromJson(e)).toList();
  }

  Future<Map<String,dynamic>> getMeterStatus(int meterId) async {
    final r = await http.get(Uri.parse('$baseUrl/meters/$meterId/status'), headers: _h);
    return json.decode(r.body);
  }

  Future<List<Map<String,dynamic>>> getReadings(int meterId, {String? from, String? to}) async {
    final u = Uri.parse('$baseUrl/meters/$meterId/readings')
        .replace(queryParameters: {'from': from, 'to': to}..removeWhere((k,v)=>v==null));
    final r = await http.get(u, headers: _h);
    final data = json.decode(r.body);
    return (data['items'] as List).cast<Map<String,dynamic>>();
  }

  Future<void> togglePower(int meterId, bool on) async {
    final r = await http.post(
      Uri.parse('$baseUrl/meters/$meterId/commands'),
      headers: _h,
      body: json.encode({'code':'switch_1','value':on}), // หรือให้ backend map ตาม dp_map
    );
    if (r.statusCode >= 300) {
      throw Exception('toggle failed: ${r.body}');
    }
  }

  Future<Map<String, dynamic>> runBilling({int? buildingId, bool dryRun=false}) async {
    final body = {'dryRun': dryRun, if (buildingId != null) 'buildingId': buildingId};
    final r = await http.post(Uri.parse('$baseUrl/admin/meters/run-billing'), headers: _h, body: json.encode(body));
    return json.decode(r.body);
  }
}
