import 'package:flutter/material.dart';

import '../services/user_role_service.dart';
import 'app_components.dart';

class RoleGate extends StatelessWidget {
  final String requiredRole;
  final Widget child;
  final String title;

  const RoleGate({
    super.key,
    required this.requiredRole,
    required this.child,
    this.title = 'Restricted Area',
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: UserRoleService.currentUserRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: AppEmptyState(
              icon: Icons.error_outline,
              title: 'Unable to verify access',
              message: '${snapshot.error}',
            ),
          );
        }

        if (snapshot.data != requiredRole) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const AppEmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin access required',
              message: 'Only administrator accounts can use this view.',
            ),
          );
        }

        return child;
      },
    );
  }
}

Future<bool> requireAdminAccess(BuildContext context) async {
  final isAdmin = await UserRoleService.isCurrentUserAdmin();
  if (isAdmin) return true;

  if (context.mounted) {
    showAppSnack(
      context,
      'Only admins can perform this action.',
      type: AppFeedbackType.error,
    );
  }
  return false;
}
