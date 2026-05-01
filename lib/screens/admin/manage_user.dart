import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../services/section_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_validators.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class ManageUsers extends StatefulWidget {
  const ManageUsers({super.key});

  @override
  State<ManageUsers> createState() => _ManageUsersState();
}

class _ManageUsersState extends State<ManageUsers>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deleteUser(
    BuildContext context,
    String uid,
    String name,
    String role,
    String section,
  ) async {
    final hasAccess = await requireAdminAccess(context);
    if (!context.mounted || !hasAccess) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete account record',
      message:
          'Delete $name from Firestore records? This does not remove the Firebase Auth login.',
      confirmLabel: 'Delete',
      type: AppFeedbackType.error,
    );

    if (!confirmed) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(FirebaseFirestore.instance.collection('users').doc(uid));

    if (role == 'teacher' && section.isNotEmpty) {
      batch.set(
        FirebaseFirestore.instance.collection('sections').doc(section),
        {
          'teacherId': FieldValue.delete(),
          'teacherName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    await AuditLogService.record(
      action: 'account.delete_record',
      targetType: 'user',
      targetId: uid,
      details: {'name': name, 'role': role, 'section': section},
    );

    if (!context.mounted) return;
    showAppSnack(context, '$name deleted', type: AppFeedbackType.success);
  }

  Future<void> _showEditUserSheet(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> user,
    String role,
  ) async {
    final data = user.data();
    final isTeacher = role == 'teacher';
    final nameController = TextEditingController(
      text: (data['name'] ?? '').toString(),
    );
    final emailController = TextEditingController(
      text: (data['email'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (data['phone'] ?? '').toString(),
    );
    final previousSection = (data['assignedSection'] ?? '').toString().trim();
    var selectedSection = previousSection;
    var isSaving = false;
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> saveChanges() async {
              final hasAccess = await requireAdminAccess(sheetContext);
              if (!sheetContext.mounted || !hasAccess) return;

              final name = nameController.text.trim();
              final email = emailController.text.trim();
              final phone = phoneController.text.trim();
              final newSection = selectedSection.trim();

              if (name.isEmpty || email.isEmpty) {
                showAppSnack(
                  sheetContext,
                  'Name and email are required',
                  type: AppFeedbackType.error,
                );
                return;
              }

              if (!InputValidators.isValidEmail(email)) {
                showAppSnack(
                  sheetContext,
                  'Please enter a valid email address',
                  type: AppFeedbackType.error,
                );
                return;
              }

              setSheetState(() => isSaving = true);
              var sheetClosed = false;

              try {
                await _updateUserRecord(
                  uid: user.id,
                  role: role,
                  name: name,
                  email: email,
                  phone: phone,
                  previousSection: previousSection,
                  newSection: newSection,
                );

                await AuditLogService.record(
                  action: 'account.update',
                  targetType: 'user',
                  targetId: user.id,
                  details: {
                    'role': role,
                    'previousName': data['name'],
                    'name': name,
                    'previousEmail': data['email'],
                    'email': email,
                    if (!isTeacher) 'phone': phone,
                    if (isTeacher) 'previousSection': previousSection,
                    if (isTeacher) 'assignedSection': newSection,
                  },
                );

                if (!sheetContext.mounted) return;
                sheetClosed = true;
                Navigator.pop(sheetContext);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('$name updated'),
                    backgroundColor: AppPalette.success,
                  ),
                );
              } catch (e) {
                if (!sheetContext.mounted) return;
                final message = e is _UserFacingException
                    ? e.message
                    : 'Error: $e';
                showAppSnack(
                  sheetContext,
                  message,
                  type: AppFeedbackType.error,
                );
              } finally {
                if (!sheetClosed && sheetContext.mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppPalette.border,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            AppIconBox(
                              icon: isTeacher
                                  ? Icons.school_outlined
                                  : Icons.family_restroom,
                              color: isTeacher
                                  ? AppPalette.violet
                                  : AppPalette.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isTeacher ? 'Edit Teacher' : 'Edit Parent',
                                    style: const TextStyle(
                                      color: AppPalette.ink,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Text(
                                    'Update school account details',
                                    style: TextStyle(
                                      color: AppPalette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        InfoBanner(
                          icon: Icons.info_outline,
                          message:
                              'Email edits update school records only. The Firebase Auth sign-in email is unchanged.',
                          color: isTeacher
                              ? AppPalette.violet
                              : AppPalette.primary,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!isTeacher) ...[
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: isTeacher
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted: (_) {
                            if (!isTeacher && !isSaving) saveChanges();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        if (isTeacher) ...[
                          const SizedBox(height: 14),
                          const AppSectionTitle(
                            title: 'Section Assignment',
                            subtitle:
                                'Choose an available section or leave unassigned',
                          ),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: SectionService.streamSections(),
                            builder: (context, sectionSnap) {
                              if (sectionSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  !sectionSnap.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              if (sectionSnap.hasError) {
                                return InfoBanner(
                                  icon: Icons.error_outline,
                                  message:
                                      'Unable to load sections: ${sectionSnap.error}',
                                  color: AppPalette.danger,
                                );
                              }

                              final sections =
                                  SectionService.sectionNamesFromDocs(
                                    sectionSnap.data?.docs ?? const [],
                                  );
                              if (selectedSection.isNotEmpty &&
                                  !sections.contains(selectedSection)) {
                                sections.add(selectedSection);
                                sections.sort(
                                  (a, b) => a.toLowerCase().compareTo(
                                    b.toLowerCase(),
                                  ),
                                );
                              }

                              return DropdownButtonFormField<String>(
                                key: ValueKey(selectedSection),
                                initialValue: selectedSection,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Assigned section',
                                  prefixIcon: Icon(Icons.class_outlined),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('No assigned section'),
                                  ),
                                  ...sections.map(
                                    (section) => DropdownMenuItem(
                                      value: section,
                                      child: Text(section),
                                    ),
                                  ),
                                ],
                                onChanged: isSaving
                                    ? null
                                    : (value) => setSheetState(
                                        () => selectedSection = value ?? '',
                                      ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isSaving ? null : saveChanges,
                            icon: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(isSaving ? 'Saving' : 'Save changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }

  Future<void> _updateUserRecord({
    required String uid,
    required String role,
    required String name,
    required String email,
    required String phone,
    required String previousSection,
    required String newSection,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(uid);

    if (role == 'teacher' && newSection.isNotEmpty) {
      final existing = await firestore
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('assignedSection', isEqualTo: newSection)
          .get();

      final occupiedByOther = existing.docs.any((doc) => doc.id != uid);
      if (occupiedByOther) {
        throw _UserFacingException(
          '$newSection already has another teacher assigned',
        );
      }
    }

    final batch = firestore.batch();
    final updateData = <String, dynamic>{
      'name': name,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (role == 'parent') {
      updateData['phone'] = phone;

      final children = await firestore
          .collection('children')
          .where('parentId', isEqualTo: uid)
          .get();

      for (final child in children.docs) {
        batch.update(child.reference, {
          'parentName': name,
          'parentEmail': email,
          'parentPhone': phone,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (role == 'teacher') {
      updateData['assignedSection'] = newSection.isEmpty
          ? FieldValue.delete()
          : newSection;

      final sections = firestore.collection('sections');

      if (previousSection.isNotEmpty && previousSection != newSection) {
        batch.set(sections.doc(previousSection), {
          'teacherId': FieldValue.delete(),
          'teacherName': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (newSection.isNotEmpty) {
        batch.set(sections.doc(newSection), {
          'name': newSection,
          'teacherId': uid,
          'teacherName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    batch.update(userRef, updateData);
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Manage Accounts',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Accounts'),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppPalette.primary,
            labelColor: AppPalette.ink,
            unselectedLabelColor: AppPalette.muted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Teachers'),
              Tab(text: 'Parents'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase().trim()),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, email, or phone',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildUserList('teacher'),
                    _buildUserList('parent'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(String role) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: role)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppEmptyState(
            icon: Icons.error_outline,
            title: 'Unable to load ${role}s',
            message: '${snapshot.error}',
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState(role);

        final users = docs.where((doc) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString().toLowerCase();
          final email = (data['email'] ?? '').toString().toLowerCase();
          final phone = (data['phone'] ?? '').toString().toLowerCase();
          return _searchQuery.isEmpty ||
              name.contains(_searchQuery) ||
              email.contains(_searchQuery) ||
              phone.contains(_searchQuery);
        }).toList();

        if (users.isEmpty) {
          return const AppEmptyState(
            icon: Icons.search_off,
            title: 'No matches found',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = users[index];
            return _buildUserCard(context, user, role);
          },
        );
      },
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> user,
    String role,
  ) {
    final data = user.data();
    final isTeacher = role == 'teacher';
    final name = (data['name'] ?? 'No name').toString();
    final email = (data['email'] ?? '').toString();
    final phone = (data['phone'] ?? '').toString();
    final section = isTeacher ? (data['assignedSection'] ?? '').toString() : '';
    final accentColor = isTeacher ? AppPalette.violet : AppPalette.primary;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          InitialsAvatar(name: name, color: accentColor),
          const SizedBox(width: 12),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppPalette.muted, fontSize: 12),
                ),
                if (!isTeacher && phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (isTeacher) ...[
                  const SizedBox(height: 6),
                  StatusPill(
                    label: section.isEmpty ? 'UNASSIGNED' : section,
                    color: section.isEmpty
                        ? AppPalette.amber
                        : AppPalette.violet,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit account',
            onPressed: () => _showEditUserSheet(context, user, role),
            icon: const Icon(Icons.edit_outlined),
            color: accentColor,
          ),
          IconButton(
            tooltip: 'Delete account',
            onPressed: () => _deleteUser(context, user.id, name, role, section),
            icon: const Icon(Icons.delete_outline),
            color: AppPalette.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String role) {
    return AppEmptyState(
      icon: role == 'teacher' ? Icons.school_outlined : Icons.family_restroom,
      title: 'No ${role}s yet',
    );
  }
}

class _UserFacingException implements Exception {
  final String message;

  const _UserFacingException(this.message);
}
