import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/input_validators.dart';
import '../widgets/app_components.dart';
import 'admin/admin_home.dart';
import 'parent/parent_home.dart';
import 'teacher/teacher_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool showLoginForm = false;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool showPassword = false;
  bool isLoading = false;
  int selectedPreviewIndex = 0;

  static const List<_FeatureStep> _landingFeatures = [
    _FeatureStep(
      icon: Icons.qr_code_2_outlined,
      title: 'QR Guardian Passes',
      caption: 'Daily pickup codes for approved guardians.',
      color: AppPalette.primary,
    ),
    _FeatureStep(
      icon: Icons.fact_check_outlined,
      title: 'Child Approvals',
      caption: 'Admins review children before access starts.',
      color: AppPalette.amber,
    ),
    _FeatureStep(
      icon: Icons.document_scanner_outlined,
      title: 'Teacher Scanning',
      caption: 'Verify QR codes and release the right child.',
      color: AppPalette.teal,
    ),
    _FeatureStep(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Account Control',
      caption: 'Only admins create parent and teacher accounts.',
      color: AppPalette.violet,
    ),
    _FeatureStep(
      icon: Icons.groups_2_outlined,
      title: 'Section Assignment',
      caption: 'Assign teachers to sections for cleaner queues.',
      color: AppPalette.primaryDark,
    ),
    _FeatureStep(
      icon: Icons.history_outlined,
      title: 'Pickup Records',
      caption: 'Track releases, guardians, and timestamps.',
      color: AppPalette.success,
    ),
  ];

  static const List<_FeatureStep> _pickupFlow = [
    _FeatureStep(
      icon: Icons.qr_code_2_outlined,
      title: 'Daily QR Passes',
      caption: 'Parents prepare active guardian QR passes.',
      color: AppPalette.violet,
    ),
    _FeatureStep(
      icon: Icons.verified_user_outlined,
      title: 'Teacher Verification',
      caption: 'Teachers scan and confirm guardian details.',
      color: AppPalette.teal,
    ),
    _FeatureStep(
      icon: Icons.pending_actions_outlined,
      title: 'Admin Approval',
      caption: 'Admins approve children before pickup access.',
      color: AppPalette.amber,
    ),
  ];

  void _movePreview(int delta) {
    setState(() {
      selectedPreviewIndex =
          (selectedPreviewIndex + delta + _pickupFlow.length) %
          _pickupFlow.length;
    });
  }

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      showAppSnack(
        context,
        'Please fill in all fields',
        type: AppFeedbackType.error,
      );
      return;
    }
    if (!InputValidators.isValidEmail(emailController.text)) {
      showAppSnack(
        context,
        'Please enter a valid email address',
        type: AppFeedbackType.error,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        showAppSnack(
          context,
          'User not found in database',
          type: AppFeedbackType.error,
        );
        return;
      }

      final role = doc['role'];
      Widget destination;

      if (role == 'parent') {
        destination = const ParentHome();
      } else if (role == 'teacher') {
        destination = const TeacherHome();
      } else if (role == 'admin') {
        destination = const AdminHome();
      } else {
        showAppSnack(context, 'Unknown role', type: AppFeedbackType.error);
        return;
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        e.message ?? 'Unable to sign in',
        type: AppFeedbackType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: AppConstrained(
              maxWidth: 520,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.025),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: showLoginForm ? _buildLoginForm() : _buildLanding(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandMark({double size = 92}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
        boxShadow: [
          BoxShadow(
            color: AppPalette.ink.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/family_icon.jpg', fit: BoxFit.cover),
    );
  }

  Widget _buildLanding() {
    final preview = _pickupFlow[selectedPreviewIndex];

    return Column(
      key: const ValueKey('landing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LandingHero(brandMark: _buildBrandMark(size: 88)),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionTitle(
                title: 'Core Features',
                subtitle: 'Built for secure daily school pickup operations',
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 390;
                  final itemWidth = twoColumns
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final feature in _landingFeatures)
                        SizedBox(
                          width: itemWidth,
                          child: _FeatureTile(item: feature),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionTitle(
                title: 'Pickup Flow',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CircleIconButton(
                      tooltip: 'Previous step',
                      icon: Icons.chevron_left,
                      onTap: () => _movePreview(-1),
                    ),
                    const SizedBox(width: 8),
                    _CircleIconButton(
                      tooltip: 'Next step',
                      icon: Icons.chevron_right,
                      onTap: () => _movePreview(1),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: ValueKey(preview.title),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: preview.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: preview.color.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      AppIconBox(icon: preview.icon, color: preview.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.title,
                              style: const TextStyle(
                                color: AppPalette.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              preview.caption,
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
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(_pickupFlow.length, (index) {
                  final selected = index == selectedPreviewIndex;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == _pickupFlow.length - 1 ? 0 : 8,
                      ),
                      child: Tooltip(
                        message: _pickupFlow[index].title,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () =>
                              setState(() => selectedPreviewIndex = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 8,
                            decoration: BoxDecoration(
                              color: selected
                                  ? _pickupFlow[index].color
                                  : AppPalette.border,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          color: AppPalette.primary.withValues(alpha: 0.06),
          borderColor: AppPalette.primary.withValues(alpha: 0.16),
          child: const Row(
            children: [
              AppIconBox(
                icon: Icons.route_outlined,
                color: AppPalette.primary,
                backgroundColor: Colors.white,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centralized Login',
                      style: TextStyle(
                        color: AppPalette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'After sign-in, your account role opens the correct workspace automatically.',
                      style: TextStyle(
                        color: AppPalette.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: () => setState(() => showLoginForm = true),
          icon: const Icon(Icons.login),
          label: const Text('Continue to sign in'),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return AppCard(
      key: const ValueKey('login'),
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildBrandMark(size: 62),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome Back',
                        style: TextStyle(
                          color: AppPalette.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const StatusPill(
                        label: 'SECURE ACCESS',
                        color: AppPalette.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: !showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) {
                if (!isLoading) login();
              },
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: showPassword ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => showPassword = !showPassword),
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 16,
                  color: AppPalette.softText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your workspace opens automatically after sign-in.',
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : login,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(isLoading ? 'Signing in' : 'Sign in securely'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => setState(() => showLoginForm = false),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to overview'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingHero extends StatelessWidget {
  final Widget brandMark;

  const _LandingHero({required this.brandMark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppPalette.primaryDark,
        borderRadius: BorderRadius.circular(8),
        image: DecorationImage(
          image: const AssetImage('assets/family_icon.jpg'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            AppPalette.primaryDark.withValues(alpha: 0.86),
            BlendMode.srcATop,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brandMark,
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroBadge(label: 'SCHOOL PICKUP PLATFORM'),
                    SizedBox(height: 12),
                    Text(
                      'Pickup Monitor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Secure QR pickup, guardian verification, child approvals, and daily release tracking in one professional workspace.',
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroBadge(label: 'Parent'),
              _HeroBadge(label: 'Teacher'),
              _HeroBadge(label: 'Admin'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;

  const _HeroBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final _FeatureStep item;

  const _FeatureTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBox(icon: item.icon, color: item.color, size: 38),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.muted,
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppPalette.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppPalette.border),
          ),
          child: Icon(icon, color: AppPalette.ink, size: 19),
        ),
      ),
    );
  }
}

class _FeatureStep {
  final IconData icon;
  final String title;
  final String caption;
  final Color color;

  const _FeatureStep({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
  });
}
