import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'confirm_pickup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ScanQr extends StatefulWidget {
  const ScanQr({super.key});

  @override
  State<ScanQr> createState() => _ScanQrState();
}

class _ScanQrState extends State<ScanQr> {
  bool isProcessing = false;
  final MobileScannerController cameraController = MobileScannerController();

  Future<void> handleScan(String scannedData) async {
    if (isProcessing) return;
    setState(() => isProcessing = true);

    // Split "token|yyyy-MM-dd"
    final parts = scannedData.split('|');

    if (parts.length != 2) {
      _showError('Invalid QR code.');
      return;
    }

    final scannedToken = parts[0];
    final scannedDate  = parts[1];
    final today        = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Check date first
    if (scannedDate != today) {
      _showError('This QR code has expired.\nAsk the parent for today\'s code.');
      return;
    }

    try {
      final result = await FirebaseFirestore.instance
          .collection('guardians')
          .where('token', isEqualTo: scannedToken)
          .where('active', isEqualTo: true)
          .get();

      if (result.docs.isEmpty) {
        _showError('This person is not on the authorized pickup list.');
      } else {
        final guardian = result.docs.first.data();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfirmPickup(
              guardianName: guardian['name'],
              relation: guardian['relation'],
              childName: guardian['childName'],
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => isProcessing = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Not Authorized', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => isProcessing = false);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5B7FD4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A6BC0),
        title: const Text('Scan Guardian QR',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF4A6BC0),
            child: const Text(
              'Point the camera at the guardian\'s QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: MobileScanner(
              controller: cameraController,
              onDetect: (capture) {
                final code = capture.barcodes.first.rawValue;
                if (code != null) handleScan(code);
              },
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF4A6BC0),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                  SizedBox(height: 8),
                  Text('Waiting for QR code...',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Make sure the QR code is well lit',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}