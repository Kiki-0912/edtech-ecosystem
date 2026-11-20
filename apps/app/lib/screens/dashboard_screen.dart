import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/bounce_tap.dart';
import 'package:edtech_app/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Dashboard — editorial header, an "Today" timeline of the signed-in user's
/// calendar, and a "Due this week" list. Layout follows the Sleek design; the
/// palette, type scale and spacing come from `theme.dart`.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  List<CalendarEvent> _events = <CalendarEvent>[];
  Map<String, String> _courseTitles = <String, String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1.0,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = context.read<AuthProvider>().user?.id ?? 'u-student-1';
      final results = await Future.wait([
        ApiService.instance.getCalendar(userId),
        ApiService.instance.getCourses(),
      ]);
      final events = results[0] as List<CalendarEvent>;
      final courses = results[1] as List<Course>;
      if (!mounted) return;
      setState(() {
        _events = List<CalendarEvent>.from(events)
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        _courseTitles = <String, String>{
          for (final course in courses) course.id: course.title,
        };
        _loading = false;
      });
      _fade.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Everything scheduled for the current calendar day.
  List<CalendarEvent> get _todayEvents {
    final now = DateTime.now();
    return _events.where((event) => isSameDay(event.startsAt, now)).toList();
  }

  /// Everything scheduled after today and within the next seven days.
  List<CalendarEvent> get _weekEvents {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final horizon = now.add(const Duration(days: 7));
    return _events
        .where((event) =>
            !event.startsAt.isBefore(tomorrow) && !event.startsAt.isAfter(horizon))
        .toList();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayEvents;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
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
              count: today.length,
              onBellTap: () => _showTodaySheet(today),
            ),
            const SizedBox(height: kSpaceLg),
            if (_loading)
              const _TimelineSkeleton()
            else if (_error != null)
              _ErrorState(error: _error!, onRetry: _load)
            else if (today.isEmpty)
              const _QuietCard(
                emoji: '🌤️',
                title: 'Nothing scheduled today',
                message: 'Your calendar is clear. Enjoy the breathing room.',
              )
            else
              _Timeline(events: today, courseTitles: _courseTitles),
            const SizedBox(height: kSpaceXl),
            Text(
              'Due this week',
              style: context.h2.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: kSpaceMd),
            if (_loading)
              const SkeletonCard()
            else if (_error == null)
              if (_weekEvents.isEmpty)
                const _QuietCard(
                  emoji: '🗓️',
                  title: 'No deadlines this week',
                  message: 'Anything due in the next seven days will show up here.',
                )
              else
                _WeekList(events: _weekEvents, courseTitles: _courseTitles),
            const SizedBox(height: kSpaceXl),
          ],
        ),
      ),
    );
  }

  void _showTodaySheet(List<CalendarEvent> today) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLg)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceMd, kSpaceLg, kSpaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: kSpaceMd),
              Text(
                'Today',
                style: context.h4.copyWith(
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                shortDate(DateTime.now()),
                style: context.body2.copyWith(color: kTextSecondary),
              ),
              const SizedBox(height: kSpaceMd),
              if (today.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: kSpaceMd),
                  child: Text(
                    'Nothing scheduled today.',
                    style: context.body2.copyWith(color: kTextSecondary),
                  ),
                )
              else
                for (final event in today)
                  Padding(
                    padding: const EdgeInsets.only(bottom: kSpaceSm),
                    child: Row(
                      children: [
                        Text(
                          clockTime(event.startsAt),
                          style: context.subtitle2.copyWith(
                            color: kPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: kSpaceMd),
                        Expanded(
                          child: Text(
                            event.title,
                            style: context.body2.copyWith(
                              color: kTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback onBellTap;

  const _Header({required this.count, required this.onBellTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today · ${shortDate(now)}'.toUpperCase(),
                style: context.overline.copyWith(letterSpacing: 1.1),
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                'Today',
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
        const SizedBox(width: kSpaceSm),
        BounceTap(
          onTap: onBellTap,
          child: Tooltip(
            message: count == 0
                ? 'Nothing scheduled today'
                : '$count scheduled today',
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kCard,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    color: kTextPrimary,
                    size: 20,
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: const BoxDecoration(
                          color: kAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w800,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Vertical timeline: time column, a hairline rail with a dot per entry, and a
/// card for each of today's events.
class _Timeline extends StatelessWidget {
  final List<CalendarEvent> events;
  final Map<String, String> courseTitles;

  const _Timeline({required this.events, required this.courseTitles});

  static const double _timeColumn = 52;
  static const double _gap = 12;
  static const double _dot = 12;
  static const double _railX = _timeColumn + _gap + _dot / 2;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: _railX,
          top: 28,
          bottom: 28,
          child: Container(width: 1, color: kBorder),
        ),
        Column(
          children: [
            for (var i = 0; i < events.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == events.length - 1 ? 0 : kSpaceSm),
                child: _TimelineRow(
                  event: events[i],
                  subtitle: courseTitles[events[i].courseId] ?? _kindLabel(events[i].kind),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _kindLabel(String kind) =>
      kind.isEmpty ? 'Institution' : '${kind[0].toUpperCase()}${kind.substring(1)}';
}

class _TimelineRow extends StatelessWidget {
  final CalendarEvent event;
  final String subtitle;

  const _TimelineRow({required this.event, required this.subtitle});

  bool get _isDueToday {
    final kind = event.kind.toLowerCase();
    return kind == 'assignment' || kind == 'quiz' || kind == 'deadline';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _Timeline._timeColumn,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              clockTime(event.startsAt),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
                color: kTextPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: _Timeline._gap),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Container(
            width: _Timeline._dot,
            height: _Timeline._dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimary,
              boxShadow: [
                BoxShadow(color: kBackground, blurRadius: 0, spreadRadius: 4),
              ],
            ),
          ),
        ),
        const SizedBox(width: _Timeline._gap),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(kSpaceMd),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(kRadiusMd),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle.toUpperCase(),
                  style: context.overline.copyWith(letterSpacing: 1.1),
                ),
                const SizedBox(height: 4),
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${clockTime(event.startsAt)}${event.endsAt != null ? ' – ${clockTime(event.endsAt!)}' : ''}',
                  style: context.body2.copyWith(color: kTextSecondary),
                ),
                if (_isDueToday) ...[
                  const SizedBox(height: kSpaceSm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tintOf(kAccent, 0.18),
                      borderRadius: BorderRadius.circular(kRadiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: kAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Due today',
                          style: context.body2.copyWith(
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                          ),
                        ),
                      ],
                    ),
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

class _WeekList extends StatelessWidget {
  final List<CalendarEvent> events;
  final Map<String, String> courseTitles;

  const _WeekList({required this.events, required this.courseTitles});

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
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) Divider(height: 1, color: kDivider),
            _WeekRow(
              event: events[i],
              courseTitle: courseTitles[events[i].courseId],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final CalendarEvent event;
  final String? courseTitle;

  const _WeekRow({required this.event, required this.courseTitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tintOf(kPrimary, 0.10),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: Icon(_iconFor(event.kind), color: kPrimary, size: 20),
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  courseTitle ?? _kindName(event.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body2.copyWith(color: kTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: kSpaceSm),
          Text(
            shortDate(event.startsAt),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
              color: kTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String kind) {
    switch (kind.toLowerCase()) {
      case 'assignment':
        return Icons.assignment_rounded;
      case 'quiz':
        return Icons.quiz_rounded;
      case 'class':
        return Icons.school_rounded;
      case 'institution':
        return Icons.business_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  static String _kindName(String kind) =>
      kind.isEmpty ? 'Institution' : '${kind[0].toUpperCase()}${kind.substring(1)}';
}

class _QuietCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;

  const _QuietCard({required this.emoji, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceLg),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: context.body2.copyWith(
                    color: kTextSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(20))),
        SizedBox(height: kSpaceSm),
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(20))),
        SizedBox(height: kSpaceSm),
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(20))),
      ],
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
