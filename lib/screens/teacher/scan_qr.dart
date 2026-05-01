import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/pickup_flow_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_components.dart';
import 'confirm_pickup.dart';

class ScanQr extends StatefulWidget {
  const ScanQr({super.key});

  @override
  State<ScanQr> createState() => _ScanQrState();
}

class _ScanQrState extends State<ScanQr> {
  bool isProcessing = false;
  bool isTorchOn = false;
  final MobileScannerController cameraController = MobileScannerController();

  Future<void> handleScan(String scannedData) async {
    if (isProcessing) return;
    setState(() => isProcessing = true);

    final parts = scannedData.split('|');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (parts.length == 3 && parts[0] == 'pickup_request') {
      await _handlePickupRequestScan(parts[1], parts[2], today);
      return;
    }

    if (parts.length == 2) {
      await _handleGuardianTokenScan(parts[0], parts[1], today);
      return;
    }

    _showError('Invalid QR code.');
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

  Future<void> _handlePickupRequestScan(
    String requestId,
    String scannedDate,
    String today,
  ) async {
    if (scannedDate != today) {
      _showError('This pickup request has expired.');
      return;
    }

    try {
      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      if (teacherId == null) {
        _showError('Please sign in again before scanning.');
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final teacherDoc = await firestore
          .collection('users')
          .doc(teacherId)
          .get();
      if (!mounted) return;

      final assignedSection = (teacherDoc.data()?['assignedSection'] ?? '')
          .toString();
      if (assignedSection.isEmpty) {
        _showError('No section is assigned to your account.');
        return;
      }

      final requestDoc = await firestore
          .collection('pickupRequests')
          .doc(requestId)
          .get();
      if (!mounted) return;

      if (!requestDoc.exists) {
        _showError('Pickup request not found.');
        return;
      }

      final request = requestDoc.data() ?? {};
      final requestSection = (request['section'] ?? '').toString();
      if (requestSection != assignedSection) {
        _showError('This pickup request is for another section.');
        return;
      }

      final status = (request['status'] ?? '').toString();
      if (status != 'pending' && status != 'acknowledged') {
        _showError('This pickup request is no longer active.');
        return;
      }

      final childId = request['childId']?.toString();
      final parentId = request['parentId']?.toString();
      if (childId == null || childId.isEmpty) {
        _showError('This pickup request is missing child information.');
        return;
      }
      if (parentId == null || parentId.isEmpty) {
        _showError('This pickup request is missing parent information.');
        return;
      }

      final childDoc = await firestore
          .collection('children')
          .doc(childId)
          .get();
      if (!mounted) return;

      final child = childDoc.data() ?? {};
      if (!childDoc.exists || child['status'] != 'approved') {
        _showError('This child is not approved for pickup yet.');
        return;
      }

      if ((child['section'] ?? '').toString() != requestSection) {
        _showError('This pickup request does not match the child section.');
        return;
      }

      final pickupType = (request['pickupByType'] ?? 'parent').toString();
      var pickupIdentityId = 'pickup_request_$requestId';
      var pickupName = (request['pickupByName'] ?? 'Pickup person').toString();
      var relation = (request['pickupByRelation'] ?? 'Parent').toString();
      var pickupPhotoUrl = _firstString(request, [
        'pickupByPhotoUrl',
        'guardianPhotoUrl',
        'parentPhotoUrl',
      ]);
      final childPhotoUrlFromRequest = _firstString(request, [
        'childPhotoUrl',
        'childImageUrl',
        'childProfilePhotoUrl',
        'childPictureUrl',
      ]);

      if (pickupType == 'guardian') {
        final guardianId = request['guardianId']?.toString();
        if (guardianId == null || guardianId.isEmpty) {
          _showError('This pickup request is missing guardian information.');
          return;
        }

        final guardianDoc = await firestore
            .collection('guardians')
            .doc(guardianId)
            .get();
        if (!mounted) return;

        final guardian = guardianDoc.data() ?? {};
        if (!guardianDoc.exists ||
            guardian['active'] != true ||
            guardian['revokedByAdmin'] == true ||
            guardian['childId'] != childId ||
            guardian['parentId'] != parentId) {
          _showError('This guardian is not authorized for this child.');
          return;
        }

        pickupIdentityId = guardianId;
        pickupName = (guardian['name'] ?? pickupName).toString();
        relation = (guardian['relation'] ?? relation).toString();
        pickupPhotoUrl = _firstString(guardian, _photoKeys);
      }

      try {
        await PickupFlowService.assertCanRelease(
          childId: childId,
          guardianId: pickupIdentityId,
        );
      } on PickupFlowException catch (e) {
        if (!mounted) return;
        _showError(e.message);
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfirmPickup(
            guardianId: pickupIdentityId,
            guardianName: pickupName,
            relation: relation,
            childName: (request['childName'] ?? child['name'] ?? 'Child')
                .toString(),
            parentId: parentId,
            childId: childId,
            section: requestSection,
            guardianPhotoUrl: pickupPhotoUrl,
            childPhotoUrl: childPhotoUrlFromRequest.isNotEmpty
                ? childPhotoUrlFromRequest
                : _firstString(child, _photoKeys),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
      setState(() => isProcessing = false);
    }
  }

  Future<void> _handleGuardianTokenScan(
    String scannedToken,
    String scannedDate,
    String today,
  ) async {
    if (scannedDate != today) {
      _showError('This QR code has expired.');
      return;
    }

    try {
      final result = await FirebaseFirestore.instance
          .collection('guardians')
          .where('token', isEqualTo: scannedToken)
          .where('active', isEqualTo: true)
          .get();

      if (!mounted) return;

      if (result.docs.isEmpty) {
        _showError('This person is not on the authorized pickup list.');
        return;
      }

      final guardian = result.docs.first.data();
      final guardianId = result.docs.first.id;
      final childId = guardian['childId']?.toString();
      final parentId = guardian['parentId']?.toString();

      if (guardian['revokedByAdmin'] == true) {
        _showError('This guardian access was removed by an admin.');
        return;
      }

      if (parentId == null || parentId.isEmpty) {
        _showError('This guardian record is missing parent information.');
        return;
      }

      if (childId == null || childId.isEmpty) {
        _showError('This guardian record is missing child information.');
        return;
      }

      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(childId)
          .get();
      final child = childDoc.data() ?? {};

      if (child['status'] != 'approved') {
        if (!mounted) return;
        _showError('This child is not approved for pickup yet.');
        return;
      }

      try {
        await PickupFlowService.assertCanRelease(
          childId: childId,
          guardianId: guardianId,
        );
      } on PickupFlowException catch (e) {
        if (!mounted) return;
        _showError(e.message);
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfirmPickup(
            guardianId: guardianId,
            guardianName: (guardian['name'] ?? 'Guardian').toString(),
            relation: (guardian['relation'] ?? '').toString(),
            childName: (guardian['childName'] ?? '').toString(),
            parentId: parentId,
            childId: childId,
            section: child['section']?.toString(),
            guardianPhotoUrl: _firstString(guardian, _photoKeys),
            childPhotoUrl: _firstString(child, _photoKeys),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Error: $e', type: AppFeedbackType.error);
      setState(() => isProcessing = false);
    }
  }

  Future<void> _toggleTorch() async {
    await cameraController.toggleTorch();
    if (!mounted) return;
    setState(() => isTorchOn = !isTorchOn);
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppPalette.danger),
            SizedBox(width: 8),
            Text('Not Authorized'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) setState(() => isProcessing = false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pickup QR')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AppIconBox(
                    icon: isProcessing
                        ? Icons.hourglass_top
                        : Icons.qr_code_scanner,
                    color: isProcessing ? AppPalette.amber : AppPalette.teal,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isProcessing ? 'Checking QR code' : 'Ready to scan',
                          style: const TextStyle(
                            color: AppPalette.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Pickup request verification',
                          style: TextStyle(
                            color: AppPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isTorchOn ? 'Turn flash off' : 'Turn flash on',
                    onPressed: _toggleTorch,
                    icon: Icon(
                      isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: isTorchOn ? AppPalette.amber : AppPalette.muted,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Switch camera',
                    onPressed: cameraController.switchCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                    color: AppPalette.muted,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: cameraController,
                        onDetect: (capture) {
                          final code = capture.barcodes.first.rawValue;
                          if (code != null) handleScan(code);
                        },
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppPalette.teal, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                      if (isProcessing)
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
