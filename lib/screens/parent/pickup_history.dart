import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';

class PickupHistory extends StatefulWidget {
  const PickupHistory({super.key});

  @override
  State<PickupHistory> createState() => _PickupHistoryState();
}

class _PickupHistoryState extends State<PickupHistory> {
  List<Map<String, dynamic>> logs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => isLoading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final childrenSnap = await FirebaseFirestore.instance
        .collection('children')
        .where('parentId', isEqualTo: uid)
        .get();

    if (!mounted) return;

    if (childrenSnap.docs.isEmpty) {
      setState(() {
        logs = [];
        isLoading = false;
      });
      return;
    }

    final childNames = childrenSnap.docs
        .map((d) => (d.data()['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();

    final logsSnap = await FirebaseFirestore.instance
        .collection('pickupLogs')
        .orderBy('timestamp', descending: true)
        .get();

    if (!mounted) return;

    final filtered = logsSnap.docs
        .map((d) => d.data())
        .where(
          (log) =>
              log['parentId'] == uid || childNames.contains(log['childName']),
        )
        .toList();

    setState(() {
      logs = filtered;
      isLoading = false;
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Just now';
    final dt = (timestamp as Timestamp).toDate();
    return DateFormat('MMMM d, yyyy - h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup History')),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : logs.isEmpty
            ? RefreshIndicator(
                onRefresh: _loadLogs,
                child: ListView(
                  children: const [
                    SizedBox(
                      height: 420,
                      child: AppEmptyState(
                        icon: Icons.history_outlined,
                        title: 'No pickup history yet',
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadLogs,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final childName = (log['childName'] ?? 'Unknown')
                        .toString();
                    final guardianName = (log['guardianName'] ?? 'Guardian')
                        .toString();
                    final relation = (log['relation'] ?? '').toString();

                    return AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                  style: const TextStyle(
                                    color: AppPalette.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Picked up by $guardianName ($relation)',
                                  style: const TextStyle(
                                    color: AppPalette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.schedule,
                                      size: 14,
                                      color: AppPalette.softText,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        _formatTimestamp(log['timestamp']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppPalette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
