import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/attendance.dart' show TeacherNote;
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/screens/home/home_data.dart' show myCourses;
import 'package:edtech_app/screens/shared/export_dialog.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Course notes and reading references. Teachers/admins write; the author or
/// an admin can edit and delete; students read.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<TeacherNote> _notes = const [];
  List<Course> _courses = const [];
  String? _courseFilter;
  String _query = '';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final api = ApiService.instance;
    setState(() {
      _loading = _notes.isEmpty;
      _error = null;
    });
    try {
      final results =
          await Future.wait([api.getTeacherNotes(), api.getCourses()]);
      final courses = myCourses(user, results[1] as List<Course>);
      final ids = courses.map((c) => c.id).toSet();
      final notes = (results[0] as List<TeacherNote>)
          .where((n) => user.isAdmin || ids.contains(n.courseId))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<TeacherNote> get _filtered {
    final q = _query.trim().toLowerCase();
    return _notes.where((n) {
      if (_courseFilter != null && n.courseId != _courseFilter) return false;
      if (q.isEmpty) return true;
      return [n.title, n.bookName, n.courseCode, n.content]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  bool _canManage(User? user, TeacherNote note) =>
      user != null && (user.isAdmin || note.authorId == user.id);

  Future<void> _openForm([TeacherNote? note]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: note == null ? 'New note' : 'Edit note',
      builder: (_) => _NoteForm(
        note: note,
        courses: _courses,
        defaultCourseId: _courseFilter,
      ),
    );
    if (saved == true) {
      if (mounted) {
        showToast(context, note == null ? 'Note saved' : 'Note updated',
            kind: ToastKind.success);
      }
      await _load();
    }
  }

  Future<void> _delete(TeacherNote note) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete note?',
      message: '"${note.title}" will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.instance.deleteTeacherNote(note.id);
      if (mounted) showToast(context, 'Note deleted', kind: ToastKind.success);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
  }

  void _open(TeacherNote note) {
    final user = context.read<AuthProvider>().user;
    final manage = _canManage(user, note);
    showFormSheet<void>(
      context,
      title: note.title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(label: note.courseCode, tone: Tone.accent),
              if (note.bookName.isNotEmpty)
                StatusBadge(
                    label: note.bookName,
                    tone: Tone.info,
                    icon: Icons.menu_book_outlined),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(note.content, style: ctx.text.bodyLarge),
          const SizedBox(height: AppSpacing.md),
          Text('Updated ${_dateLabel(note.updatedAt)}',
              style: ctx.text.bodySmall),
          if (manage) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton.icon(
                  key: const Key('note-delete'),
                  style:
                      TextButton.styleFrom(foregroundColor: ctx.colors.danger),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _delete(note);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  key: const Key('note-edit'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openForm(note);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final staff = user != null && !user.isStudent;
    final filtered = _filtered;

    return AppPage(
      title: 'Notes',
      subtitle: staff
          ? 'Lecture notes and reading references for your courses'
          : 'Notes and reading from your teachers',
      onRefresh: _load,
      actions: [
        if (staff) ...[
          OutlinedButton.icon(
            key: const Key('notes-export'),
            onPressed: () => showCsvExport(
              context,
              title: 'Export notes',
              load: () => ApiService.instance
                  .exportNotesToExcel(courseId: _courseFilter),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export'),
          ),
          FilledButton.icon(
            key: const Key('note-add'),
            onPressed: _courses.isEmpty ? null : () => _openForm(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New note'),
          ),
        ],
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              key: const Key('notes-search'),
              hint: 'Search title, book, course or content',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_courses.isNotEmpty)
              FilterChips<String?>(
                options: [
                  const FilterOption(null, 'All courses'),
                  for (final c in _courses) FilterOption(c.id, c.code),
                ],
                selected: _courseFilter,
                onSelected: (v) => setState(() => _courseFilter = v),
              ),
          ],
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: filtered.isEmpty,
          empty: EmptyState(
            icon: Icons.sticky_note_2_outlined,
            title: _notes.isEmpty ? 'No notes yet' : 'No matches',
            message: _notes.isEmpty && staff
                ? 'Share lecture notes and reading with your class.'
                : null,
          ),
          builder: (_) => ResponsiveGrid(
            minItemWidth: 300,
            children: [
              for (final n in filtered)
                AppCard(
                  key: Key('note-${n.id}'),
                  onTap: () => _open(n),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusBadge(label: n.courseCode, tone: Tone.accent),
                          const Spacer(),
                          Text(_dateLabel(n.updatedAt),
                              style: context.text.bodySmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(n.title,
                          style: context.text.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (n.bookName.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            Icon(Icons.menu_book_outlined,
                                size: 14, color: context.colors.textMuted),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(n.bookName,
                                  style: context.text.bodySmall,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(n.content,
                          style: context.text.bodyMedium,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _dateLabel(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : shortDate(d.toLocal());
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({
    required this.note,
    required this.courses,
    required this.defaultCourseId,
  });

  final TeacherNote? note;
  final List<Course> courses;
  final String? defaultCourseId;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _book;
  late final TextEditingController _title;
  late final TextEditingController _content;
  late String _courseId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _book = TextEditingController(text: n?.bookName ?? '');
    _title = TextEditingController(text: n?.title ?? '');
    _content = TextEditingController(text: n?.content ?? '');
    final preferred = n?.courseId ?? widget.defaultCourseId;
    _courseId = widget.courses.any((c) => c.id == preferred)
        ? preferred!
        : widget.courses.first.id;
  }

  @override
  void dispose() {
    _book.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Course get _course => widget.courses.firstWhere((c) => c.id == _courseId);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = ApiService.instance;
    try {
      if (widget.note == null) {
        await api.createTeacherNote(
          courseId: _courseId,
          bookName: _book.text.trim(),
          courseCode: _course.code,
          title: _title.text.trim(),
          content: _content.text.trim(),
        );
      } else {
        await api.updateTeacherNote(
          id: widget.note!.id,
          bookName: _book.text.trim(),
          courseCode: _course.code,
          title: _title.text.trim(),
          content: _content.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('note-course'),
            initialValue: _courseId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Course'),
            items: [
              for (final c in widget.courses)
                DropdownMenuItem(
                    value: c.id,
                    child: Text('${c.code} · ${c.title}',
                        overflow: TextOverflow.ellipsis)),
            ],
            // Editing can't move a note between courses (the API has no field).
            onChanged: widget.note != null
                ? null
                : (v) => setState(() => _courseId = v ?? _courseId),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('note-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Give the note a title'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('note-book'),
            controller: _book,
            decoration: const InputDecoration(
              labelText: 'Book or reference (optional)',
              prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('note-content'),
            controller: _content,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Write something' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('note-save'),
              label: widget.note == null ? 'Save note' : 'Save changes',
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
