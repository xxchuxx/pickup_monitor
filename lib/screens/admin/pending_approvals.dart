import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class PendingApprovals extends StatelessWidget {
  const PendingApprovals({super.key});

  bool _isPendingEnrollment(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    if (status.isEmpty) return true;
    return status == 'pending' ||
        status == 'for approval' ||
        status == 'for_approval';
  }

  int _createdSortValue(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Future<void> _updateChildStatus(
    BuildContext context,
    String docId,
    String status,
  ) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return;

    if (status == 'rejected') {
      final confirmed = await showAppConfirmDialog(
        context,
        title: 'Reject request',
        message: 'Reject this enrollment request?',
        confirmLabel: 'Reject',
        type: AppFeedbackType.error,
      );
      if (!confirmed) return;
    }

    final childRef = FirebaseFirestore.instance
        .collection('children')
        .doc(docId);
    final childDoc = await childRef.get();
    final childData = childDoc.data() ?? {};
    final parentId = childData['parentId']?.toString();
    Map<String, dynamic> parentData = {};

    if (parentId != null && parentId.isNotEmpty) {
      final parentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .get();
      parentData = parentDoc.data() ?? {};
    }

    await childRef.update({
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (status == 'approved') ...{
        'parentName': parentData['name'] ?? childData['parentName'] ?? '',
        'parentEmail': parentData['email'] ?? childData['parentEmail'] ?? '',
        'parentPhone': parentData['phone'] ?? childData['parentPhone'] ?? '',
      },
    });

    await AuditLogService.record(
      action: 'child.$status',
      targetType: 'child',
      targetId: docId,
      details: {
        'name': childData['name'],
        'section': childData['section'],
        'parentId': parentId,
      },
    );

    if (!context.mounted) return;
    showAppSnack(
      context,
      'Request ${status == 'approved' ? 'approved' : 'rejected'}',
      type: status == 'approved'
          ? AppFeedbackType.success
          : AppFeedbackType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Pending Approvals',
      child: Scaffold(
        appBar: AppBar(title: const Text('Pending Approvals')),
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('children')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: 'Unable to load approvals',
                  message: '${snapshot.error}',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs =
                  (snapshot.data?.docs ?? []).where((doc) {
                    return _isPendingEnrollment(doc.data());
                  }).toList()..sort((a, b) {
                    final aValue = _createdSortValue(a.data());
                    final bValue = _createdSortValue(b.data());
                    return bValue.compareTo(aValue);
                  });

              if (docs.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.verified_outlined,
                  title: 'No pending approvals',
                  message: 'New enrollment requests will appear here.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final name = (data['name'] ?? 'Unnamed child').toString();
                  final age = (data['age'] ?? '').toString();
                  final section = (data['section'] ?? '').toString();

                  return AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppIconBox(
                              icon: Icons.child_care_outlined,
                              color: AppPalette.amber,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: AppPalette.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Age $age - $section',
                                    style: const TextStyle(
                                      color: AppPalette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const StatusPill(
                              label: 'PENDING',
                              color: AppPalette.amber,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _updateChildStatus(
                                  context,
                                  doc.id,
                                  'rejected',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppPalette.danger,
                                  side: const BorderSide(
                                    color: AppPalette.danger,
                                  ),
                                ),
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _updateChildStatus(
                                  context,
                                  doc.id,
                                  'approved',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppPalette.success,
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
