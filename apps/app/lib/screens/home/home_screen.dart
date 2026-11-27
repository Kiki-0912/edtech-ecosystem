import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/screens/home/home_data.dart';
import 'package:edtech_app/screens/home/home_widgets.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Role-aware dashboard: students see their day, teachers their classes and
/// submissions, admins the institution at a glance.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _data;
  Object? _error;
  bool _loading = true;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthProvider>().user;
    if (user != null && user.id != _loadedFor) {
      _loadedFor = user.id;
      _load();
    }
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await HomeData.load(user);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    final now = DateTime.now();

    final body = AsyncBody(
      loading: _loading,
      error: _error,
      isEmpty: false,
      onRetry: _load,
      skeleton: const _HomeSkeleton(),
      builder: (_) => switch (user.role) {
        'admin' => _AdminHome(data: _data!),
        'teacher' => _TeacherHome(data: _data!),
        _ => _StudentHome(data: _data!),
      },
    );

    return AppPage(
      title: '${greetingFor(now)}, ${firstName(user.displayName)}',
      subtitle:
          '${kWeekdayLong[now.weekday - 1]}, ${dayMonth(now)} · ${_tagline(user)}',
      onRefresh: _load,
      children: [body],
    );
  }

  String _tagline(User user) => switch (user.role) {
        'admin' => 'Here\'s how the institution is doing',
        'teacher' => 'Here\'s your teaching day',
        _ => 'Here\'s what\'s on your plate',
      };
}

const kWeekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class _StudentHome extends StatelessWidget {
  const _StudentHome({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final today = data.eventsOn(DateTime.now());
    final dueSoon = data.deadlinesWithin(7);
    final summary = data.attendanceSummary;
    final nextClass = today
        .where((e) => e.kind == 'class' && e.startsAt.isAfter(DateTime.now()))
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            StatTile(
              label: 'Attendance',
              value: summary.percentLabel,
              icon: Icons.fact_check_outlined,
              tone: summary.total == 0
                  ? Tone.neutral
                  : summary.rate >= 0.85
                      ? Tone.success
                      : Tone.warning,
              caption: summary.total == 0
                  ? null
                  : '${summary.total} ${summary.total == 1 ? 'session' : 'sessions'}',
            ),
            StatTile(
              label: 'Due this week',
              value: '${dueSoon.length}',
              icon: Icons.assignment_outlined,
              tone: dueSoon.isEmpty ? Tone.success : Tone.warning,
            ),
            StatTile(
              label: 'Courses',
              value: '${data.courses.length}',
              icon: Icons.menu_book_outlined,
              tone: Tone.info,
            ),
            StatTile(
              label: 'Next class',
              value: nextClass == null ? '—' : clockTime(nextClass.startsAt),
              icon: Icons.schedule_rounded,
              caption: nextClass?.title,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TwoPane(
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Today',
                subtitle: '${today.length} scheduled',
                child: EventList(
                  events: today,
                  emptyTitle: 'Nothing scheduled today',
                  emptyMessage: 'Enjoy the free time.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Due this week',
                child: EventList(
                  events: dueSoon,
                  showDate: true,
                  emptyTitle: 'You\'re all caught up',
                  emptyMessage: 'No deadlines in the next 7 days.',
                ),
              ),
            ],
          ),
          secondary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'My courses',
                child: CourseList(courses: data.courses),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'My attendance',
                child: AttendanceBreakdown(summary: summary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeacherHome extends StatelessWidget {
  const _TeacherHome({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final today = data.eventsOn(DateTime.now());
    final pending = data.progress.fold<int>(
      0,
      (sum, p) => sum + (p.total - p.submitted),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            StatTile(
              label: 'My courses',
              value: '${data.courses.length}',
              icon: Icons.menu_book_outlined,
              tone: Tone.info,
            ),
            StatTile(
              label: 'Students',
              value: '${data.studentCount}',
              icon: Icons.groups_outlined,
            ),
            StatTile(
              label: 'Classes today',
              value: '${today.where((e) => e.kind == 'class').length}',
              icon: Icons.schedule_rounded,
              tone: Tone.success,
            ),
            StatTile(
              label: 'Awaiting submission',
              value: '$pending',
              icon: Icons.pending_actions_outlined,
              tone: pending == 0 ? Tone.success : Tone.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const QuickActions(
          actions: [
            (Icons.fact_check_outlined, 'Mark attendance', '/attendance/mark'),
            (Icons.campaign_outlined, 'Message a class', '/chat'),
            (Icons.sticky_note_2_outlined, 'Add a note', '/notes'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TwoPane(
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Today',
                subtitle: '${today.length} scheduled',
                child: EventList(events: today, emptyTitle: 'No classes today'),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Open assignments',
                child: AssignmentProgressList(items: data.progress),
              ),
            ],
          ),
          secondary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'My courses',
                child: CourseList(courses: data.courses),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Class attendance',
                child: AttendanceBreakdown(summary: data.attendanceSummary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final summary = data.attendanceSummary;
    final upcoming =
        data.events.where((e) => !e.startsAt.isBefore(DateTime.now())).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            StatTile(
              label: 'Students',
              value: grouped(data.studentCount),
              icon: Icons.groups_outlined,
            ),
            StatTile(
              label: 'Departments',
              value: '${data.departmentCount}',
              icon: Icons.account_tree_outlined,
              tone: Tone.info,
            ),
            StatTile(
              label: 'Courses',
              value: '${data.courses.length}',
              icon: Icons.menu_book_outlined,
              tone: Tone.info,
            ),
            StatTile(
              label: 'Attendance rate',
              value: summary.percentLabel,
              icon: Icons.fact_check_outlined,
              tone: summary.total == 0
                  ? Tone.neutral
                  : summary.rate >= 0.85
                      ? Tone.success
                      : Tone.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const QuickActions(
          actions: [
            (Icons.person_add_alt_outlined, 'Add student', '/students'),
            (Icons.event_outlined, 'Add event', '/calendar'),
            (Icons.fact_check_outlined, 'Mark attendance', '/attendance/mark'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TwoPane(
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Attendance this week',
                subtitle: 'Share of students present or late',
                child: AttendanceTrend(data: data),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Upcoming',
                child: EventList(
                  events: upcoming,
                  showDate: true,
                  emptyTitle: 'Nothing scheduled',
                ),
              ),
            ],
          ),
          secondary: SectionCard(
            title: 'Attendance breakdown',
            subtitle: 'All recorded sessions',
            child: AttendanceBreakdown(summary: summary),
          ),
        ),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            for (var i = 0; i < 4; i++)
              const Skeleton(height: 76, radius: AppRadius.lg),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SkeletonList(count: 3, itemHeight: 120),
      ],
    );
  }
}
