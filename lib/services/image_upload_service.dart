import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';

class PickedUploadImage {
  final XFile file;
  final Uint8List bytes;

  const PickedUploadImage({required this.file, required this.bytes});
}

class ImageUploadException implements Exception {
  final String message;
  final String? code;

  const ImageUploadException(this.message, {this.code});

  @override
  String toString() => message;
}

class ImageUploadService {
  ImageUploadService._();

  static const int _maxInlinePhotoBytes = 250 * 1024;
  static final ImagePicker _picker = ImagePicker();

  static Future<PickedUploadImage?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 480,
      maxHeight: 480,
      imageQuality: 72,
    );
    if (file == null) return null;

    return PickedUploadImage(file: file, bytes: await file.readAsBytes());
  }

  static Future<String> uploadPickedImage({
    required PickedUploadImage image,
    required String ownerId,
    required String category,
  }) async {
    if (image.bytes.isEmpty) {
      throw const ImageUploadException(
        'The selected photo is empty. Please choose another photo.',
      );
    }

    final extension = _extensionFor(image.file.name);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}.$extension';
    final storageRefs = _storageCandidates().map((storage) {
      return storage
          .ref()
          .child('pickup_photos')
          .child(ownerId)
          .child(category)
          .child(fileName);
    });

    FirebaseException? storageError;
    for (final ref in storageRefs) {
      try {
        return await _uploadToRef(ref: ref, image: image, extension: extension);
      } on FirebaseException catch (e) {
        storageError = e;
        if (!_shouldTryNextBucket(e)) {
          throw ImageUploadException(_messageForStorageError(e), code: e.code);
        }
      }
    }

    if (storageError != null) {
      return _inlineDataUrl(image: image, extension: extension);
    }
    throw const ImageUploadException(
      'Firebase Storage is not configured for this app.',
    );
  }

  static Future<String> _uploadToRef({
    required Reference ref,
    required PickedUploadImage image,
    required String extension,
  }) async {
    final snapshot = await ref.putData(
      image.bytes,
      SettableMetadata(contentType: _contentTypeFor(extension)),
    );

    return _downloadUrlAfterUpload(snapshot.ref);
  }

  static List<FirebaseStorage> _storageCandidates() {
    final options = DefaultFirebaseOptions.currentPlatform;
    final bucket = options.storageBucket;
    final buckets = <String>[
      if (bucket != null && bucket.trim().isNotEmpty) bucket.trim(),
      '${options.projectId}.appspot.com',
    ];
    final seen = <String>{};

    return buckets
        .map(_normalizeBucketUrl)
        .where((bucketUrl) => seen.add(bucketUrl))
        .map((bucketUrl) => FirebaseStorage.instanceFor(bucket: bucketUrl))
        .toList();
  }

  static String _normalizeBucketUrl(String bucket) {
    final cleanBucket = bucket
        .trim()
        .replaceFirst(RegExp(r'^gs://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return 'gs://$cleanBucket';
  }

  static String _inlineDataUrl({
    required PickedUploadImage image,
    required String extension,
  }) {
    if (image.bytes.length > _maxInlinePhotoBytes) {
      throw const ImageUploadException(
        'Firebase Storage is not set up, and this photo is too large to save directly. Please choose a smaller photo or set up Firebase Storage.',
      );
    }

    return 'data:${_contentTypeFor(extension)};base64,${base64Encode(image.bytes)}';
  }

  static Future<String> _downloadUrlAfterUpload(Reference ref) async {
    const retryDelays = [
      Duration(milliseconds: 250),
      Duration(milliseconds: 600),
      Duration(seconds: 1),
    ];

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      try {
        return await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        if (!_isObjectNotFound(e) || attempt == retryDelays.length) rethrow;
        await Future.delayed(retryDelays[attempt]);
      }
    }

    throw const ImageUploadException(
      'The photo was uploaded, but its download link could not be created. Please try again.',
    );
  }

  static bool _isObjectNotFound(FirebaseException e) {
    return e.code == 'object-not-found' || e.code == 'storage/object-not-found';
  }

  static bool _isBucketNotFound(FirebaseException e) {
    return e.code == 'bucket-not-found' || e.code == 'storage/bucket-not-found';
  }

  static bool _shouldTryNextBucket(FirebaseException e) {
    return _isObjectNotFound(e) || _isBucketNotFound(e);
  }

  static String _messageForStorageError(FirebaseException e) {
    return switch (e.code) {
      'object-not-found' || 'storage/object-not-found' =>
        'Firebase Storage could not find this app\'s upload bucket. Open Firebase Console > Storage and make sure the bucket exists.',
      'bucket-not-found' || 'storage/bucket-not-found' =>
        'Firebase Storage is not set up for this project yet. Create the Storage bucket in Firebase Console.',
      'unauthenticated' || 'storage/unauthenticated' =>
        'Please sign in again before uploading a photo.',
      'unauthorized' || 'storage/unauthorized' =>
        'Your account is not allowed to upload this photo.',
      'quota-exceeded' || 'storage/quota-exceeded' =>
        'Photo uploads are temporarily unavailable because storage quota was exceeded.',
      'canceled' || 'storage/canceled' => 'Photo upload was cancelled.',
      'invalid-argument' || 'storage/invalid-argument' =>
        'The selected photo could not be uploaded. Please choose another photo.',
      'server-file-wrong-size' || 'storage/server-file-wrong-size' =>
        'The photo changed while uploading. Please choose it again.',
      _ =>
        e.message?.trim().isNotEmpty == true
            ? 'Photo upload failed: ${e.message}'
            : 'Photo upload failed. Please try again.',
    };
  }

  static String _extensionFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (extension == 'png' || extension == 'webp') return extension;
    return 'jpg';
  }

  static String _contentTypeFor(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
