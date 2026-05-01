import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

class ViewQrCodes extends StatelessWidget {
  const ViewQrCodes({super.key});

  String _getDailyToken(String token) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return '$token|$today';
  }

  void _showQrDialog(BuildContext context, Map<String, dynamic> g) {
    final dailyToken = _getDailyToken(g['token']);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(g['name'],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              Text('${g['relation']} · ${g['childName']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Valid today: ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              QrImageView(data: dailyToken, size: 280),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF5B7FD4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A6BC0),
        title: const Text('View QR Codes',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('guardians')
            .where('parentId', isEqualTo: uid)
            .where('active', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No guardians added yet.',
                  style: TextStyle(color: Colors.white)),
            );
          }

          final guardians = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: guardians.length,
            itemBuilder: (context, index) {
              final g = guardians[index].data() as Map<String, dynamic>;
              final dailyToken = _getDailyToken(g['token']);

              return GestureDetector(
                onTap: () => _showQrDialog(context, g),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person,
                              color: Color(0xFF4A6BC0), size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g['name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text('${g['relation']} · ${g['childName']}',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.fullscreen,
                              color: Colors.grey, size: 20),
                        ],
                      ),
                      const Divider(height: 24),
                      QrImageView(data: dailyToken, size: 180),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_clock,
                              size: 12, color: Colors.orange),
                          const SizedBox(width: 4),
                          const Text(
                            'Valid today only · Tap to enlarge',
                            style: TextStyle(
                                color: Colors.orange, fontSize: 11),
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