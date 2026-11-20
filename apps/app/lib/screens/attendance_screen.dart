import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/attendance.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/attendance_marking_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Attendance — the signed-in user's own record rendered as an editorial
/// summary: headline percentage, a 14-day strip, and a per-session list.
///
/// Staff get a header action that pushes [AttendanceMarkingScreen], so the
/// original roster is still one tap away.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceRecord> _records = <AttendanceRecord>[];
  List<Course> _courses = <Course>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getAttendanceRecords(),
        ApiService.instance.getCourses(),
      ]);
      if (!mounted) return;
      setState(() {
        _records = results[0] as List<AttendanceRecord>;
        _courses = results[1] as List<Course>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String get _myId =>
      context.read<AuthProvider>().user?.id ?? 'u-student-1';

  /// The signed-in user's own records. Staff normally have none, so the view
  /// falls back to everything rather than rendering an empty percentage.
  List<AttendanceRecord> get _mine => _records
      .where((record) => record.studentId == _myId)
      .toList(growable: false);

  bool get _isPersonal => _mine.isNotEmpty;

  List<AttendanceRecord> get _scope => _isPersonal ? _mine : _records;

  String? _courseTitle(String courseId) {
    for (final course in _courses) {
      if (course.id == courseId) return course.title;
    }
    return null;
  }

  String? _courseCode(String courseId) {
    for (final course in _courses) {
      if (course.id == courseId) return course.code;
    }
    return null;
  }

  Color _courseColor(String courseId) {
    final index = _courses.indexWhere((course) => course.id == courseId);
    if (index < 0) return kPrimary;
    return kBrandColors[index % kBrandColors.length];
  }

  DateTime _dateOf(AttendanceRecord record) =>
      DateTime.tryParse(record.date) ?? DateTime.now();

  /// The 14-day window the strip renders, ending on today or on the most
  /// recent session — whichever is later.
  List<DateTime> get _stripDays {
    final now = DateTime.now();
    var end = DateTime(now.year, now.month, now.day);
    for (final record in _scope) {
      final date = _dateOf(record);
      if (date.isAfter(end)) end = date;
    }
    return List<DateTime>.generate(
      14,
      (index) => end.subtract(Duration(days: 13 - index)),
    );
  }

  AttendanceRecord? _recordFor(DateTime day) {
    for (final record in _scope) {
      if (isSameDay(_dateOf(record), day)) return record;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final sessions = scope.length;
    final present = scope.where((r) => r.status == 'present').length;
    final percent = sessions == 0 ? 0 : ((present / sessions) * 100).round();
    final term = _courses.isNotEmpty ? _courses.first.term : 'this term';

    final entries = List<AttendanceRecord>.from(scope)
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

    final user = context.watch<AuthProvider>().user;
    final canMark = user?.isTeacher == true || user?.isAdmin == true;

    final range = _stripDays;
    final firstDay = range.first;
    final lastDay = range.last;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: kPrimary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: kSpaceLg,
                vertical: kSpaceMd,
              ),
              children: [
                _Header(
                  eyebrow: sessions == 0
                      ? 'No sessions recorded'
                      : '${dayMonth(firstDay)} – ${dayMonth(lastDay)}',
                  title: 'Attendance,\n$term',
                  showMarkButton: canMark,
                  onMark: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      // ThemedScope so the pushed route repaints when the
                      // palette flips; the child is deliberately non-const —
                      // a canonicalised instance would never rebuild.
                      builder: (_) => ThemedScope(
                        buildChild: (_) => AttendanceMarkingScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kSpaceLg),
                if (_loading)
                  const _AttendanceSkeleton()
                else if (_error != null)
                  _ErrorState(error: _error!, onRetry: _load)
                else if (sessions == 0)
                  const _QuietCard(
                    emoji: '📋',
                    title: 'No attendance recorded yet',
                    message:
                        'Once your teacher marks a session, your percentage and day-by-day record show up here.',
                  )
                else ...[
                  _HeadlineStat(percent: percent, present: present, sessions: sessions),
                  const SizedBox(height: kSpaceLg),
                  _DayStrip(days: range, recordFor: _recordFor),
                  const SizedBox(height: kSpaceSm),
                  _Legend(hasExcused: scope.any((r) => r.status == 'excused')),
                  const SizedBox(height: kSpaceXl),
                  Text(
                    'Class entries',
                    style: context.h2.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  _EntryList(
                    entries: entries.take(12).toList(growable: false),
                    courseTitle: _courseTitle,
                    courseCode: _courseCode,
                    courseColor: _courseColor,
                  ),
                ],
                const SizedBox(height: kSpaceXl),
              ],
            ),
          ),
        ),
        if (!_loading && _error == null && sessions > 0)
          _ExcuseBar(
            onRequested: _requestExcuse,
          ),
      ],
    );
  }

  /// Sends a written excuse to the class channel — the only real mechanism the
  /// API offers a student for reaching their teacher about attendance.
  Future<void> _requestExcuse() async {
    final courses = _courses;
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('You are not enrolled in a course yet', kAccentDark),
      );
      return;
    }
    String? courseId = courses.first.id;
    final controller = TextEditingController();

    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusXl),
          ),
          child: Padding(
            padding: const EdgeInsets.all(kSpaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request excuse',
                  style: context.h4.copyWith(
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: kSpaceSm),
                Text(
                  'This is posted to your class channel so your teacher can review it.',
                  style: context.body2.copyWith(color: kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: kSpaceMd),
                DropdownButtonFormField<String>(
                  initialValue: courseId,
                  decoration: const InputDecoration(labelText: 'Course'),
                  items: courses
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.code} - ${c.title}'),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => courseId = value),
                ),
                const SizedBox(height: kSpaceMd),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. Medical appointment on Thursday',
                  ),
                ),
                const SizedBox(height: kSpaceXl),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: kSpaceSm),
                    Expanded(
                      child: FilledButton(
                        onPressed: controller.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(dialogContext, true),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();

    if (sent != true || reason.isEmpty || !mounted || courseId == null) return;

    try {
      final userId = context.read<AuthProvider>().user?.id ?? 'u-student-1';
      final channel = await ApiService.instance.messageCourseChannel(
        courseId: courseId!,
        authorId: userId,
        body: 'Excuse request: $reason',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Sent to $channel', kPrimary),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Could not send: $e', kTextPrimary),
      );
    }
  }

  SnackBar _snack(String text, Color color) => SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(kSpaceMd),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
      );
}

class _Header extends StatelessWidget {
  final String eyebrow;
  final String title;
  final bool showMarkButton;
  final VoidCallback onMark;

  const _Header({
    required this.eyebrow,
    required this.title,
    required this.showMarkButton,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: context.overline.copyWith(letterSpacing: 1.1),
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                title,
                style: TextStyle(
                  fontSize: 44,
                  height: 1.05,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                ),
              ),
            ],
          ),
        ),
        if (showMarkButton) ...[
          const SizedBox(width: kSpaceSm),
          Tooltip(
            message: 'Mark attendance',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kCard,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
              child: IconButton(
                tooltip: null,
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: kTextPrimary,
                icon: const Icon(Icons.fact_check_rounded),
                onPressed: onMark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeadlineStat extends StatelessWidget {
  final int percent;
  final int present;
  final int sessions;

  const _HeadlineStat({
    required this.percent,
    required this.present,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent.toDouble()),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Text(
            '${value.round()}%',
            style: TextStyle(
              fontSize: 56,
              height: 1,
              letterSpacing: -2,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              color: kTextPrimary,
            ),
          ),
        ),
        const SizedBox(width: kSpaceSm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'present · $present of $sessions sessions',
              style: context.body2.copyWith(color: kTextSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

/// 14-day strip. A day with no session is muted; the rest are tinted by status.
class _DayStrip extends StatelessWidget {
  final List<DateTime> days;
  final AttendanceRecord? Function(DateTime day) recordFor;

  const _DayStrip({required this.days, required this.recordFor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(child: _DayCell(day: days[i], record: recordFor(days[i]))),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final AttendanceRecord? record;

  const _DayCell({required this.day, required this.record});

  @override
  Widget build(BuildContext context) {
    final status = record?.status;
    final (background, foreground) = _colors(status);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekdayInitial(day),
            style: TextStyle(fontSize: 13, color: foreground, height: 1.2),
          ),
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(String? status) {
    switch (status) {
      case 'present':
        return (tintOf(kPrimary, 0.12), kPrimary);
      case 'absent':
        return (kTextPrimary, kBackground);
      case 'late':
        return (kAccent, kTextPrimary);
      case 'excused':
        return (kSurface, kTextPrimary);
      default:
        return (kDivider, kTextSecondary);
    }
  }
}

class _Legend extends StatelessWidget {
  final bool hasExcused;
  const _Legend({required this.hasExcused});

  @override
  Widget build(BuildContext context) {
    final items = <(String, Color)>[
      ('Present', tintOf(kPrimary, 0.35)),
      ('Absent', kTextPrimary),
      ('Late', kAccent),
      if (hasExcused) ('Excused', kBorder),
    ];

    return Wrap(
      spacing: kSpaceMd,
      runSpacing: kSpaceXs,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.body2.copyWith(
                  fontSize: 13,
                  color: kTextSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _EntryList extends StatelessWidget {
  final List<AttendanceRecord> entries;
  final String? Function(String courseId) courseTitle;
  final String? Function(String courseId) courseCode;
  final Color Function(String courseId) courseColor;

  const _EntryList({
    required this.entries,
    required this.courseTitle,
    required this.courseCode,
    required this.courseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, color: kDivider),
            _EntryRow(
              record: entries[i],
              title: courseTitle(entries[i].courseId),
              code: courseCode(entries[i].courseId),
              color: courseColor(entries[i].courseId),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final AttendanceRecord record;
  final String? title;
  final String? code;
  final Color color;

  const _EntryRow({
    required this.record,
    required this.title,
    required this.code,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final status = record.status;
    final (icon, bubble, iconColor) = _leading(status);

    return Padding(
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bubble, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title ?? 'Course',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${shortDate(DateTime.tryParse(record.date) ?? DateTime.now())}'
                  '${code != null ? ' · $code' : ''}',
                  style: context.body2.copyWith(color: kTextSecondary),
                ),
                if (record.notes.isNotEmpty) ...[
                  const SizedBox(height: kSpaceSm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: tintOf(kAccent, 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 14, color: kTextPrimary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            record.notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.body2.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: kSpaceSm),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _label(status),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, Color) _leading(String status) {
    switch (status) {
      case 'present':
        return (Icons.check_rounded, tintOf(kPrimary, 0.16), kPrimary);
      case 'late':
        return (Icons.schedule_rounded, tintOf(kAccent, 0.28), kTextPrimary);
      case 'excused':
        return (Icons.favorite_outline_rounded, tintOf(kTextPrimary, 0.06), kTextPrimary);
      default:
        return (Icons.close_rounded, kTextPrimary, kBackground);
    }
  }

  String _label(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'late':
        return 'Late';
      case 'excused':
        return 'Excused';
      default:
        return status.isEmpty ? '—' : '${status[0].toUpperCase()}${status.substring(1)}';
    }
  }
}

/// Pinned action bar sitting directly above the shell's bottom navigation.
class _ExcuseBar extends StatelessWidget {
  final VoidCallback onRequested;
  const _ExcuseBar({required this.onRequested});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBackground,
        border: Border(top: BorderSide(color: kDivider)),
      ),
      padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceMd, kSpaceLg, kSpaceMd),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRequested,
            icon: const Icon(Icons.attach_file_rounded, size: 20),
            label: const Text('Request excuse'),
          ),
        ),
      ),
    );
  }
}

class _AttendanceSkeleton extends StatelessWidget {
  const _AttendanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(height: 64, borderRadius: BorderRadius.all(Radius.circular(12))),
        SizedBox(height: kSpaceLg),
        SkeletonBox(height: 64, borderRadius: BorderRadius.all(Radius.circular(8))),
        SizedBox(height: kSpaceLg),
        SkeletonBox(height: 220, borderRadius: BorderRadius.all(Radius.circular(20))),
      ],
    );
  }
}

class _QuietCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;

  const _QuietCard({required this.emoji, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: kSpaceMd),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.h4.copyWith(fontWeight: FontWeight.w800, color: kTextPrimary),
          ),
          const SizedBox(height: kSpaceSm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, height: 1.7, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('😵', style: TextStyle(fontSize: 44)),
          const SizedBox(height: kSpaceMd),
          Text(
            error,
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: kSpaceLg),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(foregroundColor: kPrimary),
          ),
        ],
      ),
    );
  }
}
