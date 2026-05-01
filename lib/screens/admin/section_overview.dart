import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SectionOverview extends StatelessWidget {
  const SectionOverview({super.key});

  static const List<String> _allSections = [
    'Section A',
    'Section B',
    'Section C',
    'Section D',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Section Overview',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allSections.length,
        itemBuilder: (context, index) {
          final section = _allSections[index];
          return _SectionCard(sectionName: section);
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String sectionName;

  const _SectionCard({required this.sectionName});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.class_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text(sectionName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const Spacer(),
                // Student count badge
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('children')
                      .where('section', isEqualTo: sectionName)
                      .snapshots(),
                  builder: (context, snap) {
                    final count = snap.data?.docs.length ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.child_care,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text('$count students',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Teacher info
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'teacher')
                .where('assignedSection', isEqualTo: sectionName)
                .snapshots(),
            builder: (context, teacherSnap) {
              final teacher = teacherSnap.data?.docs.isNotEmpty == true
                  ? teacherSnap.data!.docs.first
                  : null;

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    const Text('Teacher:',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280))),
                    const SizedBox(width: 6),
                    teacher != null
                        ? Expanded(
                            child: Text(
                              teacher['name'] ?? 'Unknown',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Color(0xFF059669)),
                            ),
                          )
                        : const Expanded(
                            child: Text(
                              'No teacher assigned',
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                  color: Color(0xFFD97706)),
                            ),
                          ),
                  ],
                ),
              );
            },
          ),

          // Student list
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('children')
                .where('section', isEqualTo: sectionName)
                .snapshots(),
            builder: (context, childSnap) {
              final children = childSnap.data?.docs ?? [];

              if (children.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text('No students in this section yet.',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text('Students (${children.length})',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF374151))),
                  ),
                  ...children.map((child) {
                    final name = child['name'] ?? 'Unknown';
                    final initials = name.isNotEmpty
                        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
                        : '?';
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFFDBEAFE),
                            child: Text(initials.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1D4ED8))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF111827))),
                          ),
                          if (child['parentName'] != null)
                            Text(
                              child['parentName'],
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9CA3AF)),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 10),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}