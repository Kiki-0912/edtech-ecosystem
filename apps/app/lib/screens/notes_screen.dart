import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/bounce_tap.dart';
import 'package:edtech_app/widgets/stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// NOIR FLAME — "The Archive" Notes Screen
/// Organised by course code and book, with card masonry, modal reader, and flame accents.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Course> _courses = [];
  List<Map<String, dynamic>> _notes = [];
  String? _selectedCourseId;
  String _searchQuery = '';
  bool _loading = true;
  bool _creating = false;

  final TextEditingController _bookNameCtrl = TextEditingController();
  final TextEditingController _courseCodeCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _bookNameCtrl.dispose();
    _courseCodeCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final api = ApiService();
    try {
      final courses = await api.getCourses();
      final notes = await api.getTeacherNotes();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _notes = notes.map((n) => n.toJson()).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createNote() async {
    if (_titleCtrl.text.isEmpty || _courseCodeCtrl.text.isEmpty) return;
    setState(() => _creating = true);
    final api = ApiService();
    try {
      await api.createTeacherNote(
        courseId: _selectedCourseId ?? '',
        bookName: _bookNameCtrl.text.trim(),
        courseCode: _courseCodeCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
      );
      _bookNameCtrl.clear();
      _courseCodeCtrl.clear();
      _titleCtrl.clear();
      _contentCtrl.clear();
      if (mounted) Navigator.pop(context);
      await _loadData();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  List<Map<String, dynamic>> get _filteredNotes {
    var list = _notes;
    if (_selectedCourseId != null && _selectedCourseId!.isNotEmpty) {
      list = list.where((n) => n['courseId'] == _selectedCourseId).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((n) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final book = (n['bookName'] ?? '').toString().toLowerCase();
        final code = (n['courseCode'] ?? '').toString().toLowerCase();
        return title.contains(q) || book.contains(q) || code.contains(q);
      }).toList();
    }
    return list;
  }

  void _showNoteReader(Map<String, dynamic> note) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: kBorder, width: 1),
        ),
        child: SafeArea(
          top: false,
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      note['courseCode'] ?? 'NOTE',
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    note['bookName'] ?? '',
                    style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                note['title'] ?? 'Untitled Note',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: kTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: kDivider),
              const SizedBox(height: 16),
              Text(
                note['content'] ?? '',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: kTextBody,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close Archive', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateSheet() {
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
            border: Border.all(color: kBorder, width: 1),
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
                const SizedBox(height: 20),
                const Text(
                  'RECORD IN ARCHIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: kPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create Teacher Note',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _selectedCourseId,
                  decoration: const InputDecoration(labelText: 'Course'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('General / Non-course')),
                    ..._courses.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.code} · ${c.title}'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedCourseId = v == '' ? null : v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _courseCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Course Code (e.g. CIT-301)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bookNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reference Book / Syllabus',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note Headline',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note Details / Key Takeaways',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _creating ? null : _createNote,
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
                        : const Text('Save to Archive', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotes;

    return Scaffold(
      backgroundColor: kBackground,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateSheet,
        backgroundColor: kPrimary,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.black, size: 26),
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
                      'KNOWLEDGE VAULT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Teacher Notes',
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

                // ── Stat Tiles ───────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'Total Notes',
                        value: _notes.length,
                        icon: Icons.note_alt_outlined,
                        color: kPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        title: 'Courses',
                        value: _courses.length,
                        icon: Icons.auto_stories_outlined,
                        color: kAccent,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Search & Course Filter Ribbon ────────────────────────────
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
                      hintText: 'Search notes by book or topic...',
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

                const SizedBox(height: 12),

                // Course selector pills
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _CoursePill(
                        label: 'All Courses',
                        selected: _selectedCourseId == null,
                        onTap: () => setState(() => _selectedCourseId = null),
                      ),
                      const SizedBox(width: 8),
                      ..._courses.map((c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _CoursePill(
                              label: c.code,
                              selected: _selectedCourseId == c.id,
                              onTap: () => setState(() => _selectedCourseId = c.id),
                            ),
                          )),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Note Grid / List ─────────────────────────────────────────
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
                        Icon(Icons.notes_rounded, size: 40, color: kTextSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'ARCHIVE EMPTY',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No notes recorded for this selection.',
                          style: TextStyle(color: kTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  ...filtered.map((note) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NoteCard(
                          note: note,
                          onTap: () => _showNoteReader(note),
                        ),
                      )),
              ],
            ),
    );
  }
}

class _CoursePill extends StatelessWidget {
  const _CoursePill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kPrimary : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? kPrimary : kBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : kTextPrimary,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final Map<String, dynamic> note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = note['title'] ?? 'Untitled';
    final book = note['bookName'] ?? '';
    final code = note['courseCode'] ?? 'NOTE';
    final content = note['content'] ?? '';

    return BounceTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    book,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: kTextSecondary),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: kTextSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
