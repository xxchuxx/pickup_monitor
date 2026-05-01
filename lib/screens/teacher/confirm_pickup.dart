import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/pickup_flow_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';

class ConfirmPickup extends StatelessWidget {
  final String guardianId;
  final String guardianName;
  final String relation;
  final String childName;
  final String parentId;
  final String childId;
  final String? section;
  final String? guardianPhotoUrl;
  final String? childPhotoUrl;

  const ConfirmPickup({
    super.key,
    required this.guardianId,
    required this.guardianName,
    required this.relation,
    required this.childName,
    required this.parentId,
    required this.childId,
    this.section,
    this.guardianPhotoUrl,
    this.childPhotoUrl,
  });

  Future<void> _releaseChild(BuildContext context) async {
    final confirmed = await _showReleasePreviewDialog(context);

    if (!confirmed) return;

    try {
      await PickupFlowService.releaseChild(
        guardianId: guardianId,
        guardianName: guardianName,
        relation: relation,
        childId: childId,
        childName: childName,
        parentId: parentId,
        section: section,
      );

      if (!context.mounted) return;
      showAppSnack(
        context,
        'Child released successfully',
        type: AppFeedbackType.success,
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    } on PickupFlowException catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, e.message, type: AppFeedbackType.warning);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
    }
  }

  Future<bool> _showReleasePreviewDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Final release check'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const InfoBanner(
                icon: Icons.verified_user_outlined,
                message:
                    'Verify the pickup person and child before completing the release.',
                color: AppPalette.success,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _ReleaseIdentityCard(
                    label: 'Pickup person',
                    name: guardianName,
                    subtitle: relation,
                    photoUrl: guardianPhotoUrl,
                    color: AppPalette.primary,
                    icon: Icons.person_pin_circle_outlined,
                  ),
                  _ReleaseIdentityCard(
                    label: 'Child',
                    name: childName,
                    subtitle: section?.isNotEmpty == true
                        ? section!
                        : 'Student',
                    photoUrl: childPhotoUrl,
                    color: AppPalette.teal,
                    icon: Icons.child_care_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.success,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Release child'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Pickup')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AppConstrained(
              maxWidth: 520,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        const AppIconBox(
                          icon: Icons.verified_user_outlined,
                          color: AppPalette.success,
                          size: 64,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Authorized Pickup',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppPalette.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const StatusPill(
                          label: 'VERIFIED',
                          color: AppPalette.success,
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          alignment: WrapAlignment.center,
                          children: [
                            _ReleaseIdentityCard(
                              label: 'Pickup person',
                              name: guardianName,
                              subtitle: relation,
                              photoUrl: guardianPhotoUrl,
                              color: AppPalette.primary,
                              icon: Icons.person_pin_circle_outlined,
                            ),
                            _ReleaseIdentityCard(
                              label: 'Child',
                              name: childName,
                              subtitle: section?.isNotEmpty == true
                                  ? section!
                                  : 'Student',
                              photoUrl: childPhotoUrl,
                              color: AppPalette.teal,
                              icon: Icons.child_care_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _releaseChild(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.success,
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Release child'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseIdentityCard extends StatelessWidget {
  final String label;
  final String name;
  final String subtitle;
  final String? photoUrl;
  final Color color;
  final IconData icon;

  const _ReleaseIdentityCard({
    required this.label,
    required this.name,
    required this.subtitle,
    required this.photoUrl,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _ReleasePhoto(
            name: name,
            photoUrl: photoUrl,
            color: color,
            icon: icon,
          ),
          const SizedBox(height: 10),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppPalette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReleasePhoto extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final Color color;
  final IconData icon;

  const _ReleasePhoto({
    required this.name,
    required this.photoUrl,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = (photoUrl ?? '').trim();
    final inlineBytes = _inlineImageBytes(cleanUrl);

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: cleanUrl.isEmpty
          ? _PhotoFallback(name: name, icon: icon, color: color)
          : inlineBytes != null
          ? Image.memory(
              inlineBytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _PhotoFallback(name: name, icon: icon, color: color),
            )
          : Image.network(
              cleanUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _PhotoFallback(name: name, icon: icon, color: color),
            ),
    );
  }

  Uint8List? _inlineImageBytes(String url) {
    final match = RegExp(
      r'^data:image/[^;]+;base64,(.+)$',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;

    try {
      return base64Decode(match.group(1)!);
    } on FormatException {
      return null;
    }
  }
}

class _PhotoFallback extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;

  const _PhotoFallback({
    required this.name,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        InitialsAvatar(name: name, color: color, radius: 32),
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.border),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ],
    );
  }
}
