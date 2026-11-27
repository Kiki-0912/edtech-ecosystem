import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_widgets.dart' show kindLabel;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/shell/app_shell.dart' show eventIcon, eventTone;
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Month calendar with an agenda for the selected day. Admins and teachers
/// can create, edit and delete events (the API allows both roles). Teachers
/// manage only their own courses' events; course-less (campus-wide) events are
/// admin-only, so a teacher's new event always belongs to one of their courses.
///
/// Assignment deadlines (events with an `assignmentId`) are read-only here:
/// they follow their assignment, so the details offer to open it instead.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.canOpenAssignments = true});

  /// False where the router has no assignment pages (the admin console).
  final bool canOpenAssignments;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<CalendarEvent> _events = const [];
  List<Map<String, dynamic>> _departments = const [];
  List<Course> _courses = const [];
  String? _departmentId;
  late DateTime _month;
  late DateTime _selected;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _loadDepartments();
    _loadCourses();
    _load();
  }

  /// The courses an event can belong to: every course for admins, the
  /// courses they teach for teachers.
  Future<void> _loadCourses() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || !(user.isAdmin || user.isTeacher)) return;
    try {
      final all = await ApiService.instance.getCourses();
      if (!mounted) return;
      setState(() => _courses = user.isAdmin
          ? all
          : all.where((c) => c.teacherId == user.id).toList());
    } catch (_) {
      // Admins can still add campus-wide events; teachers see the error.
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final d = await ApiService.instance.getDepartments();
      if (mounted) setState(() => _departments = d);
    } catch (_) {
      // Filter is optional; the calendar still works without it.
    }
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    setState(() {
      _loading = _events.isEmpty;
      _error = null;
    });
    try {
      final events = await ApiService.instance
          .getCalendar(user?.id, departmentId: _departmentId);
      if (!mounted) return;
      setState(() {
        _events = events..sort((a, b) => a.startsAt.compareTo(b.startsAt));
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

  bool get _canEdit {
    final user = context.read<AuthProvider>().user;
    return user != null && (user.isAdmin || user.isTeacher);
  }

  List<CalendarEvent> _on(DateTime day) =>
      _events.where((e) => isSameDay(e.startsAt, day)).toList();

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _openEditor([CalendarEvent? event]) async {
    final result = await showFormSheet<Object>(
      context,
      title: event == null ? 'New event' : 'Edit event',
      builder: (_) => _EventEditor(
        initial: event,
        day: _selected,
        departments: _departments,
        defaultDepartmentId: _departmentId,
        courses: _courses,
        requireCourse: !(context.read<AuthProvider>().user?.isAdmin ?? false),
      ),
    );
    if (result == null || !mounted) return;
    final api = ApiService.instance;
    try {
      if (result is _DeleteEvent) {
        if (event != null) await api.deleteCalendarEvent(event.id);
        if (mounted) {
          showToast(context, 'Event deleted', kind: ToastKind.success);
        }
        await _load();
        return;
      }
      final draft = result as _EventDraft;
      if (event == null) {
        await api.createCalendarEvent(
          title: draft.title,
          kind: draft.kind,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          departmentId: draft.departmentId,
          courseId: draft.courseId,
        );
        if (mounted) showToast(context, 'Event added', kind: ToastKind.success);
      } else {
        await api.updateCalendarEvent(
          id: event.id,
          title: draft.title,
          kind: draft.kind,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          departmentId: draft.departmentId,
          courseId: draft.courseId,
        );
        if (mounted) {
          showToast(context, 'Event updated', kind: ToastKind.success);
        }
      }
      setState(() {
        _selected = DateTime(
            draft.startsAt.year, draft.startsAt.month, draft.startsAt.day);
        _month = DateTime(draft.startsAt.year, draft.startsAt.month);
      });
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
  }

  void _showDetails(CalendarEvent e) {
    final dept = _departments
        .where((d) => d['id'] == e.departmentId)
        .map((d) => d['name']?.toString())
        .firstOrNull;
    showFormSheet<void>(
      context,
      title: e.title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child:
                StatusBadge(label: kindLabel(e.kind), tone: eventTone(e.kind)),
          ),
          const SizedBox(height: AppSpacing.md),
          ListRow(
            leading: const Icon(Icons.event_outlined),
            title: shortDate(e.startsAt),
            subtitle: '${clockTime(e.startsAt)}'
                '${e.endsAt != null ? ' – ${clockTime(e.endsAt!)}' : ''}',
          ),
          if (dept != null)
            ListRow(
              leading: const Icon(Icons.account_tree_outlined),
              title: dept,
              subtitle: 'Department',
            ),
          if (e.isAssignmentDeadline) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This deadline comes from an assignment. '
              'Change it on the assignment page.',
              key: const Key('event-linked-note'),
              style: ctx.text.bodyMedium,
            ),
            if (widget.canOpenAssignments && e.courseId != null) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('event-open-assignment'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go(
                        '/courses/${e.courseId}/assignments/${e.assignmentId}');
                  },
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('Open assignment'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user != null && _canEdit;
    final dayEvents = _on(_selected);

    final grid = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${kMonthLong[_month.month - 1]} ${_month.year}',
                    style: context.text.titleLarge),
              ),
              TextButton(
                  key: const Key('calendar-today'),
                  onPressed: _goToday,
                  child: const Text('Today')),
              IconButton(
                key: const Key('calendar-prev'),
                tooltip: 'Previous month',
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                key: const Key('calendar-next'),
                tooltip: 'Next month',
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _MonthGrid(
            month: _month,
            selected: _selected,
            eventsOn: _on,
            onSelect: (d) => setState(() {
              _selected = d;
              if (d.month != _month.month) _month = DateTime(d.year, d.month);
            }),
          ),
        ],
      ),
    );

    final agenda = SectionCard(
      title: isSameDay(_selected, DateTime.now())
          ? 'Today'
          : '${kWeekdayShort[_selected.weekday - 1]}, ${dayMonth(_selected)}',
      subtitle: dayEvents.isEmpty
          ? 'Nothing scheduled'
          : '${dayEvents.length} ${dayEvents.length == 1 ? 'event' : 'events'}',
      child: dayEvents.isEmpty
          ? EmptyState(
              icon: Icons.event_available_outlined,
              title: 'Clear on this date',
              message: canEdit ? 'Add an event to schedule something.' : null,
              action: canEdit
                  ? OutlinedButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add event'))
                  : null,
            )
          : Column(
              children: [
                for (final e in dayEvents)
                  ListRow(
                    key: Key('event-${e.id}'),
                    leading: IconBadge(
                        icon: eventIcon(e.kind),
                        tone: eventTone(e.kind),
                        size: 36),
                    title: e.title,
                    subtitle: '${clockTime(e.startsAt)}'
                        '${e.endsAt != null ? ' – ${clockTime(e.endsAt!)}' : ''}',
                    // Assignment deadlines are read-only for everyone.
                    trailing: canEdit && !e.isAssignmentDeadline
                        ? Icon(Icons.edit_outlined,
                            size: 18, color: context.colors.textMuted)
                        : StatusBadge(
                            label: kindLabel(e.kind), tone: eventTone(e.kind)),
                    onTap: () => canEdit && !e.isAssignmentDeadline
                        ? _openEditor(e)
                        : _showDetails(e),
                  ),
              ],
            ),
    );

    return AppPage(
      title: 'Calendar',
      subtitle: 'Classes, quizzes, deadlines and campus events',
      onRefresh: _load,
      actions: [
        if (canEdit)
          FilledButton.icon(
            key: const Key('calendar-add'),
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New event'),
          ),
      ],
      children: [
        if (_departments.isNotEmpty)
          FilterChips<String?>(
            options: [
              const FilterOption(null, 'All departments'),
              for (final d in _departments)
                FilterOption(d['id']?.toString(),
                    d['code']?.toString() ?? d['name']?.toString() ?? ''),
            ],
            selected: _departmentId,
            onSelected: (id) {
              setState(() => _departmentId = id);
              _load();
            },
          ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: false,
          skeleton: const SkeletonList(count: 2, itemHeight: 220),
          builder: (_) => TwoPane(
            breakpoint: 960,
            primary: grid,
            secondary: agenda,
          ),
        ),
      ],
    );
  }
}

const kMonthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.eventsOn,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<CalendarEvent> Function(DateTime) eventsOn;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = DateTime(month.year, month.month);
    // Monday-first grid.
    final start = first.subtract(Duration(days: first.weekday - 1));
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: [
            for (final d in kWeekdayShort)
              Expanded(
                child: Center(
                  child:
                      Text(d.substring(0, 2), style: context.text.labelSmall),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: () {
                    final day = DateTime(
                        start.year, start.month, start.day + week * 7 + i);
                    final inMonth = day.month == month.month;
                    final isSelected = isSameDay(day, selected);
                    final isToday = isSameDay(day, today);
                    final events = eventsOn(day);
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: Semantics(
                        button: true,
                        selected: isSelected,
                        label: '${dayMonth(day)}, ${events.length} events',
                        child: InkWell(
                          key: Key('day-${day.year}-${day.month}-${day.day}'),
                          borderRadius: AppRadius.mdAll,
                          onTap: () => onSelect(day),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected ? c.accent : null,
                              borderRadius: AppRadius.mdAll,
                              border: isToday && !isSelected
                                  ? Border.all(color: c.accent)
                                  : null,
                            ),
                            // Narrow phones with large text: shrink the
                            // cell's content rather than overflow it.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: context.text.labelLarge?.copyWith(
                                      color: isSelected
                                          ? c.onAccent
                                          : inMonth
                                              ? c.textPrimary
                                              : c.textMuted
                                                  .withValues(alpha: 0.5),
                                      fontWeight: isToday || isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (final e in events.take(3))
                                        Container(
                                          width: 5,
                                          height: 5,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 1),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? c.onAccent
                                                : c.fg(eventTone(e.kind)),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _EventDraft {
  const _EventDraft({
    required this.title,
    required this.kind,
    required this.startsAt,
    this.endsAt,
    this.departmentId,
    this.courseId,
  });

  final String title;
  final String kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? departmentId;
  final String? courseId;
}

/// Returned by the editor when the user confirms deletion.
class _DeleteEvent {
  const _DeleteEvent();
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({
    required this.initial,
    required this.day,
    required this.departments,
    required this.defaultDepartmentId,
    required this.courses,
    required this.requireCourse,
  });

  final CalendarEvent? initial;
  final DateTime day;
  final List<Map<String, dynamic>> departments;
  final String? defaultDepartmentId;

  /// Courses the caller may put the event in.
  final List<Course> courses;

  /// Teachers must pick a course; only admins may leave it campus-wide.
  final bool requireCourse;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late String _kind;
  late DateTime _date;
  late TimeOfDay _start;
  TimeOfDay? _end;
  String? _departmentId;
  String? _courseId;

  static const kinds = {
    'class': 'Class',
    'assignment': 'Assignment due',
    'quiz': 'Quiz',
    'institution': 'Campus event',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _kind = kinds.containsKey(e?.kind) ? e!.kind : 'class';
    final start = e?.startsAt ??
        DateTime(widget.day.year, widget.day.month, widget.day.day, 9);
    _date = DateTime(start.year, start.month, start.day);
    _start = TimeOfDay.fromDateTime(start);
    _end = e?.endsAt == null ? null : TimeOfDay.fromDateTime(e!.endsAt!);
    _departmentId = e?.departmentId ?? widget.defaultDepartmentId;
    if (!widget.departments.any((d) => d['id'] == _departmentId)) {
      _departmentId = null;
    }
    _courseId = e == null
        ? (widget.requireCourse ? widget.courses.firstOrNull?.id : null)
        : e.courseId;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final startsAt = _at(_start);
    final endsAt = _end == null ? null : _at(_end!);
    if (endsAt != null && !endsAt.isAfter(startsAt)) {
      showToast(context, 'End time must be after the start time',
          kind: ToastKind.error);
      return;
    }
    Navigator.of(context).pop(_EventDraft(
      title: _title.text.trim(),
      kind: _kind,
      startsAt: startsAt,
      endsAt: endsAt,
      departmentId: _departmentId,
      courseId: _courseId,
    ));
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete event?',
      message: '"${widget.initial!.title}" will be removed for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) Navigator.of(context).pop(const _DeleteEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('event-title'),
            controller: _title,
            autofocus: widget.initial == null,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Give the event a title'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('event-kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final k in kinds.entries)
                DropdownMenuItem(value: k.key, child: Text(k.value)),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: AppSpacing.md),
          DatePickerField(
            label: 'Date',
            value: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TimePickerField(
                  label: 'Starts',
                  value: _start,
                  onChanged: (t) => setState(() => _start = t),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _end == null
                    ? OutlinedButton.icon(
                        key: const Key('event-add-end'),
                        onPressed: () => setState(() => _end = TimeOfDay(
                            hour: (_start.hour + 1) % 24,
                            minute: _start.minute)),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('End time'),
                      )
                    : TimePickerField(
                        label: 'Ends',
                        value: _end!,
                        onChanged: (t) => setState(() => _end = t),
                      ),
              ),
            ],
          ),
          if (widget.departments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              key: const Key('event-department'),
              initialValue: _departmentId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Department'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All departments')),
                for (final d in widget.departments)
                  DropdownMenuItem<String?>(
                    value: d['id']?.toString(),
                    child: Text(d['name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _departmentId = v),
            ),
          ],
          if (widget.requireCourse || widget.courses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              key: const Key('event-course'),
              initialValue: _courseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Course'),
              items: [
                if (!widget.requireCourse)
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Campus-wide')),
                for (final c in widget.courses)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text('${c.code} · ${c.title}',
                        overflow: TextOverflow.ellipsis),
                  ),
                // Keep an event's course selectable even if it is not listed.
                if (_courseId != null &&
                    !widget.courses.any((c) => c.id == _courseId))
                  DropdownMenuItem<String?>(
                      value: _courseId, child: Text(_courseId!)),
              ],
              onChanged: (v) => setState(() => _courseId = v),
              validator: (v) => widget.requireCourse && v == null
                  ? 'Pick a course you teach'
                  : null,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (widget.initial != null)
                TextButton.icon(
                  key: const Key('event-delete'),
                  onPressed: _delete,
                  style: TextButton.styleFrom(
                      foregroundColor: context.colors.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                key: const Key('event-save'),
                onPressed: _save,
                child: Text(widget.initial == null ? 'Add event' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
