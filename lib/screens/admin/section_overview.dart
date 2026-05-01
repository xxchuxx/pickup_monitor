import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../services/section_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class SectionOverview extends StatefulWidget {
  const SectionOverview({super.key});

  @override
  State<SectionOverview> createState() => _SectionOverviewState();
}

class _SectionOverviewState extends State<SectionOverview> {
  Future<void> _showAddSectionDialog() async {
    final hasAccess = await requireAdminAccess(context);
    if (!mounted || !hasAccess) return;

    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> saveSection() async {
              final sectionName = controller.text.trim();

              if (sectionName.isEmpty) {
                showAppSnack(
                  dialogContext,
                  'Please enter a section name',
                  type: AppFeedbackType.error,
                );
                return;
              }

              if (sectionName.contains('/')) {
                showAppSnack(
                  dialogContext,
                  'Section name cannot contain /',
                  type: AppFeedbackType.error,
                );
                return;
              }

              setDialogState(() => isSaving = true);
              var dialogClosed = false;

              try {
                final exists = await SectionService.sectionExists(sectionName);
                if (exists) {
                  if (!dialogContext.mounted) return;
                  showAppSnack(
                    dialogContext,
                    '$sectionName already exists',
                    type: AppFeedbackType.error,
                  );
                  return;
                }

                await SectionService.createSection(sectionName);
                await AuditLogService.record(
                  action: 'section.create',
                  targetType: 'section',
                  targetId: sectionName,
                  details: {'name': sectionName},
                );

                if (!dialogContext.mounted) return;
                dialogClosed = true;
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('$sectionName added'),
                    backgroundColor: AppPalette.success,
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                showAppSnack(
                  dialogContext,
                  'Error: $e',
                  type: AppFeedbackType.error,
                );
              } finally {
                if (!dialogClosed && dialogContext.mounted) {
                  setDialogState(() => isSaving = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Add Section'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!isSaving) saveSection();
                },
                decoration: const InputDecoration(
                  labelText: 'Section name',
                  hintText: 'Example: Section E',
                  prefixIcon: Icon(Icons.class_outlined),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving ? null : saveSection,
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(isSaving ? 'Adding' : 'Add section'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Section Overview',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Section Overview'),
          actions: [
            IconButton(
              tooltip: 'Add section',
              onPressed: _showAddSectionDialog,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddSectionDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add Section'),
        ),
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: SectionService.streamSections(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: 'Unable to load sections',
                  message: '${snapshot.error}',
                );
              }

              final sections = SectionService.sectionNamesFromDocs(
                snapshot.data?.docs ?? const [],
              );

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                itemCount: sections.length + 1,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return InfoBanner(
                      icon: Icons.class_outlined,
                      message:
                          'Add sections here, then assign teachers and enroll children into them.',
                      color: AppPalette.primaryDark,
                    );
                  }

                  final section = sections[index - 1];
                  return _SectionCard(sectionName: section);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String sectionName;

  const _SectionCard({required this.sectionName});

  Future<void> _assignTeacher(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> teacher,
    required String teacherName,
    String? currentTeacherId,
    String? currentTeacherName,
  }) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return;

    final teacherData = teacher.data();
    final previousSection = (teacherData['assignedSection'] ?? '')
        .toString()
        .trim();

    if (teacher.id == currentTeacherId) {
      showAppSnack(
        context,
        '$teacherName is already assigned to $sectionName.',
        type: AppFeedbackType.info,
      );
      return;
    }

    if (previousSection.isNotEmpty && previousSection != sectionName) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: 'Move teacher',
        message:
            '$teacherName is currently assigned to $previousSection. Move them to $sectionName?',
        confirmLabel: 'Move',
        type: AppFeedbackType.warning,
      );
      if (!context.mounted || !confirmed) return;
    }

    final batch = FirebaseFirestore.instance.batch();
    final users = FirebaseFirestore.instance.collection('users');
    final sections = FirebaseFirestore.instance.collection('sections');

    if (currentTeacherId != null && currentTeacherId != teacher.id) {
      batch.update(users.doc(currentTeacherId), {
        'assignedSection': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (previousSection.isNotEmpty && previousSection != sectionName) {
      batch.set(sections.doc(previousSection), {
        'teacherId': FieldValue.delete(),
        'teacherName': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.update(users.doc(teacher.id), {
      'assignedSection': sectionName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(sections.doc(sectionName), {
      'name': sectionName,
      'teacherId': teacher.id,
      'teacherName': teacherName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    await AuditLogService.record(
      action: 'section.assign_teacher',
      targetType: 'section',
      targetId: sectionName,
      details: {
        'teacherId': teacher.id,
        'teacherName': teacherName,
        'previousTeacherId': currentTeacherId,
        'previousTeacherName': currentTeacherName,
        'previousSection': previousSection,
      },
    );

    if (!context.mounted) return;
    showAppSnack(
      context,
      '$teacherName assigned to $sectionName',
      type: AppFeedbackType.success,
    );
  }

  Future<void> _unassignTeacher(
    BuildContext context, {
    required String currentTeacherId,
    required String currentTeacherName,
  }) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Unassign teacher',
      message: 'Remove $currentTeacherName from $sectionName?',
      confirmLabel: 'Unassign',
      type: AppFeedbackType.warning,
    );

    if (!context.mounted || !confirmed) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.update(
      FirebaseFirestore.instance.collection('users').doc(currentTeacherId),
      {
        'assignedSection': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      FirebaseFirestore.instance.collection('sections').doc(sectionName),
      {
        'teacherId': FieldValue.delete(),
        'teacherName': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    await AuditLogService.record(
      action: 'section.unassign_teacher',
      targetType: 'section',
      targetId: sectionName,
      details: {
        'teacherId': currentTeacherId,
        'teacherName': currentTeacherName,
      },
    );

    if (!context.mounted) return;
    showAppSnack(
      context,
      '$currentTeacherName removed from $sectionName',
      type: AppFeedbackType.success,
    );
  }

  Future<bool> _removeGuardianAccess(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> guardianDoc,
    required String childName,
  }) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return false;

    final guardian = guardianDoc.data();
    final guardianName = (guardian['name'] ?? 'Guardian').toString();
    final parentId = (guardian['parentId'] ?? '').toString().trim();

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove guardian access',
      message: 'Remove pickup access for $guardianName from $childName?',
      confirmLabel: 'Remove access',
      type: AppFeedbackType.error,
    );

    if (!context.mounted || !confirmed) return false;

    final update = <String, dynamic>{
      'active': false,
      'parentId': FieldValue.delete(),
      'revokedByAdmin': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (parentId.isNotEmpty) {
      update['previousParentId'] = parentId;
    }

    await guardianDoc.reference.update(update);

    await AuditLogService.record(
      action: 'guardian.admin_remove_access',
      targetType: 'guardian',
      targetId: guardianDoc.id,
      details: {
        'guardianName': guardianName,
        'childId': guardian['childId'],
        'childName': childName,
        'parentId': parentId,
      },
    );

    if (!context.mounted) return true;
    showAppSnack(
      context,
      '$guardianName access removed',
      type: AppFeedbackType.success,
    );
    return true;
  }

  Future<bool> _removeParentAccess(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> childDoc,
  }) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return false;

    final child = childDoc.data();
    final childName = (child['name'] ?? 'this child').toString();
    final parentId = (child['parentId'] ?? '').toString().trim();
    final parentName = (child['parentName'] ?? 'Parent').toString();

    if (parentId.isEmpty) {
      showAppSnack(
        context,
        'This child has no active parent link.',
        type: AppFeedbackType.info,
      );
      return false;
    }

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove parent access',
      message:
          'Remove $parentName from $childName and revoke all guardian QR access for this child?',
      confirmLabel: 'Remove access',
      type: AppFeedbackType.error,
    );

    if (!context.mounted || !confirmed) return false;

    final guardianSnap = await FirebaseFirestore.instance
        .collection('guardians')
        .where('childId', isEqualTo: childDoc.id)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    batch.update(childDoc.reference, {
      'parentId': FieldValue.delete(),
      'parentName': FieldValue.delete(),
      'parentEmail': FieldValue.delete(),
      'parentPhone': FieldValue.delete(),
      'parentAccessRevoked': true,
      'parentAccessRevokedAt': FieldValue.serverTimestamp(),
      'revokedParentId': parentId,
      'revokedParentName': child['parentName'] ?? '',
      'revokedParentEmail': child['parentEmail'] ?? '',
      'revokedParentPhone': child['parentPhone'] ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final guardian in guardianSnap.docs) {
      final data = guardian.data();
      final guardianParentId = (data['parentId'] ?? '').toString().trim();
      batch.update(guardian.reference, {
        'active': false,
        'parentId': FieldValue.delete(),
        if (guardianParentId.isNotEmpty) 'previousParentId': guardianParentId,
        'revokedByAdmin': true,
        'revokedReason': 'parent_access_removed',
        'revokedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    await AuditLogService.record(
      action: 'child.remove_parent_access',
      targetType: 'child',
      targetId: childDoc.id,
      details: {
        'childName': childName,
        'parentId': parentId,
        'parentName': parentName,
        'guardianCount': guardianSnap.docs.length,
      },
    );

    if (!context.mounted) return true;
    showAppSnack(
      context,
      'Parent and guardian access removed',
      type: AppFeedbackType.success,
    );
    return true;
  }

  void _showChildAccessSheet(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> childDoc,
  }) {
    final parentContext = context;
    final child = childDoc.data();
    final childName = (child['name'] ?? 'Unknown child').toString();
    final section = (child['section'] ?? sectionName).toString();
    final parentId = (child['parentId'] ?? '').toString().trim();
    final parentName = (child['parentName'] ?? '').toString().trim();
    final parentEmail = (child['parentEmail'] ?? '').toString().trim();
    final parentPhone = (child['parentPhone'] ?? '').toString().trim();
    final revokedParentName = (child['revokedParentName'] ?? '')
        .toString()
        .trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.5,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        const AppIconBox(
                          icon: Icons.admin_panel_settings_outlined,
                          color: AppPalette.danger,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Child Access',
                                style: const TextStyle(
                                  color: AppPalette.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '$childName - $section',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppPalette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppSectionTitle(
                                title: 'Parent Access',
                                subtitle:
                                    'Removing the parent also disables all guardians for this child',
                              ),
                              if (parentId.isEmpty)
                                InfoBanner(
                                  icon: Icons.person_off_outlined,
                                  message: revokedParentName.isEmpty
                                      ? 'No parent currently has access to this child.'
                                      : '$revokedParentName no longer has access to this child.',
                                  color: AppPalette.amber,
                                )
                              else ...[
                                Row(
                                  children: [
                                    InitialsAvatar(
                                      name: parentName.isEmpty
                                          ? 'Parent'
                                          : parentName,
                                      color: AppPalette.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            parentName.isEmpty
                                                ? 'Parent account'
                                                : parentName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppPalette.ink,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (parentEmail.isNotEmpty)
                                            Text(
                                              parentEmail,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppPalette.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (parentPhone.isNotEmpty)
                                            Text(
                                              parentPhone,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppPalette.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _removeParentAccess(
                                        parentContext,
                                        childDoc: childDoc,
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppPalette.danger,
                                      side: const BorderSide(
                                        color: AppPalette.danger,
                                      ),
                                    ),
                                    icon: const Icon(Icons.link_off_outlined),
                                    label: const Text('Remove parent access'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const AppSectionTitle(
                          title: 'Guardian Access',
                          subtitle: 'Remove individual QR pickup access',
                        ),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('guardians')
                              .where('childId', isEqualTo: childDoc.id)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const SizedBox(
                                height: 160,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return AppEmptyState(
                                icon: Icons.error_outline,
                                title: 'Unable to load guardians',
                                message: '${snapshot.error}',
                              );
                            }

                            final guardians = snapshot.data?.docs ?? [];
                            if (guardians.isEmpty) {
                              return const AppEmptyState(
                                icon: Icons.group_off_outlined,
                                title: 'No guardians for this child',
                              );
                            }

                            final sortedGuardians = [...guardians]
                              ..sort((a, b) {
                                final aActive = a.data()['active'] == true;
                                final bActive = b.data()['active'] == true;
                                if (aActive != bActive) {
                                  return aActive ? -1 : 1;
                                }
                                final aName = (a.data()['name'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final bName = (b.data()['name'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                return aName.compareTo(bName);
                              });

                            return Column(
                              children: sortedGuardians.map((guardianDoc) {
                                final guardian = guardianDoc.data();
                                final guardianName =
                                    (guardian['name'] ?? 'Guardian').toString();
                                final relation = (guardian['relation'] ?? '')
                                    .toString();
                                final phone = (guardian['phone'] ?? '')
                                    .toString();
                                final active = guardian['active'] == true;
                                final hasParentLink =
                                    (guardian['parentId'] ?? '')
                                        .toString()
                                        .trim()
                                        .isNotEmpty;
                                final removedByAdmin =
                                    guardian['revokedByAdmin'] == true ||
                                    !hasParentLink;
                                final canRemove = active || hasParentLink;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: AppCard(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        InitialsAvatar(
                                          name: guardianName,
                                          color: active
                                              ? AppPalette.violet
                                              : AppPalette.muted,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                guardianName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppPalette.ink,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                relation.isEmpty
                                                    ? childName
                                                    : '$relation - $childName',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppPalette.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (phone.isNotEmpty)
                                                Text(
                                                  phone,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppPalette.muted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              const SizedBox(height: 6),
                                              StatusPill(
                                                label: active
                                                    ? 'ACTIVE'
                                                    : removedByAdmin
                                                    ? 'ACCESS REMOVED'
                                                    : 'DISABLED',
                                                color: active
                                                    ? AppPalette.success
                                                    : removedByAdmin
                                                    ? AppPalette.danger
                                                    : AppPalette.muted,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'Remove guardian access',
                                          onPressed: canRemove
                                              ? () {
                                                  Navigator.pop(context);
                                                  _removeGuardianAccess(
                                                    parentContext,
                                                    guardianDoc: guardianDoc,
                                                    childName: childName,
                                                  );
                                                }
                                              : null,
                                          icon: const Icon(
                                            Icons.block_outlined,
                                          ),
                                          color: AppPalette.danger,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAssignTeacherSheet(
    BuildContext context, {
    String? currentTeacherId,
    String? currentTeacherName,
  }) {
    final parentContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assign Teacher',
                                style: const TextStyle(
                                  color: AppPalette.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                sectionName,
                                style: const TextStyle(
                                  color: AppPalette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (currentTeacherId != null &&
                            currentTeacherName != null)
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _unassignTeacher(
                                parentContext,
                                currentTeacherId: currentTeacherId,
                                currentTeacherName: currentTeacherName,
                              );
                            },
                            icon: const Icon(Icons.person_remove_outlined),
                            label: const Text('Unassign'),
                          ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(24),
                            children: const [
                              SizedBox(
                                height: 220,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ],
                          );
                        }
                        if (snapshot.hasError) {
                          return ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              AppEmptyState(
                                icon: Icons.error_outline,
                                title: 'Unable to load teachers',
                                message: '${snapshot.error}',
                              ),
                            ],
                          );
                        }

                        final teachers =
                            (snapshot.data?.docs ?? []).where((doc) {
                              final role = (doc.data()['role'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              return role == 'teacher';
                            }).toList()..sort((a, b) {
                              final aName = (a.data()['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final bName = (b.data()['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return aName.compareTo(bName);
                            });

                        if (teachers.isEmpty) {
                          return ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            children: const [
                              AppEmptyState(
                                icon: Icons.school_outlined,
                                title: 'No teacher accounts found',
                                message:
                                    'Create a teacher account in Admin Tools, then assign it here.',
                              ),
                            ],
                          );
                        }

                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: teachers.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final teacher = teachers[index];
                            final data = teacher.data();
                            final name = (data['name'] ?? 'Teacher').toString();
                            final email = (data['email'] ?? '').toString();
                            final assignedSection =
                                (data['assignedSection'] ?? '')
                                    .toString()
                                    .trim();
                            final isCurrent = teacher.id == currentTeacherId;
                            final isAssignedElsewhere =
                                assignedSection.isNotEmpty &&
                                assignedSection != sectionName;

                            return AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  InitialsAvatar(
                                    name: name,
                                    color: isCurrent
                                        ? AppPalette.success
                                        : AppPalette.violet,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppPalette.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (email.isNotEmpty)
                                          Text(
                                            email,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppPalette.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        const SizedBox(height: 6),
                                        StatusPill(
                                          label: isCurrent
                                              ? 'CURRENT'
                                              : assignedSection.isEmpty
                                              ? 'UNASSIGNED'
                                              : assignedSection.toUpperCase(),
                                          color: isCurrent
                                              ? AppPalette.success
                                              : isAssignedElsewhere
                                              ? AppPalette.amber
                                              : AppPalette.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: isCurrent
                                        ? null
                                        : () async {
                                            Navigator.pop(context);
                                            await _assignTeacher(
                                              parentContext,
                                              teacher: teacher,
                                              teacherName: name,
                                              currentTeacherId:
                                                  currentTeacherId,
                                              currentTeacherName:
                                                  currentTeacherName,
                                            );
                                          },
                                    child: Text(
                                      isAssignedElsewhere ? 'Move' : 'Assign',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const AppIconBox(
                  icon: Icons.class_outlined,
                  color: AppPalette.primaryDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sectionName,
                    style: const TextStyle(
                      color: AppPalette.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('children')
                      .where('section', isEqualTo: sectionName)
                      .snapshots(),
                  builder: (context, snap) {
                    final count = snap.data?.docs.length ?? 0;
                    return StatusPill(
                      label: '$count STUDENTS',
                      color: AppPalette.primaryDark,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, teacherSnap) {
              final teacherDocs = (teacherSnap.data?.docs ?? []).where((doc) {
                final data = doc.data();
                final role = (data['role'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final assignedSection = (data['assignedSection'] ?? '')
                    .toString()
                    .trim();
                return role == 'teacher' && assignedSection == sectionName;
              }).toList();
              final teacherDoc = teacherDocs.isNotEmpty
                  ? teacherDocs.first
                  : null;
              final teacher = teacherDoc?.data();
              final teacherName = teacher?['name']?.toString();
              final teacherId = teacherDoc?.id;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      teacherName == null
                          ? Icons.person_off_outlined
                          : Icons.person_outline,
                      size: 18,
                      color: teacherName == null
                          ? AppPalette.amber
                          : AppPalette.success,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Teacher',
                      style: TextStyle(
                        color: AppPalette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        teacherName ?? 'No teacher assigned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: teacherName == null
                              ? AppPalette.amber
                              : AppPalette.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAssignTeacherSheet(
                        context,
                        currentTeacherId: teacherId,
                        currentTeacherName: teacherName,
                      ),
                      icon: Icon(
                        teacherId == null
                            ? Icons.person_add_alt_1_outlined
                            : Icons.swap_horiz,
                        size: 18,
                      ),
                      label: Text(teacherId == null ? 'Assign' : 'Change'),
                    ),
                  ],
                ),
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('children')
                .where('section', isEqualTo: sectionName)
                .snapshots(),
            builder: (context, childSnap) {
              final children = childSnap.data?.docs ?? [];

              if (childSnap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (children.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Text(
                    'No students in this section yet.',
                    style: TextStyle(color: AppPalette.muted, fontSize: 12),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Students',
                      style: TextStyle(
                        color: AppPalette.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...children.map((child) {
                      final data = child.data();
                      final name = (data['name'] ?? 'Unknown').toString();
                      final parentName = data['parentName']?.toString();
                      final status = (data['status'] ?? '').toString();
                      final statusColor = status == 'approved'
                          ? AppPalette.success
                          : status == 'rejected'
                          ? AppPalette.danger
                          : AppPalette.amber;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppPalette.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            InitialsAvatar(
                              name: name,
                              color: AppPalette.primary,
                              radius: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppPalette.ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (parentName != null)
                                    Text(
                                      parentName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppPalette.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (status.isNotEmpty)
                              StatusPill(
                                label: status.toUpperCase(),
                                color: statusColor,
                              ),
                            IconButton(
                              tooltip: 'Manage child access',
                              onPressed: () => _showChildAccessSheet(
                                context,
                                childDoc: child,
                              ),
                              icon: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                              color: AppPalette.danger,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
