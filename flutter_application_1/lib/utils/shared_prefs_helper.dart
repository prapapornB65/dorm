import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsHelper {
  static Future<void> saveTenantId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tenantId', id);
  }

  static Future<int?> getTenantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('tenantId');
  }

  static Future<void> saveOwnerId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ownerId', id);
  }

  static Future<int?> getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('ownerId');
  }

  static Future<void> saveTenantName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tenantName', name);
  }

  static Future<void> saveRoomNumber(String roomNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('roomNumber', roomNumber);
  }

  static Future<String?> getRoomNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('roomNumber');
  }

  static Future<String?> getTenantName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tenantName');
  }

  static Future<void> saveSavedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savedEmail', email);
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('savedEmail');
  }
}
