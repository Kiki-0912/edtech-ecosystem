import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/attendance.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart'
    show AttendanceSummary, isoDate, myCourses;
import 'package:edtech_app/screens/shared/export_dialog.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Students: personal attendance record and excuse requests.
/// Staff: per-course attendance rates, recent sessions and a link to marking.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _records = const [];
  List<Course> _courses = const [];
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
      _loading = _records.isEmpty && _courses.isEmpty;
      _error = null;
    });
    try {
      final results =
          await Future.wait([api.getAttendanceRecords(), api.getCourses()]);
      final courses = myCourses(user, results[1] as List<Course>);
      var records = results[0] as List<AttendanceRecord>;
      if (user.isStudent) {
        records = records.where((r) => r.studentId == user.id).toList();
      } else if (user.isTeacher) {
        final ids = courses.map((c) => c.id).toSet();
        records = records.where((r) => ids.contains(r.courseId)).toList();
      }
      records.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _records = records;
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

  String _courseCode(String id) =>
      _courses.where((c) => c.id == id).firstOrNull?.code ?? id;

  Future<void> _requestExcuse() async {
    final sent = await showFormSheet<String>(
      context,
      title: 'Request an excuse',
      builder: (_) => _ExcuseForm(courses: _courses),
    );
    if (sent != null && mounted) {
      showToast(context, 'Request sent to #$sent', kind: ToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final staff = user != null && !user.isStudent;

    return AppPage(
      title: 'Attendance',
      subtitle: staff
          ? 'Class attendance across your courses'
          : 'Your attendance record',
      onRefresh: _load,
      actions: [
        if (staff) ...[
          OutlinedButton.icon(
            key: const Key('attendance-export'),
            onPressed: () => showCsvExport(
              context,
              title: 'Export attendance',
              load: () => ApiService.instance.exportAttendanceToExcel(),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export'),
          ),
          FilledButton.icon(
            key: const Key('attendance-mark'),
            onPressed: () => context.go('/attendance/mark'),
            icon: const Icon(Icons.fact_check_rounded, size: 18),
            label: const Text('Mark attendance'),
          ),
        ] else
          OutlinedButton.icon(
            key: const Key('attendance-excuse'),
            onPressed: _courses.isEmpty ? null : _requestExcuse,
            icon: const Icon(Icons.mail_outline_rounded, size: 18),
            label: const Text('Request excuse'),
          ),
      ],
      children: [
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: false,
          builder: (_) => staff
              ? _StaffView(
                  records: _records, courses: _courses, codeOf: _courseCode)
              : _StudentView(records: _records, codeOf: _courseCode),
        ),
      ],
    );
  }
}

class _StudentView extends StatelessWidget {
  const _StudentView({required this.records, required this.codeOf});

  final List<AttendanceRecord> records;
  final String Function(String) codeOf;

  @override
  Widget build(BuildContext context) {
    final summary = AttendanceSummary.of(records);
    final tone = summary.total == 0
        ? Tone.neutral
        : summary.rate >= 0.85
            ? Tone.success
            : summary.rate >= 0.6
                ? Tone.warning
                : Tone.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoPane(
          primaryFlex: 2,
          secondaryFlex: 3,
          primary: AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                ProgressRing(
                  value: summary.rate,
                  label: summary.percentLabel,
                  caption: 'attended',
                  tone: tone,
                  size: 140,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  summary.total == 0
                      ? 'No sessions recorded yet'
                      : '${summary.present + summary.late} of ${summary.total} sessions',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
          secondary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveGrid(
                minItemWidth: 140,
                spacing: AppSpacing.sm,
                children: [
                  StatTile(
                      label: 'Present',
                      value: '${summary.present}',
                      icon: Icons.check_circle_outline_rounded,
                      tone: Tone.success),
                  StatTile(
                      label: 'Late',
                      value: '${summary.late}',
                      icon: Icons.schedule_rounded,
                      tone: Tone.warning),
                  StatTile(
                      label: 'Absent',
                      value: '${summary.absent}',
                      icon: Icons.cancel_outlined,
                      tone: Tone.danger),
                  StatTile(
                      label: 'Excused',
                      value: '${summary.excused}',
                      icon: Icons.verified_outlined,
                      tone: Tone.info),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: 'Last 14 days',
                child: _DayStrip(records: records),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Class entries',
          subtitle: '${records.length} recorded',
          child: records.isEmpty
              ? const EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Nothing recorded yet',
                  message: 'Your teachers\' attendance marks will appear here.',
                )
              : Column(
                  children: [
                    for (final r in records.take(30))
                      _RecordRow(record: r, code: codeOf(r.courseId)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.records});

  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final size = ((constraints.maxWidth - 13 * 4) / 14).clamp(14.0, 32.0);
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final d in days)
            () {
              final dayRecords = records.where((r) => r.date == isoDate(d));
              final status =
                  dayRecords.isEmpty ? null : dayRecords.first.status;
              final color = status == null
                  ? c.surfaceMuted
                  : c.fg(attendanceTone(status));
              return Tooltip(
                message: '${dayMonth(d)}: ${status ?? 'no class'}',
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    '${d.day}',
                    style: context.text.labelSmall?.copyWith(
                      color: status == null ? c.textMuted : c.surface,
                      fontSize: size * 0.38,
                    ),
                  ),
                ),
              );
            }(),
        ],
      );
    });
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.code});

  final AttendanceRecord record;
  final String code;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(record.date);
    return ListRow(
      dense: true,
      leading: IconBadge(
        icon: Icons.event_note_outlined,
        tone: attendanceTone(record.status),
        size: 32,
      ),
      title: code,
      subtitle: [
        if (date != null)
          '${kWeekdayShort[date.weekday - 1]} ${shortDate(date)}',
        if (record.notes.isNotEmpty) record.notes,
      ].join(' · '),
      trailing: StatusBadge.attendance(record.status),
    );
  }
}

class _StaffView extends StatelessWidget {
  const _StaffView({
    required this.records,
    required this.courses,
    required this.codeOf,
  });

  final List<AttendanceRecord> records;
  final List<Course> courses;
  final String Function(String) codeOf;

  @override
  Widget build(BuildContext context) {
    final overall = AttendanceSummary.of(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 180,
          children: [
            StatTile(
                label: 'Attendance rate',
                value: overall.percentLabel,
                icon: Icons.insights_rounded,
                tone: overall.rate >= 0.85 ? Tone.success : Tone.warning),
            StatTile(
                label: 'Sessions marked',
                value: '${overall.total}',
                icon: Icons.fact_check_outlined,
                tone: Tone.info),
            StatTile(
                label: 'Absences',
                value: '${overall.absent}',
                icon: Icons.cancel_outlined,
                tone: Tone.danger),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TwoPane(
          primary: SectionCard(
            title: 'By course',
            child: courses.isEmpty
                ? const EmptyState(
                    icon: Icons.menu_book_outlined, title: 'No courses')
                : Column(
                    children: [
                      for (final c in courses)
                        () {
                          final s = AttendanceSummary.of(
                              records.where((r) => r.courseId == c.id));
                          return InkWell(
                            borderRadius: AppRadius.mdAll,
                            onTap: () =>
                                context.go('/attendance/mark?course=${c.id}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                  horizontal: AppSpacing.xs),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('${c.code} · ${c.title}',
                                            style: context.text.titleSmall,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      Text(s.percentLabel,
                                          style: context.text.titleSmall),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  ProgressBar(
                                    value: s.rate,
                                    tone: s.total == 0
                                        ? Tone.neutral
                                        : s.rate >= 0.85
                                            ? Tone.success
                                            : Tone.warning,
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                      '${s.total} marks · ${s.absent} absent · ${s.late} late',
                                      style: context.text.bodySmall),
                                ],
                              ),
                            ),
                          );
                        }(),
                    ],
                  ),
          ),
          secondary: SectionCard(
            title: 'Class entries',
            subtitle: 'Most recent first',
            child: records.isEmpty
                ? const EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Nothing marked yet',
                    message: 'Mark a class to start tracking attendance.',
                  )
                : Column(
                    children: [
                      for (final r in records.take(15))
                        _RecordRow(record: r, code: codeOf(r.courseId)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ExcuseForm extends StatefulWidget {
  const _ExcuseForm({required this.courses});

  final List<Course> courses;

  @override
  State<_ExcuseForm> createState() => _ExcuseFormState();
}

class _ExcuseFormState extends State<_ExcuseForm> {
  final _reason = TextEditingController();
  late String _courseId = widget.courses.first.id;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      showToast(context, 'Add a short reason', kind: ToastKind.error);
      return;
    }
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final channel = await ApiService.instance.messageCourseChannel(
        courseId: _courseId,
        authorId: user.id,
        body: 'Excuse request for ${shortDate(_date)}: $reason',
      );
      if (mounted) Navigator.of(context).pop(channel);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your teacher will see this in the course chat.',
            style: context.text.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: const Key('excuse-course'),
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
          onChanged: (v) => setState(() => _courseId = v ?? _courseId),
        ),
        const SizedBox(height: AppSpacing.md),
        DatePickerField(
          label: 'Date',
          value: _date,
          onChanged: (d) => setState(() => _date = d),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('excuse-reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. Medical appointment',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: BusyButton(
            key: const Key('excuse-send'),
            label: 'Send request',
            busy: _busy,
            onPressed: _send,
          ),
        ),
      ],
    );
  }
}
