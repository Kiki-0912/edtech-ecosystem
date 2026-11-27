import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart';
import 'package:edtech_app/shell/app_shell.dart' show eventIcon, eventTone;
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Timeline of events (today's schedule or upcoming deadlines).
class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.events,
    required this.emptyTitle,
    this.emptyMessage,
    this.showDate = false,
    this.limit = 6,
  });

  final List<CalendarEvent> events;
  final String emptyTitle;
  final String? emptyMessage;
  final bool showDate;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return EmptyState(
        icon: Icons.event_available_outlined,
        illustration: emptyTitle.contains('caught up')
            ? IllustrationKind.caughtUp
            : IllustrationKind.nothing,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    final now = DateTime.now();
    return Column(
      children: [
        for (final (i, e) in events.take(limit).indexed)
          FadeSlideIn(
              delay: AppMotion.delayFor(i),
              offset: 10,
              child: ListRow(
                key: Key('home-event-${e.id}'),
                leading: IconBadge(
                    icon: eventIcon(e.kind), tone: eventTone(e.kind), size: 36),
                title: e.title,
                subtitle: showDate
                    ? '${isSameDay(e.startsAt, now) ? 'Today' : shortDate(e.startsAt)} · ${clockTime(e.startsAt)}'
                    : '${clockTime(e.startsAt)}${e.endsAt != null ? ' – ${clockTime(e.endsAt!)}' : ''}',
                trailing: StatusBadge(
                  label: kindLabel(e.kind),
                  tone: eventTone(e.kind),
                ),
                onTap: () => context.go('/calendar'),
              )),
      ],
    );
  }
}

String kindLabel(String kind) => switch (kind) {
      'assignment' => 'Due',
      'quiz' => 'Quiz',
      'institution' => 'Event',
      _ => 'Class',
    };

/// Compact list of courses linking to course detail.
class CourseList extends StatelessWidget {
  const CourseList({super.key, required this.courses, this.limit = 5});

  final List<Course> courses;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No courses yet',
        message: 'Courses you join or teach will appear here.',
      );
    }
    return Column(
      children: [
        for (final c in courses.take(limit))
          ListRow(
            key: Key('home-course-${c.id}'),
            leading: const IconBadge(
                icon: Icons.menu_book_outlined, tone: Tone.info, size: 36),
            title: c.title,
            subtitle: [
              c.code,
              if (c.teacherName != null) c.teacherName!,
            ].join(' · '),
            trailing: (c.openAssignmentCount ?? 0) > 0
                ? StatusBadge(
                    label: '${c.openAssignmentCount} open', tone: Tone.warning)
                : null,
            onTap: () => context.go('/courses/${c.id}'),
          ),
      ],
    );
  }
}

/// Donut + legend for an attendance breakdown.
class AttendanceBreakdown extends StatelessWidget {
  const AttendanceBreakdown({super.key, required this.summary});

  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (summary.total == 0) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'No attendance yet',
        message: 'Marked sessions will show up here.',
      );
    }
    return Row(
      children: [
        DonutChart(
          size: 120,
          values: [
            summary.present.toDouble(),
            summary.late.toDouble(),
            summary.absent.toDouble(),
            summary.excused.toDouble(),
          ],
          colors: [c.success, c.warning, c.danger, c.info],
          centerTitle: summary.percentLabel,
          centerSubtitle: 'attended',
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendRow(
                  color: c.success, label: 'Present', value: summary.present),
              _LegendRow(color: c.warning, label: 'Late', value: summary.late),
              _LegendRow(
                  color: c.danger, label: 'Absent', value: summary.absent),
              _LegendRow(
                  color: c.info, label: 'Excused', value: summary.excused),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Text('$value', style: context.text.titleSmall),
        ],
      ),
    );
  }
}

/// Row of shortcut buttons.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.actions});

  final List<(IconData, String, String)> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (i, (icon, label, path)) in actions.indexed)
          FadeSlideIn(
            delay: AppMotion.delayFor(i),
            offset: 8,
            // One hero action per screen: the first is the orange one.
            child: Pressable(
              child: i == 0
                  ? FilledButton.icon(
                      key: Key('quick-${path.replaceAll('/', '-')}'),
                      onPressed: () => context.go(path),
                      icon: Icon(icon, size: 18),
                      label: Text(label),
                    )
                  : OutlinedButton.icon(
                      key: Key('quick-${path.replaceAll('/', '-')}'),
                      onPressed: () => context.go(path),
                      icon: Icon(icon, size: 18),
                      label: Text(label),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Bar chart of attendance rate over recent days.
class AttendanceTrend extends StatelessWidget {
  const AttendanceTrend({super.key, required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = data.dailyAttendance(7);
    if (days.every((d) => d.$2.total == 0)) {
      return const EmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'No sessions this week',
        message: 'Attendance rates appear once classes are marked.',
      );
    }
    return BarChart(
      labels: [for (final d in days) kWeekdayShort[d.$1.weekday - 1]],
      values: [for (final d in days) d.$2.rate * 100],
      maxValue: 100,
      colors: [
        for (final d in days)
          d.$2.total == 0
              ? c.surfaceMuted
              : d.$2.rate >= 0.85
                  ? c.success
                  : d.$2.rate >= 0.6
                      ? c.warning
                      : c.danger,
      ],
      valueFormatter: (v) => '${v.round()}%',
    );
  }
}

/// Open assignments with submission progress (teacher view).
class AssignmentProgressList extends StatelessWidget {
  const AssignmentProgressList({super.key, required this.items});

  final List<AssignmentProgress> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.assignment_turned_in_outlined,
        title: 'No open assignments',
        message: 'New assignments and their submissions will show here.',
      );
    }
    return Column(
      children: [
        for (final p in items)
          InkWell(
            key: Key('home-progress-${p.assignment.id}'),
            borderRadius: AppRadius.mdAll,
            onTap: () => context
                .go('/courses/${p.course.id}/assignments/${p.assignment.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.assignment.title,
                            style: context.text.titleSmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${p.submitted}/${p.total} submitted',
                          style: context.text.labelMedium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                      '${p.course.code} · due ${shortDate(p.assignment.dueAt)}',
                      style: context.text.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  ProgressBar(
                    value: p.ratio,
                    tone: p.ratio >= 0.8 ? Tone.success : Tone.accent,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
