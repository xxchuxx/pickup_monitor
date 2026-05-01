import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/audit_log_service.dart';
import '../../services/image_upload_service.dart';
import '../../services/section_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/photo_upload_field.dart';

class AddChild extends StatefulWidget {
  const AddChild({super.key});

  @override
  State<AddChild> createState() => _AddChildState();
}

class _AddChildState extends State<AddChild> {
  final nameController = TextEditingController();
  final ageController = TextEditingController();

  String? selectedSection;
  PickedUploadImage? childPhoto;
  bool isLoading = false;

  Future<void> _pickChildPhoto() async {
    final image = await ImageUploadService.pickImage();
    if (image == null || !mounted) return;
    setState(() => childPhoto = image);
  }

  Future<void> saveChild() async {
    if (nameController.text.trim().isEmpty ||
        ageController.text.trim().isEmpty ||
        selectedSection == null) {
      _showSnack('Please fill in all fields', isError: true);
      return;
    }
    if (childPhoto == null) {
      _showSnack("Please upload the child's photo", isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final parentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final parentData = parentDoc.data() ?? {};
      final photoUrl = await ImageUploadService.uploadPickedImage(
        image: childPhoto!,
        ownerId: uid,
        category: 'children',
      );

      final childRef = await FirebaseFirestore.instance
          .collection('children')
          .add({
            'name': nameController.text.trim(),
            'age': ageController.text.trim(),
            'section': selectedSection,
            'parentId': uid,
            'parentName': parentData['name'] ?? '',
            'parentEmail': parentData['email'] ?? '',
            'parentPhone': parentData['phone'] ?? '',
            'photoUrl': photoUrl,
            'status': 'pending',
            'createdAt': Timestamp.now(),
          });

      await AuditLogService.record(
        action: 'child.submit',
        targetType: 'child',
        targetId: childRef.id,
        details: {
          'name': nameController.text.trim(),
          'section': selectedSection,
        },
      );

      nameController.clear();
      ageController.clear();

      if (!mounted) return;
      setState(() {
        selectedSection = null;
        childPhoto = null;
      });
      _showSnack('Child submitted for approval', isError: false);
    } on ImageUploadException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, isError: true);
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
    ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Child')),
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
                    title: "Child's Information",
                    subtitle: 'New children remain pending until approved',
                  ),
                  PhotoUploadField(
                    title: "Child's photo *",
                    subtitle:
                        'This appears during teacher pickup verification.',
                    image: childPhoto,
                    onPick: _pickChildPhoto,
                    onRemove: () => setState(() => childPhoto = null),
                    icon: Icons.child_care_outlined,
                    color: AppPalette.teal,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Child's full name",
                      prefixIcon: Icon(Icons.child_care_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: SectionService.streamSections(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const SizedBox(
                          height: 56,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return InfoBanner(
                          icon: Icons.error_outline,
                          message: 'Unable to load sections: ${snapshot.error}',
                          color: AppPalette.danger,
                        );
                      }

                      final sections = SectionService.sectionNamesFromDocs(
                        snapshot.data?.docs ?? const [],
                      );
                      final currentValue = sections.contains(selectedSection)
                          ? selectedSection
                          : null;

                      return DropdownButtonFormField<String>(
                        key: ValueKey(currentValue),
                        initialValue: currentValue,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Section',
                          prefixIcon: Icon(Icons.class_outlined),
                        ),
                        items: sections
                            .map(
                              (section) => DropdownMenuItem(
                                value: section,
                                child: Text(section),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          selectedSection = value;
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : saveChild,
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        isLoading ? 'Submitting' : 'Submit for approval',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const AppSectionTitle(title: 'My Children'),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('children')
                  .where('parentId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: Icons.error_outline,
                    title: 'Unable to load children',
                    message: '${snapshot.error}',
                  );
                }

                final children = snapshot.data?.docs ?? [];

                if (children.isEmpty) {
                  return const SizedBox(
                    height: 180,
                    child: AppEmptyState(
                      icon: Icons.child_care_outlined,
                      title: 'No children added yet',
                    ),
                  );
                }

                return Column(
                  children: children.map((child) {
                    final data = child.data();
                    final name = (data['name'] ?? 'Unknown').toString();
                    final age = (data['age'] ?? '').toString();
                    final section = (data['section'] ?? '').toString();
                    final status = (data['status'] ?? 'pending').toString();
                    final color = _statusColor(status);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            InitialsAvatar(
                              name: name,
                              color: AppPalette.primary,
                            ),
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
                            StatusPill(
                              label: status.toUpperCase(),
                              color: color,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    if (status == 'approved') return AppPalette.success;
    if (status == 'rejected') return AppPalette.danger;
    return AppPalette.amber;
  }
}
