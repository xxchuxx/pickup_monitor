import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

class AddGuardian extends StatefulWidget {
  const AddGuardian({super.key});

  @override
  State<AddGuardian> createState() => _AddGuardianState();
}

class _AddGuardianState extends State<AddGuardian> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  String? selectedRelation; // ← replaces relationController
  String? generatedToken;
  bool isLoading = false;
  String? selectedChildId;
  String? selectedChildName;

  static const List<String> _relations = [
    'Mother', 'Father', 'Sister', 'Brother',
    'Aunt', 'Uncle', 'Grandmother', 'Grandfather',
    'Cousin', 'Friend', 'Guardian', 'Other',
  ];

  Future<void> saveGuardian() async {
    if (nameController.text.isEmpty ||
        selectedRelation == null ||       // ← updated check
        phoneController.text.isEmpty ||
        selectedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields and select a child')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final token = const Uuid().v4();

      await FirebaseFirestore.instance.collection('guardians').add({
        'name': nameController.text.trim(),
        'relation': selectedRelation,      // ← updated
        'phone': phoneController.text.trim(),
        'childId': selectedChildId,
        'childName': selectedChildName,
        'parentId': uid,
        'token': token,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        generatedToken = token;
        selectedRelation = null;           // ← clear on success
      });
      nameController.clear();
      phoneController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardian added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF5B7FD4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A6BC0),
        title: const Text('Add Guardian',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Guardian's Information",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  // Child selector
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('children')
                        .where('parentId', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const CircularProgressIndicator();
                      final children = snapshot.data!.docs;
                      if (children.isEmpty) {
                        return const Text(
                          'No children found. Please add a child first.',
                          style: TextStyle(color: Colors.red),
                        );
                      }
                      return DropdownButtonFormField<String>(
                        value: selectedChildId,
                        hint: const Text('Select Child'),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.child_care),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        items: children.map((child) {
                          return DropdownMenuItem<String>(
                            value: child.id,
                            child: Text(child['name']),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedChildId = value;
                            selectedChildName =
                                children.firstWhere((c) => c.id == value)['name'];
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: "Guardian's Full Name",
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ↓ Relation dropdown
                  DropdownButtonFormField<String>(
                    value: selectedRelation,
                    decoration: InputDecoration(
                      labelText: 'Relation',
                      prefixIcon: const Icon(Icons.people),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _relations
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedRelation = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : saveGuardian,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A6BC0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Generate QR Code',
                              style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
            if (generatedToken != null) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text('QR Code Generated!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green)),
                    const SizedBox(height: 8),
                    const Text('Share this QR code with the guardian.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 16),
                    QrImageView(data: generatedToken!, size: 200),
                    const SizedBox(height: 12),
                    const Text('Guardian saves screenshot of this QR.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}