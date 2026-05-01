import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../services/auth_account_creator.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_validators.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class CreateParentAccount extends StatefulWidget {
  const CreateParentAccount({super.key});

  @override
  State<CreateParentAccount> createState() => _CreateParentAccountState();
}

class _CreateParentAccountState extends State<CreateParentAccount> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _createParent() async {
    if (!await requireAdminAccess(context)) return;

    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack('Please fill in all required fields', isError: true);
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
        'phone': _phoneController.text.trim(),
        'role': 'parent',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await AuditLogService.record(
        action: 'account.create_parent',
        targetType: 'user',
        targetId: uid,
        details: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
        },
      );

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _phoneController.clear();

      if (!mounted) return;
      _showSnack('Parent account created successfully', isError: false);
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
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Create Parent',
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Parent')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AppConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InfoBanner(
                    icon: Icons.family_restroom,
                    message:
                        'Parent accounts can add children, guardians, and view pickup records.',
                    color: AppPalette.primary,
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionTitle(
                          title: 'Parent Details',
                          subtitle:
                              'Required fields are marked with an asterisk',
                        ),
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email address *',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password *',
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
                            onPressed: _isLoading ? null : _createParent,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_outlined),
                            label: Text(
                              _isLoading ? 'Creating account' : 'Create parent',
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
