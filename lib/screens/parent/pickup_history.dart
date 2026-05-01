import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Step 1: get this parent's children names
    final childrenSnap = await FirebaseFirestore.instance
        .collection('children')
        .where('parentId', isEqualTo: uid)
        .get();

    if (childrenSnap.docs.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    final childNames = childrenSnap.docs.map((d) => d['name'] as String).toList();

    // Step 2: get pickup logs where childName is in that list
    final logsSnap = await FirebaseFirestore.instance
        .collection('pickupLogs')
        .orderBy('timestamp', descending: true)
        .get();

    final filtered = logsSnap.docs
        .where((d) => childNames.contains(d['childName']))
        .map((d) => d.data())
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
      backgroundColor: const Color(0xFF5B7FD4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A6BC0),
        title: const Text('Pickup History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : logs.isEmpty
              ? const Center(
                  child: Text('No pickup history yet.',
                      style: TextStyle(color: Colors.white)),
                )
              : RefreshIndicator(
                  onRefresh: _loadLogs,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check_circle,
                                  color: Colors.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(log['childName'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Picked up by: ${log['guardianName']} (${log['relation']})',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time,
                                          size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTimestamp(log['timestamp']),
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 12),
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
    );
  }
}