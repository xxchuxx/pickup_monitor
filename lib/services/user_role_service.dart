import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRoleService {
  const UserRoleService._();

  static Future<String?> currentUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return doc.data()?['role']?.toString();
  }

  static Future<bool> isCurrentUserAdmin() async {
    return await currentUserRole() == 'admin';
  }
}
