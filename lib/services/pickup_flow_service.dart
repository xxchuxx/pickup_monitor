import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'audit_log_service.dart';

class PickupFlowException implements Exception {
  final String message;

  const PickupFlowException(this.message);

  @override
  String toString() => message;
}

class PickupFlowService {
  const PickupFlowService._();

  static String todayKey([DateTime? date]) {
    return DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
  }

  static String pickupStatusId(String childId, [DateTime? date]) {
    return '${childId}_${todayKey(date)}';
  }

  static String qrUseId(String guardianId, [DateTime? date]) {
    return '${guardianId}_${todayKey(date)}';
  }

  static Future<void> assertCanRelease({
    required String childId,
    required String guardianId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final statusDoc = await firestore
        .collection('pickupStatus')
        .doc(pickupStatusId(childId))
        .get();
    if (statusDoc.exists && statusDoc.data()?['status'] == 'picked_up') {
      throw const PickupFlowException(
        'This child was already picked up today.',
      );
    }

    final qrUseDoc = await firestore
        .collection('qrUses')
        .doc(qrUseId(guardianId))
        .get();
    if (qrUseDoc.exists) {
      throw const PickupFlowException(
        'This QR code has already been used today.',
      );
    }
  }

  static Future<void> releaseChild({
    required String guardianId,
    required String guardianName,
    required String relation,
    required String childId,
    required String childName,
    required String parentId,
    String? section,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    final statusRef = firestore
        .collection('pickupStatus')
        .doc(pickupStatusId(childId));
    final qrUseRef = firestore.collection('qrUses').doc(qrUseId(guardianId));
    final logRef = firestore.collection('pickupLogs').doc();

    await firestore.runTransaction((transaction) async {
      final statusDoc = await transaction.get(statusRef);
      if (statusDoc.exists && statusDoc.data()?['status'] == 'picked_up') {
        throw const PickupFlowException(
          'This child was already picked up today.',
        );
      }

      final qrUseDoc = await transaction.get(qrUseRef);
      if (qrUseDoc.exists) {
        throw const PickupFlowException(
          'This QR code has already been used today.',
        );
      }

      final payload = {
        'guardianId': guardianId,
        'guardianName': guardianName,
        'relation': relation,
        'childId': childId,
        'childName': childName,
        if (section != null && section.isNotEmpty) 'section': section,
        'parentId': parentId,
        'teacherId': teacherId,
        'timestamp': FieldValue.serverTimestamp(),
      };

      transaction.set(logRef, payload);
      transaction.set(statusRef, {
        'status': 'picked_up',
        'childId': childId,
        'childName': childName,
        if (section != null && section.isNotEmpty) 'section': section,
        'parentId': parentId,
        'guardianId': guardianId,
        'guardianName': guardianName,
        'teacherId': teacherId,
        'pickupLogId': logRef.id,
        'date': todayKey(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(qrUseRef, {
        'guardianId': guardianId,
        'childId': childId,
        'pickupLogId': logRef.id,
        'date': todayKey(),
        'usedByTeacherId': teacherId,
        'usedAt': FieldValue.serverTimestamp(),
      });
    });

    await _completeActivePickupRequests(
      childId: childId,
      section: section,
      pickupLogId: logRef.id,
      firestore: firestore,
      teacherId: teacherId,
    );

    await AuditLogService.record(
      action: 'pickup.release',
      targetType: 'child',
      targetId: childId,
      details: {
        'childName': childName,
        'guardianId': guardianId,
        'guardianName': guardianName,
        'section': section,
      },
    );
  }

  static Future<void> _completeActivePickupRequests({
    required String childId,
    required String? section,
    required String pickupLogId,
    required FirebaseFirestore firestore,
    required String? teacherId,
  }) async {
    if (section == null || section.isEmpty) return;

    try {
      final requestSnap = await firestore
          .collection('pickupRequests')
          .where('section', isEqualTo: section)
          .get();
      final batch = firestore.batch();
      var hasUpdates = false;

      for (final doc in requestSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        if (data['childId'] == childId &&
            (status == 'pending' || status == 'acknowledged')) {
          batch.update(doc.reference, {
            'status': 'completed',
            'pickupLogId': pickupLogId,
            'completedAt': FieldValue.serverTimestamp(),
            'completedByTeacherId': teacherId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) await batch.commit();
    } catch (_) {
      // Pickup release is the source of truth; request completion is best effort.
    }
  }
}
