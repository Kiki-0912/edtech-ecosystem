import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// NOIR FLAME — "The Roster" Student Management
/// High-contrast dark student registry with initials monograms, modal enrolment, and quick deletion.
class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() => _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  List<Map<String, dynamic>> _students = [];
  List<Course> _courses = [];
  bool _loading = true;
  bool _creating = false;
  String _searchQuery = '';
  String? _selectedCourseId;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final api = ApiService();
    try {
      final courses = await api.getCourses();
      final students = await api.getStudents();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _students = students;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addStudent() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _creating = true);
    final api = ApiService();
    try {
      await api.createStudent(
        displayName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        courseId: _selectedCourseId,
      );
      _nameCtrl.clear();
      _emailCtrl.clear();
      _phoneCtrl.clear();
      setState(() => _selectedCourseId = null);
      if (mounted) Navigator.pop(context);
      await _loadData();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteStudent(String id, String name) async {
    HapticFeedback.heavyImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        title: Text('Remove $name?', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
        content: const Text(
          'This will revoke enrolment credentials and remove telemetry associations.',
          style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: kTextSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kError),
            child: const Text('Delete Student', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final api = ApiService();
    await api.deleteStudent(id);
    await _loadData();
  }

  void _showAddStudentSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: kBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ENROLMENT DESK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: kPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add New Student',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline, color: kPrimary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined, color: kPrimary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined, color: kPrimary),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedCourseId,
                  decoration: const InputDecoration(
                    labelText: 'Assign Course',
                    prefixIcon: Icon(Icons.school_outlined, color: kPrimary),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('No Course Assignment')),
                    ..._courses.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.code} · ${c.title}'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedCourseId = v == '' ? null : v),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _creating ? null : _addStudent,
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Enrol Student', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.trim().isEmpty) return _students;
    final q = _searchQuery.toLowerCase();
    return _students.where((s) {
      final name = (s['displayName'] ?? s['name'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'ST';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStudents;

    return Scaffold(
      backgroundColor: kBackground,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStudentSheet,
        backgroundColor: kPrimary,
        elevation: 4,
        child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.black, size: 24),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // ── Header ───────────────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STUDENT REGISTRY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Roster Management',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: kTextPrimary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Stat Cards ───────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'Total Students',
                        value: _students.length,
                        icon: Icons.people_outline,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        title: 'Active Courses',
                        value: _courses.length,
                        icon: Icons.school_outlined,
                        color: kAccent,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Search Bar ───────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(color: kTextPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search roster by name, email or phone...',
                      hintStyle: TextStyle(color: kTextSecondary, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: kPrimary, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Student List ─────────────────────────────────────────────
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.person_off_outlined, size: 40, color: kTextSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'NO STUDENTS MATCHED',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try a different search term or add a new student.',
                          style: TextStyle(color: kTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  ...filtered.map((student) {
                    final name = student['displayName'] ?? student['name'] ?? 'Student';
                    final email = student['email'] ?? '';
                    final phone = student['phone'] ?? '';
                    final id = student['id'] ?? '';
                    final initials = _getInitials(name);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(
                          children: [
                            // Initials Avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [kOrange400, kOrange600],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [flameShadow(0.5)],
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: kTextPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email.isNotEmpty ? email : phone,
                                    style: TextStyle(
                                      color: kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: kError),
                              tooltip: 'Remove',
                              onPressed: () => _deleteStudent(id, name),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
