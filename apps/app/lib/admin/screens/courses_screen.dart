import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Every course: create, edit (including the teacher), delete and manage the
/// student roster.
class AdminCoursesScreen extends StatefulWidget {
  const AdminCoursesScreen({super.key});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
  List<AdminCourse> _courses = const [];
  List<AdminUser> _users = const [];
  String _query = '';
  bool _loading = true;
  bool _loaded = false;
  Object? _error;

  List<AdminUser> get _teachers => _users.where((u) => u.isTeacher).toList();
  List<AdminUser> get _students => _users.where((u) => u.isStudent).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ApiService.instance;
    setState(() {
      _loading = !_loaded;
      _error = null;
    });
    try {
      final results =
          await Future.wait([api.adminListCourses(), api.adminListUsers()]);
      if (!mounted) return;
      setState(() {
        _courses = (results[0] as List<AdminCourse>)
          ..sort((a, b) => a.code.compareTo(b.code));
        _users = (results[1] as List<AdminUser>)
          ..sort((a, b) => a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase()));
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<AdminCourse> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _courses;
    return _courses
        .where((c) => [c.code, c.title, c.term, c.teacherName]
            .any((v) => v.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _openForm([AdminCourse? course]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: course == null ? 'New course' : 'Edit ${course.code}',
      builder: (_) => _CourseForm(course: course, teachers: _teachers),
    );
    if (saved != true || !mounted) return;
    showToast(context, course == null ? 'Course created' : 'Course updated',
        kind: ToastKind.success);
    await _load();
  }

  Future<void> _openRoster(AdminCourse course) async {
    final saved = await showFormSheet<bool>(
      context,
      title: '${course.code} roster',
      builder: (_) => _RosterForm(course: course, students: _students),
    );
    if (saved != true || !mounted) return;
    showToast(context, 'Roster saved', kind: ToastKind.success);
    await _load();
  }

  Future<void> _delete(AdminCourse course) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${course.code}?',
      message: '${course.title} and everything in it (assignments, '
          'submissions, chat channels, calendar events, attendance and '
          'notes) will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.instance.adminDeleteCourse(course.id);
      if (mounted) {
        showToast(context, 'Course deleted', kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AppPage(
      title: 'Courses',
      subtitle: _loaded
          ? '${_courses.length} ${_courses.length == 1 ? 'course' : 'courses'}'
          : 'Courses, teachers and rosters',
      onRefresh: _load,
      actions: [
        FilledButton.icon(
          key: const Key('courses-add'),
          onPressed: _loaded ? () => _openForm() : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New course'),
        ),
      ],
      children: [
        SearchField(
          key: const Key('courses-search'),
          hint: 'Search code, title, term or teacher',
          onChanged: (v) => setState(() => _query = v),
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: filtered.isEmpty,
          empty: EmptyState(
            icon: Icons.menu_book_outlined,
            title: _courses.isEmpty ? 'No courses yet' : 'No matches',
            message: _courses.isEmpty
                ? 'Create a course and assign a teacher to it.'
                : null,
          ),
          builder: (_) => AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const Divider(),
                  _CourseRow(
                    course: filtered[i],
                    onEdit: () => _openForm(filtered[i]),
                    onRoster: () => _openRoster(filtered[i]),
                    onDelete: () => _delete(filtered[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.course,
    required this.onEdit,
    required this.onRoster,
    required this.onDelete,
  });

  final AdminCourse course;
  final VoidCallback onEdit;
  final VoidCallback onRoster;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final teacher =
        course.teacherName.isEmpty ? 'No teacher' : course.teacherName;
    return Padding(
      key: Key('course-row-${course.id}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          const IconBadge(icon: Icons.menu_book_outlined, tone: Tone.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${course.code} · ${course.title}',
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    [course.term, teacher]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusBadge(
                      label: '${course.studentCount} '
                          '${course.studentCount == 1 ? 'student' : 'students'}',
                      icon: Icons.groups_outlined,
                    ),
                    StatusBadge(
                      label: '${course.assignmentCount} '
                          '${course.assignmentCount == 1 ? 'assignment' : 'assignments'}',
                      icon: Icons.assignment_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: Key('course-menu-${course.id}'),
            tooltip: 'Actions for ${course.code}',
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  onEdit();
                case 'roster':
                  onRoster();
                default:
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                key: Key('course-action-edit'),
                value: 'edit',
                child: Text('Edit'),
              ),
              PopupMenuItem(
                key: Key('course-action-roster'),
                value: 'roster',
                child: Text('Manage roster'),
              ),
              PopupMenuItem(
                key: Key('course-action-delete'),
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({required this.course, required this.teachers});

  /// Null when creating.
  final AdminCourse? course;
  final List<AdminUser> teachers;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _code;
  late final TextEditingController _term;
  String? _teacherId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _title = TextEditingController(text: c?.title ?? '');
    _code = TextEditingController(text: c?.code ?? '');
    _term = TextEditingController(text: c?.term ?? '');
    final current = c?.teacherId;
    _teacherId = widget.teachers.any((t) => t.id == current)
        ? current
        : widget.teachers.firstOrNull?.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _teacherId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiService.instance;
    final title = _title.text.trim();
    final code = _code.text.trim();
    final term = _term.text.trim();
    try {
      final c = widget.course;
      if (c == null) {
        await api.adminCreateCourse(
          title: title,
          code: code,
          term: term,
          teacherId: _teacherId!,
        );
      } else {
        await api.adminUpdateCourse(
          c.id,
          title: title != c.title ? title : null,
          code: code != c.code ? code : null,
          term: term != c.term ? term : null,
          teacherId: _teacherId != c.teacherId ? _teacherId : null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String? notEmpty(String? v, String message) =>
        (v == null || v.trim().isEmpty) ? message : null;
    final noTeachers = widget.teachers.isEmpty;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            FormErrorBanner(
                key: const Key('course-form-error'), message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            key: const Key('course-title'),
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => notEmpty(v, 'Enter a title'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('course-code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Code', hintText: 'e.g. CS 301'),
            validator: (v) => notEmpty(v, 'Enter a course code'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('course-term'),
            controller: _term,
            decoration: const InputDecoration(
                labelText: 'Term', hintText: 'e.g. Fall 2026'),
            validator: (v) => notEmpty(v, 'Enter a term'),
          ),
          const SizedBox(height: AppSpacing.md),
          if (noTeachers)
            Text(
              'There are no teacher accounts yet. Create one under Users '
              'first.',
              key: const Key('course-no-teachers'),
              style: context.text.bodyMedium,
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('course-teacher'),
              initialValue: _teacherId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Teacher'),
              items: [
                for (final t in widget.teachers)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      t.isActive
                          ? t.displayName
                          : '${t.displayName} (inactive)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _teacherId = v ?? _teacherId),
            ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('course-save'),
              label: widget.course == null ? 'Create course' : 'Save changes',
              busy: _busy,
              onPressed: noTeachers ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterForm extends StatefulWidget {
  const _RosterForm({required this.course, required this.students});

  final AdminCourse course;
  final List<AdminUser> students;

  @override
  State<_RosterForm> createState() => _RosterFormState();
}

class _RosterFormState extends State<_RosterForm> {
  late final Set<String> _selected = {...widget.course.studentIds};
  String _query = '';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Keep the order of the student list so requests are deterministic.
      final ids = [
        for (final s in widget.students)
          if (_selected.contains(s.id)) s.id,
      ];
      await ApiService.instance.adminSetCourseStudents(widget.course.id, ids);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.students
        .where((s) =>
            q.isEmpty ||
            [s.displayName, s.email, s.phone]
                .any((v) => v.toLowerCase().contains(q)))
        .toList();
    final count = widget.students.where((s) => _selected.contains(s.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.course.title, style: context.text.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        if (_error != null) ...[
          FormErrorBanner(key: const Key('roster-error'), message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        SearchField(
          key: const Key('roster-search'),
          hint: 'Search students',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('$count selected',
            key: const Key('roster-count'), style: context.text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        if (widget.students.isEmpty)
          const EmptyState(
            icon: Icons.school_outlined,
            title: 'No student accounts yet',
          )
        else
          for (final s in shown)
            CheckboxListTile(
              key: Key('roster-student-${s.id}'),
              value: _selected.contains(s.id),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                s.isActive ? s.displayName : '${s.displayName} (inactive)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [s.email, s.phone].where((v) => v.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(s.id);
                } else {
                  _selected.remove(s.id);
                }
              }),
            ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: BusyButton(
            key: const Key('roster-save'),
            label: 'Save roster',
            busy: _busy,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
