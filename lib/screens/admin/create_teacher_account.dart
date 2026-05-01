import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateTeacherAccount extends StatefulWidget {
  const CreateTeacherAccount({super.key});

  @override
  State<CreateTeacherAccount> createState() => _CreateTeacherAccountState();
}

class _CreateTeacherAccountState extends State<CreateTeacherAccount> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _selectedSection;

  // Sections available — you can fetch these from Firestore if dynamic
  final List<String> _sections = [
    'Section A',
    'Section B',
    'Section C',
    'Section D',
  ];

  Future<void> _createTeacher() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack('Please fill in all fields', isError: true);
      return;
    }
    if (_selectedSection == null) {
      _showSnack('Please assign a section to this teacher', isError: true);
      return;
    }
    if (_passwordController.text.trim().length < 6) {
      _showSnack('Password must be at least 6 characters', isError: true);
      return;
    }

    // Check if section already has a teacher assigned
    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('assignedSection', isEqualTo: _selectedSection)
        .get();

    if (existing.docs.isNotEmpty) {
      _showSnack('$_selectedSection already has a teacher assigned', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Save current admin session so we can restore it
      final currentUser = FirebaseAuth.instance.currentUser;

      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'uid': credential.user!.uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'teacher',
        'assignedSection': _selectedSection,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Also update the sections collection with the teacher reference
      await FirebaseFirestore.instance
          .collection('sections')
          .doc(_selectedSection)
          .set({
        'name': _selectedSection,
        'teacherId': credential.user!.uid,
        'teacherName': _nameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      setState(() => _selectedSection = null);

      _showSnack('Teacher account created & assigned to $_selectedSection!',
          isError: false);
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'An error occurred', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        title: const Text('Create Teacher Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC4B5FD)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF7C3AED), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Each section can only have one teacher. The teacher will only see children in their assigned section.',
                      style: TextStyle(
                          color: Color(0xFF5B21B6), fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section Assignment (first — it's the most important decision)
                  const Text('Assign Section',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF374151))),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'teacher')
                        .snapshots(),
                    builder: (context, snap) {
                      final assignedSections = snap.data?.docs
                          .map((d) => d['assignedSection'] as String?)
                          .whereType<String>()
                          .toSet() ?? {};

                      return Column(
                        children: _sections.map((section) {
                          final isTaken = assignedSections.contains(section);
                          final isSelected = _selectedSection == section;
                          return GestureDetector(
                            onTap: isTaken ? null : () => setState(() => _selectedSection = section),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFEDE9FE)
                                    : isTaken
                                        ? Colors.grey.shade100
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF7C3AED)
                                      : isTaken
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade300,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.class_outlined,
                                    color: isSelected
                                        ? const Color(0xFF7C3AED)
                                        : isTaken
                                            ? Colors.grey.shade400
                                            : const Color(0xFF6B7280),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(section,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: isTaken
                                              ? Colors.grey.shade400
                                              : const Color(0xFF111827),
                                        )),
                                  ),
                                  if (isTaken)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Occupied',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey)),
                                    ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle,
                                        color: Color(0xFF7C3AED), size: 18),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Teacher Details
                  const Text('Teacher Details',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF374151))),
                  const SizedBox(height: 12),

                  _buildTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _createTeacher,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Create Teacher Account',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}