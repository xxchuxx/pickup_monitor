import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class PickedUploadImage {
  final XFile file;
  final Uint8List bytes;

  const PickedUploadImage({required this.file, required this.bytes});
}

class ImageUploadService {
  ImageUploadService._();

  static final ImagePicker _picker = ImagePicker();

  static Future<PickedUploadImage?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 82,
    );
    if (file == null) return null;

    return PickedUploadImage(file: file, bytes: await file.readAsBytes());
  }

  static Future<String> uploadPickedImage({
    required PickedUploadImage image,
    required String ownerId,
    required String category,
  }) async {
    final extension = _extensionFor(image.file.name);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}.$extension';
    final ref = FirebaseStorage.instance
        .ref()
        .child('pickup_photos')
        .child(ownerId)
        .child(category)
        .child(fileName);

    await ref.putData(
      image.bytes,
      SettableMetadata(contentType: _contentTypeFor(extension)),
    );

    return ref.getDownloadURL();
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
