import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PendingApprovals extends StatelessWidget {
  const PendingApprovals({super.key});

  Future<void> approveChild(String docId) async {
    await FirebaseFirestore.instance
        .collection('children')
        .doc(docId)
        .update({
      'status': 'approved',
    });
  }

  Future<void> rejectChild(String docId) async {
    await FirebaseFirestore.instance
        .collection('children')
        .doc(docId)
        .update({
      'status': 'rejected',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Approvals"),
        backgroundColor: const Color(0xFF5B7FD4),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('children')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          /// Show exact Firestore error
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  "Error: ${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }

          /// Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          /// No pending approvals
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "No pending approvals",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          /// Show pending children
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data =
                  docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Child Name: ${data['name'] ?? ''}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text("Age: ${data['age'] ?? ''}"),
                      Text("Section: ${data['section'] ?? ''}"),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          /// Approve Button
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  approveChild(docId),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.green,
                                foregroundColor:
                                    Colors.white,
                              ),
                              child:
                                  const Text("Approve"),
                            ),
                          ),

                          const SizedBox(width: 10),

                          /// Reject Button
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  rejectChild(docId),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.red,
                                foregroundColor:
                                    Colors.white,
                              ),
                              child:
                                  const Text("Reject"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}