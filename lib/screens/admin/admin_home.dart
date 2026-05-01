import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';
import '../login_screen.dart';
import 'create_parent_account.dart';
import 'create_teacher_account.dart';
import 'manage_user.dart';
import 'pending_approvals.dart';
import 'reports.dart';
import 'section_overview.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Sign out',
      message: 'Return to the login screen?',
      confirmLabel: 'Sign out',
      type: AppFeedbackType.warning,
    );
    if (!confirmed) return;

    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      requiredRole: 'admin',
      title: 'Admin Dashboard',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AppSectionTitle(
                title: 'Overview',
                subtitle: 'Enrollment, accounts, and section coverage',
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 560 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: constraints.maxWidth > 560 ? 1.35 : 1.55,
                    children: const [
                      _MetricStream(
                        label: 'Pending',
                        icon: Icons.pending_actions_outlined,
                        color: AppPalette.amber,
                        collection: 'children',
                        pendingOnly: true,
                      ),
                      _MetricStream(
                        label: 'Teachers',
                        icon: Icons.school_outlined,
                        color: AppPalette.violet,
                        collection: 'users',
                        field: 'role',
                        value: 'teacher',
                      ),
                      _MetricStream(
                        label: 'Parents',
                        icon: Icons.family_restroom,
                        color: AppPalette.primary,
                        collection: 'users',
                        field: 'role',
                        value: 'parent',
                      ),
                      _MetricStream(
                        label: 'Students',
                        icon: Icons.child_care_outlined,
                        color: AppPalette.teal,
                        collection: 'children',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const AppSectionTitle(title: 'Admin Tools'),
              _AdminAction(
                icon: Icons.pending_actions_outlined,
                title: 'Pending Approvals',
                subtitle: 'Review child enrollment requests',
                color: AppPalette.amber,
                destination: const PendingApprovals(),
              ),
              const SizedBox(height: 10),
              _AdminAction(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Create Parent Account',
                subtitle: 'Issue a parent login',
                color: AppPalette.primary,
                destination: const CreateParentAccount(),
              ),
              const SizedBox(height: 10),
              _AdminAction(
                icon: Icons.badge_outlined,
                title: 'Create Teacher Account',
                subtitle: 'Assign a teacher to a section',
                color: AppPalette.violet,
                destination: const CreateTeacherAccount(),
              ),
              const SizedBox(height: 10),
              _AdminAction(
                icon: Icons.manage_accounts_outlined,
                title: 'Manage Accounts',
                subtitle: 'Search and maintain user records',
                color: AppPalette.teal,
                destination: const ManageUsers(),
              ),
              const SizedBox(height: 10),
              _AdminAction(
                icon: Icons.grid_view_outlined,
                title: 'Section Overview',
                subtitle: 'Check teacher and student assignments',
                color: AppPalette.primaryDark,
                destination: const SectionOverview(),
              ),
              const SizedBox(height: 10),
              _AdminAction(
                icon: Icons.bar_chart_outlined,
                title: 'Reports',
                subtitle: 'Daily pickups and activity log',
                color: AppPalette.success,
                destination: const AdminReports(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricStream extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String collection;
  final String? field;
  final String? value;
  final bool pendingOnly;

  const _MetricStream({
    required this.label,
    required this.icon,
    required this.color,
    required this.collection,
    this.field,
    this.value,
    this.pendingOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      collection,
    );
    if (field != null && value != null) {
      query = query.where(field!, isEqualTo: value);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final count = pendingOnly
            ? docs.where((doc) => _isPendingChild(doc.data())).length
            : docs.length;
        return AppMetricCard(
          icon: icon,
          label: label,
          value: snapshot.hasError ? '--' : '$count',
          color: color,
        );
      },
    );
  }
}

bool _isPendingChild(Map<String, dynamic> data) {
  final status = (data['status'] ?? '').toString().trim().toLowerCase();
  return status.isEmpty ||
      status == 'pending' ||
      status == 'for approval' ||
      status == 'for_approval';
}

class _AdminAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget destination;

  const _AdminAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return AppActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: color,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => destination)),
    );
  }
}
