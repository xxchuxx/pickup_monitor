import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../login_screen.dart';
import 'add_child.dart';
import 'add_guardian.dart';
import 'pickup_history.dart';
import 'start_pickup.dart';

class ParentHome extends StatelessWidget {
  const ParentHome({super.key});

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
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Portal'),
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
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('children')
                  .where('parentId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                return AppMetricCard(
                  icon: Icons.child_care_outlined,
                  label: 'Registered children',
                  value: '$count',
                  color: AppPalette.primary,
                );
              },
            ),
            const SizedBox(height: 22),
            const AppSectionTitle(title: 'Quick Actions'),
            AppActionTile(
              icon: Icons.directions_walk_outlined,
              title: 'Start Pickup',
              subtitle: 'Tell the teacher who is coming for your child',
              accentColor: AppPalette.success,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const StartPickup())),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.person_add_alt_1_outlined,
              title: 'Add Child',
              subtitle: 'Submit a student enrollment request',
              accentColor: AppPalette.primary,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AddChild())),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.group_add_outlined,
              title: 'Add Guardian',
              subtitle: 'Create an authorized pickup profile',
              accentColor: AppPalette.teal,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AddGuardian())),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.history_outlined,
              title: 'Pickup History',
              subtitle: 'Review completed releases',
              accentColor: AppPalette.amber,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PickupHistory())),
            ),
          ],
        ),
      ),
    );
  }
}
