import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/audit_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../login_screen.dart';
import 'scan_qr.dart';

class TeacherHome extends StatefulWidget {
  const TeacherHome({super.key});

  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  String? teacherName;
  String? assignedSection;

  @override
  void initState() {
    super.initState();
    _loadTeacherInfo();
  }

  Future<void> _loadTeacherInfo() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!mounted || !doc.exists) return;

    final data = doc.data() ?? {};
    setState(() {
      teacherName = (data['name'] ?? 'Teacher').toString();
      assignedSection = (data['assignedSection'] ?? '').toString();
    });
  }

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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activePickupRequests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final requests = docs.where((doc) {
      final status = (doc.data()['status'] ?? '').toString();
      return status == 'pending' || status == 'acknowledged';
    }).toList();

    requests.sort((a, b) {
      final aTime = a.data()['createdAt'];
      final bTime = b.data()['createdAt'];
      final aDate = aTime is Timestamp
          ? aTime.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = bTime is Timestamp
          ? bTime.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return requests;
  }

  Color _pickupRequestStatusColor(String status) {
    return switch (status) {
      'pending' => AppPalette.amber,
      'acknowledged' => AppPalette.primary,
      _ => AppPalette.softText,
    };
  }

  String _formatRequestTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('h:mm a').format(timestamp.toDate());
    }
    return 'Just now';
  }

  String _pickupLabel(String name, String relation) {
    final cleanRelation = relation.trim();
    return cleanRelation.isEmpty ? name : '$name ($cleanRelation)';
  }

  Future<void> _acknowledgePickupRequest(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final request = doc.data();
    final childName = (request['childName'] ?? 'Child').toString();

    try {
      await doc.reference.update({
        'status': 'acknowledged',
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'acknowledgedByTeacherId': uid,
        'acknowledgedByTeacherName': teacherName ?? 'Teacher',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await AuditLogService.record(
        action: 'pickup_request.acknowledge',
        targetType: 'pickupRequest',
        targetId: doc.id,
        details: {'childName': childName, 'section': request['section']},
      );

      if (!context.mounted) return;
      showAppSnack(
        context,
        'Pickup request acknowledged.',
        type: AppFeedbackType.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Portal'),
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
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  InitialsAvatar(
                    name: teacherName ?? 'Teacher',
                    color: AppPalette.teal,
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          teacherName ?? 'Teacher',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppPalette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        StatusPill(
                          label: assignedSection?.isNotEmpty == true
                              ? assignedSection!
                              : 'NO SECTION',
                          color: assignedSection?.isNotEmpty == true
                              ? AppPalette.teal
                              : AppPalette.amber,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('pickupLogs')
                  .where(
                    'timestamp',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
                  )
                  .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final count = assignedSection?.isNotEmpty == true
                    ? docs.where((doc) {
                        final section = doc.data()['section'];
                        return section == null || section == assignedSection;
                      }).length
                    : docs.length;
                return AppMetricCard(
                  icon: Icons.check_circle_outline,
                  label: "Today's pickups",
                  value: '$count',
                  color: AppPalette.success,
                );
              },
            ),
            const SizedBox(height: 10),
            if (assignedSection?.isNotEmpty == true)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('pickupRequests')
                    .where('section', isEqualTo: assignedSection)
                    .snapshots(),
                builder: (context, snapshot) {
                  final requests = _activePickupRequests(
                    snapshot.data?.docs ?? [],
                  );
                  return AppMetricCard(
                    icon: Icons.notifications_active_outlined,
                    label: 'Active pickup requests',
                    value: '${requests.length}',
                    color: AppPalette.amber,
                  );
                },
              )
            else
              const AppMetricCard(
                icon: Icons.notifications_active_outlined,
                label: 'Active pickup requests',
                value: '0',
                color: AppPalette.amber,
              ),
            const SizedBox(height: 22),
            const AppSectionTitle(title: 'Daily Tools'),
            AppActionTile(
              icon: Icons.people_outline,
              title: 'Child List',
              subtitle: assignedSection?.isNotEmpty == true
                  ? 'Students in $assignedSection'
                  : 'Section assignment required',
              accentColor: AppPalette.primary,
              onTap: () => _showChildList(context),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.notifications_active_outlined,
              title: 'Pickup Requests',
              subtitle: assignedSection?.isNotEmpty == true
                  ? 'Parents and guardians on the way'
                  : 'Section assignment required',
              accentColor: AppPalette.amber,
              onTap: () => _showPickupRequests(context),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.qr_code_scanner,
              title: 'Scan QR Code',
              subtitle: 'Verify authorized pickup',
              accentColor: AppPalette.teal,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ScanQr())),
            ),
            const SizedBox(height: 10),
            AppActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'Pickup Logs',
              subtitle: "Today's release records",
              accentColor: AppPalette.amber,
              onTap: () => _showPickupLogs(context, startOfDay, endOfDay),
            ),
          ],
        ),
      ),
    );
  }

  void _showChildList(BuildContext context) {
    if (assignedSection == null || assignedSection!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No section assigned to your account.'),
          backgroundColor: AppPalette.amber,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => _TeacherSheet(
          title: '$assignedSection Student List',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('children')
                .where('section', isEqualTo: assignedSection)
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: 'Unable to load students',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.people_outline,
                  title: 'No approved students',
                );
              }

              final children = snapshot.data!.docs;
              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: children.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = children[index].data();
                  final name = (data['name'] ?? 'Unknown').toString();
                  final age = (data['age'] ?? '').toString();
                  final section = (data['section'] ?? '').toString();
                  final parentName = data['parentName']?.toString();

                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        InitialsAvatar(name: name, color: AppPalette.primary),
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
                              Text(
                                'Age $age - $section',
                                style: const TextStyle(
                                  color: AppPalette.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (parentName != null)
                                Text(
                                  'Parent: $parentName',
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
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPickupRequests(BuildContext context) {
    if (assignedSection == null || assignedSection!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No section assigned to your account.'),
          backgroundColor: AppPalette.amber,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => _TeacherSheet(
          title: 'Pickup Requests',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('pickupRequests')
                .where('section', isEqualTo: assignedSection)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: 'Unable to load pickup requests',
                  message: '${snapshot.error}',
                );
              }

              final requests = _activePickupRequests(
                snapshot.data?.docs ?? const [],
              );
              if (requests.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.notifications_none_outlined,
                  title: 'No active pickup requests',
                  message: 'Parent requests will appear here.',
                );
              }

              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = requests[index];
                  final request = doc.data();
                  final childName = (request['childName'] ?? 'Child')
                      .toString();
                  final pickupByName =
                      (request['pickupByName'] ?? 'Pickup person').toString();
                  final relation = (request['pickupByRelation'] ?? '')
                      .toString();
                  final parentName = (request['parentName'] ?? 'Parent')
                      .toString();
                  final status = (request['status'] ?? 'pending').toString();
                  final color = _pickupRequestStatusColor(status);
                  final isPending = status == 'pending';

                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppIconBox(
                              icon: Icons.directions_walk_outlined,
                              color: color,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    childName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppPalette.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _pickupLabel(pickupByName, relation),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppPalette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Requested by $parentName',
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
                            const SizedBox(width: 8),
                            StatusPill(
                              label: _formatRequestTime(request['createdAt']),
                              color: AppPalette.softText,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            StatusPill(
                              label: status.toUpperCase(),
                              color: color,
                            ),
                            const Spacer(),
                            if (isPending)
                              TextButton.icon(
                                onPressed: () =>
                                    _acknowledgePickupRequest(context, doc),
                                icon: const Icon(Icons.done_all_outlined),
                                label: const Text('Acknowledge'),
                              )
                            else
                              const StatusPill(
                                label: 'TEACHER NOTIFIED',
                                color: AppPalette.primary,
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

  void _showPickupLogs(
    BuildContext context,
    DateTime startOfDay,
    DateTime endOfDay,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => _TeacherSheet(
          title: "Today's Pickup Logs",
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('pickupLogs')
                .where(
                  'timestamp',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
                )
                .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.error_outline,
                  title: 'Unable to load pickup logs',
                  message: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No pickups recorded today',
                );
              }

              final logs = assignedSection?.isNotEmpty == true
                  ? snapshot.data!.docs.where((doc) {
                      final section = doc.data()['section'];
                      return section == null || section == assignedSection;
                    }).toList()
                  : snapshot.data!.docs;
              if (logs.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No pickups recorded for your section',
                );
              }
              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final log = logs[index].data();
                  final timestamp = log['timestamp'] as Timestamp?;
                  final time = timestamp != null
                      ? DateFormat('h:mm a').format(timestamp.toDate())
                      : 'Just now';
                  final childName = (log['childName'] ?? 'Unknown').toString();
                  final guardianName = (log['guardianName'] ?? 'Guardian')
                      .toString();
                  final relation = (log['relation'] ?? '').toString();

                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const AppIconBox(
                          icon: Icons.check_circle_outline,
                          color: AppPalette.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                childName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppPalette.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '$guardianName ($relation)',
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
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}

class _TeacherSheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _TeacherSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
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
          Expanded(child: child),
        ],
      ),
    );
  }
}
