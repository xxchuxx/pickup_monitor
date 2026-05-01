import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuditLogService {
  const AuditLogService._();

  static Future<void> record({
    required String action,
    required String targetType,
    String? targetId,
    Map<String, dynamic> details = const {},
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final payload = <String, dynamic>{
      'action': action,
      'targetType': targetType,
      'actorId': user?.uid,
      'actorEmail': user?.email,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (targetId != null) {
      payload['targetId'] = targetId;
    }

    try {
      await FirebaseFirestore.instance.collection('auditLogs').add(payload);
    } catch (_) {
      // Audit logging is best effort so it never blocks the user workflow.
    }
  }
}
