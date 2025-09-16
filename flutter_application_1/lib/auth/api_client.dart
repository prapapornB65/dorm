// api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/config/api_config.dart';

class ApiClient {
  final http.Client _client = http.Client();

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final base = {'Content-Type': 'application/json'};
    if (!auth) return base;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    return {
      ...base,
      'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.get(Uri.parse('$apiBaseUrl$path'), headers: headers);
  }

  Future<http.Response> post(String path, {Object? body, bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _client.post(Uri.parse('$apiBaseUrl$path'), headers: headers, body: jsonEncode(body));
  }
}
