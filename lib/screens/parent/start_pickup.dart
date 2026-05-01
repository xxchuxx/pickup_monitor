import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/audit_log_service.dart';
import '../../services/image_upload_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/photo_upload_field.dart';

class StartPickup extends StatefulWidget {
  const StartPickup({super.key});

  @override
  State<StartPickup> createState() => _StartPickupState();
}

class _StartPickupState extends State<StartPickup> {
  String? selectedChildId;
  String? selectedPickupKey;
  PickedUploadImage? childVerificationPhoto;
  PickedUploadImage? pickupPersonVerificationPhoto;
  bool isSubmitting = false;

  Future<void> _pickChildVerificationPhoto() async {
    final image = await ImageUploadService.pickImage();
    if (image == null || !mounted) return;
    setState(() => childVerificationPhoto = image);
  }

  Future<void> _pickPickupPersonVerificationPhoto() async {
    final image = await ImageUploadService.pickImage();
    if (image == null || !mounted) return;
    setState(() => pickupPersonVerificationPhoto = image);
  }

  Future<void> _submitPickupRequest({
    required QueryDocumentSnapshot<Map<String, dynamic>> childDoc,
    required _PickupOption pickupOption,
  }) async {
    if (isSubmitting) return;

    setState(() => isSubmitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final firestore = FirebaseFirestore.instance;
      final child = childDoc.data();
      final childName = (child['name'] ?? 'Child').toString();
      final section = (child['section'] ?? '').toString();

      final existing = await firestore
          .collection('pickupRequests')
          .where('parentId', isEqualTo: uid)
          .get();
      final hasActiveRequest = existing.docs.any((doc) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        return data['childId'] == childDoc.id &&
            (status == 'pending' || status == 'acknowledged');
      });

      if (hasActiveRequest) {
        if (!mounted) return;
        showAppSnack(
          context,
          'There is already an active pickup request for $childName.',
          type: AppFeedbackType.warning,
        );
        return;
      }

      final parentDoc = await firestore.collection('users').doc(uid).get();
      final parent = parentDoc.data() ?? {};
      final parentName = _textOrFallback(
        parent['name'],
        _textOrFallback(child['parentName'], 'Parent'),
      );
      final parentEmail = _textOrFallback(
        parent['email'],
        _textOrFallback(
          child['parentEmail'],
          FirebaseAuth.instance.currentUser?.email ?? '',
        ),
      );
      final parentPhone = _textOrFallback(
        parent['phone'],
        (child['parentPhone'] ?? '').toString(),
      );
      final storedParentPhotoUrl = _firstString(parent, _photoKeys);
      final parentPhotoUrl = storedParentPhotoUrl.isNotEmpty
          ? storedParentPhotoUrl
          : (FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();

      var childPhotoUrl = _firstString(child, _photoKeys);
      if (childPhotoUrl.isEmpty && childVerificationPhoto != null) {
        childPhotoUrl = await ImageUploadService.uploadPickedImage(
          image: childVerificationPhoto!,
          ownerId: uid,
          category: 'children',
        );
        await childDoc.reference.update({
          'photoUrl': childPhotoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (childPhotoUrl.isEmpty) {
        if (!mounted) return;
        showAppSnack(
          context,
          "Please upload the child's photo for verification.",
          type: AppFeedbackType.warning,
        );
        return;
      }

      var pickupByPhotoUrl = pickupOption.photoUrl.isNotEmpty
          ? pickupOption.photoUrl
          : pickupOption.type == 'parent'
          ? parentPhotoUrl
          : '';
      if (pickupByPhotoUrl.isEmpty && pickupPersonVerificationPhoto != null) {
        pickupByPhotoUrl = await ImageUploadService.uploadPickedImage(
          image: pickupPersonVerificationPhoto!,
          ownerId: uid,
          category: 'pickup_people',
        );
        if (pickupOption.guardianId != null) {
          await firestore
              .collection('guardians')
              .doc(pickupOption.guardianId)
              .update({
                'photoUrl': pickupByPhotoUrl,
                'updatedAt': FieldValue.serverTimestamp(),
              });
        } else if (pickupOption.type == 'parent') {
          await firestore.collection('users').doc(uid).update({
            'photoUrl': pickupByPhotoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (pickupByPhotoUrl.isEmpty) {
        if (!mounted) return;
        showAppSnack(
          context,
          "Please upload the pickup person's photo for verification.",
          type: AppFeedbackType.warning,
        );
        return;
      }

      final requestRef = await firestore.collection('pickupRequests').add({
        'parentId': uid,
        'parentName': parentName,
        'parentEmail': parentEmail,
        'parentPhone': parentPhone,
        'childId': childDoc.id,
        'childName': childName,
        'section': section,
        'pickupByType': pickupOption.type,
        'pickupByName': pickupOption.name,
        'pickupByRelation': pickupOption.relation,
        if (pickupOption.guardianId != null)
          'guardianId': pickupOption.guardianId,
        if (pickupOption.phone.isNotEmpty) 'pickupByPhone': pickupOption.phone,
        if (pickupByPhotoUrl.isNotEmpty) 'pickupByPhotoUrl': pickupByPhotoUrl,
        if (childPhotoUrl.isNotEmpty) 'childPhotoUrl': childPhotoUrl,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await AuditLogService.record(
        action: 'pickup_request.create',
        targetType: 'pickupRequest',
        targetId: requestRef.id,
        details: {
          'childId': childDoc.id,
          'childName': childName,
          'section': section,
          'pickupByName': pickupOption.name,
          'pickupByType': pickupOption.type,
        },
      );

      if (!mounted) return;
      setState(() {
        childVerificationPhoto = null;
        pickupPersonVerificationPhoto = null;
      });
      showAppSnack(
        context,
        'Teacher notified for $childName.',
        type: AppFeedbackType.success,
      );
    } on ImageUploadException catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.message, type: AppFeedbackType.error);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _cancelRequest(
    BuildContext context,
    String requestId,
    String childName,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Cancel pickup request',
      message: 'Cancel the active pickup request for $childName?',
      confirmLabel: 'Cancel request',
      type: AppFeedbackType.warning,
    );
    if (!confirmed) return;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('pickupRequests')
          .doc(requestId)
          .update({
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
            'cancelledBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await AuditLogService.record(
        action: 'pickup_request.cancel',
        targetType: 'pickupRequest',
        targetId: requestId,
        details: {'childName': childName},
      );

      if (!context.mounted) return;
      showAppSnack(
        context,
        'Pickup request cancelled.',
        type: AppFeedbackType.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
    }
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _selectedChild(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> children,
  ) {
    for (final child in children) {
      if (child.id == selectedChildId) return child;
    }
    return null;
  }

  _PickupOption? _optionForKey(List<_PickupOption> options, String? key) {
    if (key == null) return null;
    for (final option in options) {
      if (option.key == key) return option;
    }
    return null;
  }

  String _textOrFallback(dynamic value, String fallback) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  List<String> get _photoKeys => const [
    'photoUrl',
    'imageUrl',
    'profilePhotoUrl',
    'pictureUrl',
    'avatarUrl',
  ];

  String _pickupLabel(String name, String relation) {
    final cleanRelation = relation.trim();
    return cleanRelation.isEmpty ? name : '$name ($cleanRelation)';
  }

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => AppPalette.amber,
      'acknowledged' => AppPalette.primary,
      'completed' => AppPalette.success,
      'cancelled' => AppPalette.muted,
      _ => AppPalette.softText,
    };
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('MMM d, h:mm a').format(timestamp.toDate());
    }
    return 'Just now';
  }

  String _requestQrData(String requestId) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'pickup_request|$requestId|$today';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Start Pickup')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('children')
              .where('parentId', isEqualTo: uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return AppEmptyState(
                icon: Icons.error_outline,
                title: 'Unable to load children',
                message: '${snapshot.error}',
              );
            }

            final children =
                (snapshot.data?.docs ?? const [])
                    .where((doc) => doc.data()['status'] == 'approved')
                    .toList()
                  ..sort((a, b) {
                    final aName = (a.data()['name'] ?? '').toString();
                    final bName = (b.data()['name'] ?? '').toString();
                    return aName.compareTo(bName);
                  });

            if (children.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.child_care_outlined,
                    title: 'No approved children yet',
                    message:
                        'Only approved children registered to your account can start a pickup request.',
                  ),
                ],
              );
            }

            final currentChildId =
                children.any((child) => child.id == selectedChildId)
                ? selectedChildId
                : null;
            final childDoc = _selectedChild(children);
            final childData = childDoc?.data();
            final parentName = _textOrFallback(
              childData?['parentName'],
              FirebaseAuth.instance.currentUser?.email ?? 'Parent',
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const InfoBanner(
                  icon: Icons.notifications_active_outlined,
                  message:
                      'Submitting a pickup request shows the teacher who is coming for your child.',
                  color: AppPalette.primary,
                ),
                const SizedBox(height: 14),
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionTitle(
                        title: 'Pickup Details',
                        subtitle: 'Choose a registered child and pickup person',
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(currentChildId),
                        initialValue: currentChildId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Child',
                          prefixIcon: Icon(Icons.child_care_outlined),
                        ),
                        items: children.map((child) {
                          final data = child.data();
                          final name = (data['name'] ?? 'Unknown').toString();
                          final section = (data['section'] ?? '').toString();
                          return DropdownMenuItem(
                            value: child.id,
                            child: Text(
                              section.isEmpty ? name : '$name - $section',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedChildId = value;
                            selectedPickupKey = null;
                            childVerificationPhoto = null;
                            pickupPersonVerificationPhoto = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (childDoc == null)
                        const InfoBanner(
                          icon: Icons.touch_app_outlined,
                          message: 'Select a child to choose a pickup person.',
                          color: AppPalette.amber,
                        )
                      else
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('guardians')
                              .where('parentId', isEqualTo: uid)
                              .snapshots(),
                          builder: (context, guardianSnapshot) {
                            if (guardianSnapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !guardianSnapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: LinearProgressIndicator(),
                              );
                            }

                            if (guardianSnapshot.hasError) {
                              return InfoBanner(
                                icon: Icons.error_outline,
                                message:
                                    'Unable to load pickup options: ${guardianSnapshot.error}',
                                color: AppPalette.danger,
                              );
                            }

                            final guardians =
                                (guardianSnapshot.data?.docs ?? const [])
                                    .where((doc) {
                                      final data = doc.data();
                                      return data['childId'] == childDoc.id &&
                                          data['active'] == true &&
                                          data['revokedByAdmin'] != true;
                                    })
                                    .map((doc) {
                                      final data = doc.data();
                                      return _PickupOption(
                                        type: 'guardian',
                                        name: (data['name'] ?? 'Guardian')
                                            .toString(),
                                        relation:
                                            (data['relation'] ?? 'Guardian')
                                                .toString(),
                                        phone: (data['phone'] ?? '').toString(),
                                        photoUrl: _firstString(
                                          data,
                                          _photoKeys,
                                        ),
                                        guardianId: doc.id,
                                      );
                                    })
                                    .toList()
                                  ..sort((a, b) => a.name.compareTo(b.name));
                            final options = [
                              _PickupOption(
                                type: 'parent',
                                name: parentName,
                                relation: 'Parent',
                              ),
                              ...guardians,
                            ];
                            final currentPickupKey =
                                options.any(
                                  (option) => option.key == selectedPickupKey,
                                )
                                ? selectedPickupKey
                                : null;
                            final selectedOption = _optionForKey(
                              options,
                              currentPickupKey,
                            );
                            final childHasPhoto = _firstString(
                              childDoc.data(),
                              _photoKeys,
                            ).isNotEmpty;
                            final selectedOptionHasPhoto =
                                selectedOption?.photoUrl.isNotEmpty == true;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    '${childDoc.id}-$currentPickupKey',
                                  ),
                                  initialValue: currentPickupKey,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Pickup person',
                                    prefixIcon: Icon(
                                      Icons.person_pin_circle_outlined,
                                    ),
                                  ),
                                  items: options.map((option) {
                                    return DropdownMenuItem(
                                      value: option.key,
                                      child: Text(
                                        _pickupLabel(
                                          option.name,
                                          option.relation,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedPickupKey = value;
                                      pickupPersonVerificationPhoto = null;
                                    });
                                  },
                                ),
                                if (!childHasPhoto) ...[
                                  const SizedBox(height: 10),
                                  PhotoUploadField(
                                    title: "Child's photo required",
                                    subtitle:
                                        'Upload a child photo for teacher verification.',
                                    image: childVerificationPhoto,
                                    onPick: _pickChildVerificationPhoto,
                                    onRemove: () => setState(
                                      () => childVerificationPhoto = null,
                                    ),
                                    icon: Icons.child_care_outlined,
                                    color: AppPalette.teal,
                                  ),
                                ],
                                if (selectedOption != null &&
                                    !selectedOptionHasPhoto) ...[
                                  const SizedBox(height: 10),
                                  PhotoUploadField(
                                    title: "Pickup person's photo required",
                                    subtitle:
                                        'Upload the listed pickup person for QR verification.',
                                    image: pickupPersonVerificationPhoto,
                                    onPick: _pickPickupPersonVerificationPhoto,
                                    onRemove: () => setState(
                                      () =>
                                          pickupPersonVerificationPhoto = null,
                                    ),
                                    icon: Icons.person_pin_circle_outlined,
                                    color: AppPalette.violet,
                                  ),
                                ],
                                if (guardians.isEmpty) ...[
                                  const SizedBox(height: 10),
                                  const InfoBanner(
                                    icon: Icons.info_outline,
                                    message:
                                        'No active guardians are registered for this child. You can still choose yourself.',
                                    color: AppPalette.teal,
                                  ),
                                ],
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        isSubmitting || selectedOption == null
                                        ? null
                                        : () => _submitPickupRequest(
                                            childDoc: childDoc,
                                            pickupOption: selectedOption,
                                          ),
                                    icon: isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.notifications_active_outlined,
                                          ),
                                    label: Text(
                                      isSubmitting
                                          ? 'Notifying teacher'
                                          : 'Notify teacher',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const AppSectionTitle(title: 'Recent Requests'),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('pickupRequests')
                      .where('parentId', isEqualTo: uid)
                      .snapshots(),
                  builder: (context, requestSnapshot) {
                    if (requestSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !requestSnapshot.hasData) {
                      return const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (requestSnapshot.hasError) {
                      return AppEmptyState(
                        icon: Icons.error_outline,
                        title: 'Unable to load requests',
                        message: '${requestSnapshot.error}',
                      );
                    }

                    final requests =
                        (requestSnapshot.data?.docs ?? const []).toList()
                          ..sort((a, b) {
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

                    if (requests.isEmpty) {
                      return const SizedBox(
                        height: 170,
                        child: AppEmptyState(
                          icon: Icons.directions_walk_outlined,
                          title: 'No pickup requests yet',
                        ),
                      );
                    }

                    return Column(
                      children: requests.take(8).map((doc) {
                        final request = doc.data();
                        final childName = (request['childName'] ?? 'Child')
                            .toString();
                        final pickupByName =
                            (request['pickupByName'] ?? 'Pickup person')
                                .toString();
                        final relation = (request['pickupByRelation'] ?? '')
                            .toString();
                        final status = (request['status'] ?? 'pending')
                            .toString();
                        final isActive =
                            status == 'pending' || status == 'acknowledged';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppIconBox(
                                      icon: Icons.directions_walk_outlined,
                                      color: _statusColor(status),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                            _pickupLabel(
                                              pickupByName,
                                              relation,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppPalette.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              StatusPill(
                                                label: status.toUpperCase(),
                                                color: _statusColor(status),
                                              ),
                                              StatusPill(
                                                label: _formatTimestamp(
                                                  request['createdAt'],
                                                ),
                                                color: AppPalette.softText,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isActive)
                                      IconButton(
                                        tooltip: 'Cancel request',
                                        onPressed: () => _cancelRequest(
                                          context,
                                          doc.id,
                                          childName,
                                        ),
                                        icon: const Icon(Icons.close),
                                        color: AppPalette.danger,
                                      ),
                                  ],
                                ),
                                if (isActive) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppPalette.border,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'Pickup QR Pass',
                                          style: TextStyle(
                                            color: AppPalette.ink,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        QrImageView(
                                          data: _requestQrData(doc.id),
                                          size: 190,
                                        ),
                                        const SizedBox(height: 8),
                                        StatusPill(
                                          label: DateFormat(
                                            'MMM d, yyyy',
                                          ).format(DateTime.now()),
                                          color: AppPalette.amber,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PickupOption {
  final String type;
  final String name;
  final String relation;
  final String phone;
  final String photoUrl;
  final String? guardianId;

  const _PickupOption({
    required this.type,
    required this.name,
    required this.relation,
    this.phone = '',
    this.photoUrl = '',
    this.guardianId,
  });

  String get key => '$type:${guardianId ?? 'self'}';
}
