import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../services/auth_account_creator.dart';
import '../../services/section_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_validators.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class CreateTeacherAccount extends StatefulWidget {
  const CreateTeacherAccount({super.key});

  @override
  State<CreateTeacherAccount> createState() => _CreateTeacherAccountState();
}

class _CreateTeacherAccountState extends State<CreateTeacherAccount> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _selectedSection;

  Future<void> _createTeacher() async {
    if (!await requireAdminAccess(context)) return;

    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack('Please fill in all fields', isError: true);
      return;
    }
    if (_selectedSection == null) {
      _showSnack('Please assign a section to this teacher', isError: true);
      return;
    }
    if (!InputValidators.isValidEmail(_emailController.text)) {
      _showSnack('Please enter a valid email address', isError: true);
      return;
    }
    if (!InputValidators.isStrongEnoughPassword(_passwordController.text)) {
      _showSnack('Password must be at least 6 characters', isError: true);
      return;
    }

    final assignedSection = _selectedSection!;
    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('assignedSection', isEqualTo: assignedSection)
        .get();

    if (!mounted) return;

    if (existing.docs.isNotEmpty) {
      _showSnack(
        '$assignedSection already has a teacher assigned',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = await AuthAccountCreator.createAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'teacher',
        'assignedSection': assignedSection,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('sections')
          .doc(assignedSection)
          .set({
            'name': assignedSection,
            'teacherId': uid,
            'teacherName': _nameController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await AuditLogService.record(
        action: 'account.create_teacher',
        targetType: 'user',
        targetId: uid,
        details: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'assignedSection': assignedSection,
        },
      );

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();

      if (!mounted) return;
      setState(() => _selectedSection = null);
      _showSnack(
        'Teacher account created for $assignedSection',
        isError: false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message ?? 'An error occurred', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppPalette.danger : AppPalette.success,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Create Teacher',
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Teacher')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AppConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InfoBanner(
                    icon: Icons.info_outline,
                    message:
                        'Each section can have one active teacher assignment.',
                    color: AppPalette.violet,
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionTitle(
                          title: 'Assign Section',
                          subtitle: 'Occupied sections are locked',
                        ),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: SectionService.streamSections(),
                          builder: (context, sectionSnap) {
                            if (sectionSnap.hasError) {
                              return AppEmptyState(
                                icon: Icons.error_outline,
                                title: 'Unable to load sections',
                                message: '${sectionSnap.error}',
                              );
                            }

                            final sections =
                                SectionService.sectionNamesFromDocs(
                                  sectionSnap.data?.docs ?? const [],
                                );

                            return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .where('role', isEqualTo: 'teacher')
                                  .snapshots(),
                              builder: (context, teacherSnap) {
                                final assignedSections =
                                    teacherSnap.data?.docs
                                        .map((d) => d.data()['assignedSection'])
                                        .whereType<String>()
                                        .toSet() ??
                                    <String>{};

                                if (sectionSnap.connectionState ==
                                        ConnectionState.waiting &&
                                    !sectionSnap.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                return Column(
                                  children: sections.map((section) {
                                    final isTaken = assignedSections.contains(
                                      section,
                                    );
                                    final isSelected =
                                        _selectedSection == section;
                                    final borderColor = isSelected
                                        ? AppPalette.violet
                                        : AppPalette.border;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppPalette.violet.withValues(
                                                  alpha: 0.06,
                                                )
                                              : isTaken
                                              ? AppPalette.background
                                              : AppPalette.surface,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: borderColor,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: isTaken
                                                ? null
                                                : () => setState(
                                                    () => _selectedSection =
                                                        section,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              child: Row(
                                                children: [
                                                  AppIconBox(
                                                    icon: Icons.class_outlined,
                                                    color: isTaken
                                                        ? AppPalette.softText
                                                        : AppPalette.violet,
                                                    size: 36,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      section,
                                                      style: TextStyle(
                                                        color: isTaken
                                                            ? AppPalette
                                                                  .softText
                                                            : AppPalette.ink,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                  if (isTaken)
                                                    const StatusPill(
                                                      label: 'OCCUPIED',
                                                      color: AppPalette.muted,
                                                    ),
                                                  if (isSelected)
                                                    const Icon(
                                                      Icons.check_circle,
                                                      color: AppPalette.violet,
                                                      size: 20,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            );
                          },
                        ),
                        const Divider(),
                        const AppSectionTitle(title: 'Teacher Details'),
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _createTeacher,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.badge_outlined),
                            label: Text(
                              _isLoading
                                  ? 'Creating account'
                                  : 'Create teacher',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
