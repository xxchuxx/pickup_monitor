import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/audit_log_service.dart';
import '../../services/image_upload_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/photo_upload_field.dart';

class AddGuardian extends StatefulWidget {
  const AddGuardian({super.key});

  @override
  State<AddGuardian> createState() => _AddGuardianState();
}

class _AddGuardianState extends State<AddGuardian> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  String? selectedRelation;
  bool isLoading = false;
  String? selectedChildId;
  String? selectedChildName;
  PickedUploadImage? guardianPhoto;

  static const List<String> _relations = [
    'Mother',
    'Father',
    'Sister',
    'Brother',
    'Aunt',
    'Uncle',
    'Grandmother',
    'Grandfather',
    'Cousin',
    'Friend',
    'Guardian',
    'Other',
  ];

  Future<void> _pickGuardianPhoto() async {
    final image = await ImageUploadService.pickImage();
    if (image == null || !mounted) return;
    setState(() => guardianPhoto = image);
  }

  Future<void> saveGuardian() async {
    if (nameController.text.trim().isEmpty ||
        selectedRelation == null ||
        phoneController.text.trim().isEmpty ||
        selectedChildId == null) {
      _showSnack('Please fill in all fields and select a child', isError: true);
      return;
    }
    if (guardianPhoto == null) {
      _showSnack("Please upload the guardian's photo", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final token = const Uuid().v4();
      final photoUrl = await ImageUploadService.uploadPickedImage(
        image: guardianPhoto!,
        ownerId: uid,
        category: 'guardians',
      );

      final guardianRef = await FirebaseFirestore.instance
          .collection('guardians')
          .add({
            'name': nameController.text.trim(),
            'relation': selectedRelation,
            'phone': phoneController.text.trim(),
            'childId': selectedChildId,
            'childName': selectedChildName,
            'parentId': uid,
            'token': token,
            'photoUrl': photoUrl,
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

      await AuditLogService.record(
        action: 'guardian.create',
        targetType: 'guardian',
        targetId: guardianRef.id,
        details: {
          'name': nameController.text.trim(),
          'relation': selectedRelation,
          'childId': selectedChildId,
          'childName': selectedChildName,
        },
      );

      nameController.clear();
      phoneController.clear();

      if (!mounted) return;
      setState(() {
        selectedRelation = null;
        selectedChildId = null;
        selectedChildName = null;
        guardianPhoto = null;
      });

      _showSnack('Guardian added successfully', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppPalette.danger : AppPalette.success,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Guardian')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionTitle(
                    title: "Guardian's Information",
                    subtitle: 'Authorized guardians can be selected for pickup',
                  ),
                  PhotoUploadField(
                    title: "Guardian's photo *",
                    subtitle:
                        'Teachers use this image during pickup verification.',
                    image: guardianPhoto,
                    onPick: _pickGuardianPhoto,
                    onRemove: () => setState(() => guardianPhoto = null),
                    icon: Icons.person_outline,
                    color: AppPalette.violet,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('children')
                        .where('parentId', isEqualTo: uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: LinearProgressIndicator(),
                        );
                      }

                      final children = (snapshot.data?.docs ?? [])
                          .where(
                            (child) => child.data()['status'] == 'approved',
                          )
                          .toList();
                      if (children.isEmpty) {
                        return const InfoBanner(
                          icon: Icons.child_care_outlined,
                          message:
                              'Approved children are required before creating a guardian.',
                          color: AppPalette.amber,
                        );
                      }

                      return DropdownButtonFormField<String>(
                        key: ValueKey(selectedChildId),
                        initialValue: selectedChildId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Child',
                          prefixIcon: Icon(Icons.child_care_outlined),
                        ),
                        items: children.map((child) {
                          final data = child.data();
                          return DropdownMenuItem<String>(
                            value: child.id,
                            child: Text((data['name'] ?? 'Unknown').toString()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedChildId = value;
                            selectedChildName = children
                                .firstWhere((child) => child.id == value)
                                .data()['name']
                                ?.toString();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Guardian's full name",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedRelation),
                    initialValue: selectedRelation,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Relation',
                      prefixIcon: Icon(Icons.people_outline),
                    ),
                    items: _relations
                        .map(
                          (relation) => DropdownMenuItem(
                            value: relation,
                            child: Text(relation),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      selectedRelation = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : saveGuardian,
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(isLoading ? 'Saving' : 'Save guardian'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
