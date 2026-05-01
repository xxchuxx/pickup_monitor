import 'package:cloud_firestore/cloud_firestore.dart';

class SectionService {
  const SectionService._();

  static const List<String> defaultSections = [
    'Section A',
    'Section B',
    'Section C',
    'Section D',
  ];

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('sections');

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamSections() {
    return _collection.snapshots();
  }

  static List<String> sectionNamesFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final namesByKey = <String, String>{};

    for (final section in defaultSections) {
      namesByKey[_normalize(section)] = section;
    }

    for (final doc in docs) {
      final name = (doc.data()['name'] ?? doc.id).toString().trim();
      if (name.isEmpty) continue;
      namesByKey[_normalize(name)] = name;
    }

    final names = namesByKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<bool> sectionExists(String sectionName) async {
    final normalized = _normalize(sectionName);

    if (defaultSections.any((section) => _normalize(section) == normalized)) {
      return true;
    }

    final snapshot = await _collection.get();
    return snapshot.docs.any((doc) {
      final existingName = (doc.data()['name'] ?? doc.id).toString().trim();
      return _normalize(existingName) == normalized;
    });
  }

  static Future<void> createSection(String sectionName) async {
    await _collection.doc(sectionName).set({
      'name': sectionName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
