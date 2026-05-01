import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/pickup_flow_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/role_gate.dart';

class AdminReports extends StatelessWidget {
  const AdminReports({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return RoleGate(
      requiredRole: 'admin',
      title: 'Reports',
      child: Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppSectionTitle(
                title: 'Today',
                subtitle: DateFormat('MMMM d, yyyy').format(today),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.maxWidth > 560 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: count,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: constraints.maxWidth > 560 ? 1.35 : 1.55,
                    children: [
                      _CountMetric(
                        label: 'Pickups',
                        icon: Icons.check_circle_outline,
                        color: AppPalette.success,
                        query: FirebaseFirestore.instance
                            .collection('pickupLogs')
                            .where(
                              'timestamp',
                              isGreaterThanOrEqualTo: Timestamp.fromDate(
                                startOfDay,
                              ),
                            )
                            .where(
                              'timestamp',
                              isLessThan: Timestamp.fromDate(endOfDay),
                            ),
                      ),
                      _CountMetric(
                        label: 'Pending',
                        icon: Icons.pending_actions_outlined,
                        color: AppPalette.amber,
                        query: FirebaseFirestore.instance.collection(
                          'children',
                        ),
                        pendingOnly: true,
                      ),
                      _CountMetric(
                        label: 'Active Guardians',
                        icon: Icons.supervised_user_circle_outlined,
                        color: AppPalette.violet,
                        query: FirebaseFirestore.instance
                            .collection('guardians')
                            .where('active', isEqualTo: true),
                      ),
                      _CountMetric(
                        label: 'QR Used',
                        icon: Icons.qr_code_2_outlined,
                        color: AppPalette.primary,
                        query: FirebaseFirestore.instance
                            .collection('qrUses')
                            .where(
                              'date',
                              isEqualTo: PickupFlowService.todayKey(today),
                            ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const AppSectionTitle(title: 'Pickup By Section'),
              _SectionPickupSummary(startOfDay: startOfDay, endOfDay: endOfDay),
              const SizedBox(height: 22),
              const AppSectionTitle(title: 'Recent Activity'),
              const _AuditLogList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountMetric extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Query<Map<String, dynamic>> query;
  final bool pendingOnly;

  const _CountMetric({
    required this.label,
    required this.icon,
    required this.color,
    required this.query,
    this.pendingOnly = false,
  });

  @override
  Widget build(BuildContext context) {
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

class _SectionPickupSummary extends StatelessWidget {
  final DateTime startOfDay;
  final DateTime endOfDay;

  const _SectionPickupSummary({
    required this.startOfDay,
    required this.endOfDay,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pickupLogs')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return AppEmptyState(
            icon: Icons.error_outline,
            title: 'Unable to load section summary',
            message: '${snapshot.error}',
          );
        }

        final counts = <String, int>{};
        for (final doc in snapshot.data?.docs ?? []) {
          final section = (doc.data()['section'] ?? 'Unassigned').toString();
          counts[section] = (counts[section] ?? 0) + 1;
        }

        if (counts.isEmpty) {
          return const AppCard(
            child: AppEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'No pickups recorded today',
            ),
          );
        }

        final entries = counts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const AppIconBox(
                      icon: Icons.class_outlined,
                      color: AppPalette.primaryDark,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: AppPalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusPill(
                      label: '${entry.value} PICKUPS',
                      color: AppPalette.success,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _AuditLogList extends StatelessWidget {
  const _AuditLogList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('auditLogs')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return AppEmptyState(
            icon: Icons.error_outline,
            title: 'Unable to load activity',
            message: '${snapshot.error}',
          );
        }

        final logs = snapshot.data?.docs ?? [];
        if (logs.isEmpty) {
          return const AppCard(
            child: AppEmptyState(
              icon: Icons.history_outlined,
              title: 'No activity yet',
            ),
          );
        }

        return Column(
          children: logs.map((doc) {
            final data = doc.data();
            final timestamp = data['createdAt'] as Timestamp?;
            final time = timestamp == null
                ? 'Just now'
                : DateFormat('MMM d, h:mm a').format(timestamp.toDate());

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const AppIconBox(
                      icon: Icons.history_outlined,
                      color: AppPalette.muted,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data['action'] ?? 'Activity').toString(),
                            style: const TextStyle(
                              color: AppPalette.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            (data['actorEmail'] ?? 'System').toString(),
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
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
