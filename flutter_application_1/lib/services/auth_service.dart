import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static Future<String?> getUserRole(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      return doc.data()?['role']; // ต้องมี field 'role': 'tenant' / 'owner' / 'admin'
    }
    return null;
  }
}
