import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart' show isoDate, myCourses;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

const _statuses = ['present', 'absent', 'late', 'excused'];

/// Roll call for one course on one date. `?course=` preselects the course.
class AttendanceMarkScreen extends StatefulWidget {
  const AttendanceMarkScreen({super.key, this.initialCourseId});

  final String? initialCourseId;

  @override
  State<AttendanceMarkScreen> createState() => _AttendanceMarkScreenState();
}

class _AttendanceMarkScreenState extends State<AttendanceMarkScreen> {
  List<Course> _courses = const [];
  String? _courseId;
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _roster = const [];
  bool _loading = true;
  bool _loadingRoster = false;
  bool _saving = false;
  bool _dirty = false;
  bool _savedOnce = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _courseId = widget.initialCourseId;
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final courses = myCourses(user, await ApiService.instance.getCourses());
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _loading = false;
        if (_courseId == null || !courses.any((c) => c.id == _courseId)) {
          _courseId = courses.firstOrNull?.id;
        }
      });
      await _loadRoster();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadRoster() async {
    final courseId = _courseId;
    if (courseId == null) return;
    setState(() => _loadingRoster = true);
    try {
      final roster = await ApiService.instance.getCourseStudentsWithAttendance(
        courseId: courseId,
        date: isoDate(_date),
      );
      if (!mounted) return;
      setState(() {
        _roster = [
          for (final r in roster)
            {
              ...r,
              'status':
                  _statuses.contains(r['status']) ? r['status'] : 'present',
              'notes': r['notes']?.toString() ?? '',
            },
        ];
        _loadingRoster = false;
        _dirty = false;
        _savedOnce = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRoster = false);
      showToast(context, friendlyError(e), kind: ToastKind.error);
    }
  }

  void _setStatus(int index, String status) {
    setState(() {
      _roster = [
        for (var i = 0; i < _roster.length; i++)
          i == index ? {..._roster[i], 'status': status} : _roster[i],
      ];
      _dirty = true;
    });
  }

  void _markAll(String status) {
    setState(() {
      _roster = [
        for (final r in _roster) {...r, 'status': status},
      ];
      _dirty = true;
    });
  }

  Future<void> _editNote(int index) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        studentName: _roster[index]['displayName']?.toString() ?? 'student',
        initial: _roster[index]['notes']?.toString() ?? '',
      ),
    );
    if (note == null) return;
    setState(() {
      _roster = [
        for (var i = 0; i < _roster.length; i++)
          i == index ? {..._roster[i], 'notes': note} : _roster[i],
      ];
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final courseId = _courseId;
    if (courseId == null || _roster.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.bulkMarkAttendance(
        courseId: courseId,
        date: isoDate(_date),
        records: [
          for (final r in _roster)
            {
              'studentId': r['id'],
              'status': r['status'],
              'notes': r['notes'] ?? '',
            },
        ],
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _savedOnce = true;
      });
      showToast(
        context,
        'Attendance saved successfully',
        kind: ToastKind.success,
      );
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final s in _statuses)
        s: _roster.where((r) => r['status'] == s).length,
    };

    final saveBar = _roster.isEmpty
        ? null
        : Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(top: BorderSide(color: context.colors.border)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final badges = Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      for (final s in _statuses)
                        StatusBadge(
                          label:
                              '${counts[s]} ${s[0].toUpperCase()}${s.substring(1)}',
                          tone: attendanceTone(s),
                        ),
                    ],
                  );
                  final button = BusyButton(
                    key: const Key('attendance-save'),
                    label: _dirty || !_savedOnce ? 'Save attendance' : 'Saved',
                    icon: Icons.check_rounded,
                    busy: _saving,
                    onPressed: _saving ? null : _save,
                  );
                  if (constraints.maxWidth < 560) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        badges,
                        const SizedBox(height: AppSpacing.xs),
                        button,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: badges),
                      const SizedBox(width: AppSpacing.sm),
                      button,
                    ],
                  );
                },
              ),
            ),
          );

    return AppPage(
      title: 'Mark attendance',
      subtitle: 'Take roll for a class session',
      bottom: saveBar,
      onRefresh: _loadRoster,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/attendance'),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Attendance overview'),
          ),
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _loadCourses,
          isEmpty: _courses.isEmpty,
          empty: const EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No courses to mark',
            message: 'You need to teach a course to take attendance.',
          ),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveGrid(
                minItemWidth: 260,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('mark-course'),
                    initialValue: _courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: [
                      for (final c in _courses)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.code} · ${c.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _courseId = v);
                      _loadRoster();
                    },
                  ),
                  DatePickerField(
                    key: const Key('mark-date'),
                    label: 'Date',
                    value: _date,
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    onChanged: (d) {
                      setState(() => _date = d);
                      _loadRoster();
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  OutlinedButton.icon(
                    key: const Key('mark-all-present'),
                    onPressed:
                        _roster.isEmpty ? null : () => _markAll('present'),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Mark all present'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loadingRoster)
                const SkeletonList(count: 4, itemHeight: 64)
              else if (_roster.isEmpty)
                const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No students in this course',
                )
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      for (var i = 0; i < _roster.length; i++) ...[
                        if (i > 0) const Divider(),
                        _RosterRow(
                          key: Key('mark-row-${_roster[i]['id']}'),
                          student: _roster[i],
                          onStatus: (s) => _setStatus(i, s),
                          onNote: () => _editNote(i),
                        ),
                      ],
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

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.student,
    required this.onStatus,
    required this.onNote,
  });

  final Map<String, dynamic> student;
  final ValueChanged<String> onStatus;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = student['displayName']?.toString() ?? 'Student';
    final status = student['status']?.toString() ?? 'present';
    final note = student['notes']?.toString() ?? '';

    final chips = Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final s in _statuses)
          ChoiceChip(
            key: Key('mark-${student['id']}-$s'),
            label: Text('${s[0].toUpperCase()}${s.substring(1)}'),
            selected: status == s,
            onSelected: (_) => onStatus(s),
            selectedColor: c.bg(attendanceTone(s)),
            side: BorderSide(
              color: status == s ? c.fg(attendanceTone(s)) : c.border,
            ),
            labelStyle: context.text.labelMedium?.copyWith(
              color: status == s ? c.fg(attendanceTone(s)) : c.textSecondary,
              fontWeight: status == s ? FontWeight.w600 : FontWeight.w500,
            ),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );

    final noteButton = IconButton(
      key: Key('mark-note-${student['id']}'),
      tooltip: note.isEmpty ? 'Add note' : 'Edit note',
      onPressed: onNote,
      icon: Icon(
        note.isEmpty ? Icons.note_add_outlined : Icons.sticky_note_2_rounded,
        color: note.isEmpty ? c.textMuted : c.accentText,
      ),
    );

    final identity = Row(
      children: [
        Avatar(name: name, size: 36),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: context.text.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (note.isNotEmpty)
                Text(
                  note,
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              else if (student['rollNumber'] != null)
                Text(
                  student['rollNumber'].toString(),
                  style: context.text.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 640
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: identity),
                      noteButton,
                    ],
                  ),
                  chips,
                ],
              )
            : Row(
                children: [
                  Expanded(child: identity),
                  chips,
                  const SizedBox(width: AppSpacing.xs),
                  noteButton,
                ],
              ),
      ),
    );
  }
}

/// Owns its controller so it is disposed only after the dialog route is gone.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.studentName, required this.initial});

  final String studentName;
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Note for ${widget.studentName}'),
      content: TextField(
        key: const Key('attendance-note-input'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. Left early for a clinic visit',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('attendance-note-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save note'),
        ),
      ],
    );
  }
}
