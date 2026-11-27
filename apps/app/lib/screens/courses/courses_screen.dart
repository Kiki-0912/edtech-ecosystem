import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/college.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart' show myCourses;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Course catalogue for the signed-in user, plus the college's programmes.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  List<Course> _courses = const [];
  Map<String, DateTime> _nextDue = const {};
  College? _college;
  bool _loading = true;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    final api = ApiService.instance;
    setState(() {
      _loading = _courses.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([api.getCourses(), api.getCollege()]);
      final all = results[0] as List<Course>;
      final courses = user == null ? all : myCourses(user, all);
      final assignments = await Future.wait(courses.map(
          (c) => api.getAssignments(c.id).catchError((_) => <Assignment>[])));
      final now = DateTime.now();
      final nextDue = <String, DateTime>{};
      for (var i = 0; i < courses.length; i++) {
        final upcoming = assignments[i]
            .where((a) => a.isOpen && a.dueAt.isAfter(now))
            .map((a) => a.dueAt)
            .toList()
          ..sort();
        if (upcoming.isNotEmpty) nextDue[courses[i].id] = upcoming.first;
      }
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _nextDue = nextDue;
        _college = results[1] as College?;
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

  List<Course> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _courses;
    return _courses
        .where((c) =>
            c.title.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q) ||
            (c.teacherName ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final filtered = _filtered;

    return AppPage(
      title: 'Courses',
      subtitle: user?.isAdmin == true
          ? 'All courses this term'
          : user?.isTeacher == true
              ? 'Courses you teach'
              : 'Courses you\'re enrolled in',
      onRefresh: _load,
      children: [
        SearchField(
          key: const Key('courses-search'),
          hint: 'Search by course, code or teacher',
          onChanged: (v) => setState(() => _query = v),
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: filtered.isEmpty,
          skeleton: ResponsiveGrid(children: [
            for (var i = 0; i < 3; i++)
              const Skeleton(height: 150, radius: AppRadius.lg),
          ]),
          empty: _query.isNotEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'Nothing matches "$_query".',
                )
              : const EmptyState(
                  icon: Icons.menu_book_outlined,
                  illustration: IllustrationKind.courses,
                  title: 'No courses yet',
                  message: 'Courses you join or teach will appear here.',
                ),
          builder: (_) => ResponsiveGrid(
            children: [
              for (final c in filtered)
                CourseCard(course: c, nextDue: _nextDue[c.id]),
            ],
          ),
        ),
        if (_college != null && _college!.departments.isNotEmpty)
          _ProgrammesSection(college: _college!),
      ],
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, this.nextDue});

  final Course course;
  final DateTime? nextDue;

  @override
  Widget build(BuildContext context) {
    final open = course.openAssignmentCount ?? 0;
    return AppCard(
      key: Key('course-${course.id}'),
      onTap: () => context.go('/courses/${course.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Monogram(title: course.title),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(label: course.code, tone: Tone.accent),
              const Spacer(),
              Text(course.term, style: context.text.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(course.title,
              style: context.text.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.xxs),
          Text(course.teacherName ?? 'Teacher to be assigned',
              style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _Meta(
                  icon: Icons.groups_outlined,
                  text: '${course.studentCount} students'),
              _Meta(
                icon: Icons.assignment_outlined,
                text: open == 0 ? 'No open work' : '$open open',
              ),
              if (nextDue != null)
                _Meta(
                    icon: Icons.event_outlined,
                    text: 'Next due ${dayMonth(nextDue!)}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ink tile with the course's initials; the orange letters are the spark.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letters = title
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.ink, borderRadius: AppRadius.mdAll),
      child: Text(
        letters,
        style: context.text.titleSmall?.copyWith(color: c.accent),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.colors.textMuted),
        const SizedBox(width: AppSpacing.xxs),
        Text(text, style: context.text.bodySmall),
      ],
    );
  }
}

class _ProgrammesSection extends StatelessWidget {
  const _ProgrammesSection({required this.college});

  final College college;

  @override
  Widget build(BuildContext context) {
    final groups = college.departmentsByCategory;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('programmes'),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          title: Text('Programmes at ${college.shortName}',
              style: context.text.titleMedium),
          subtitle: Text(
              '${college.departmentCount} programmes · ${college.name}',
              style: context.text.bodySmall),
          children: [
            for (final entry in groups.entries) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.sm, bottom: AppSpacing.xs),
                  child: Text(entry.key.toUpperCase(),
                      style: context.text.labelSmall),
                ),
              ),
              ResponsiveGrid(
                minItemWidth: 240,
                spacing: AppSpacing.xs,
                children: [
                  for (final d in entry.value)
                    ListRow(
                      dense: true,
                      leading: IconBadge(
                        icon: Icons.school_outlined,
                        tone: d.isShortCourse ? Tone.warning : Tone.info,
                        size: 32,
                      ),
                      title: d.name,
                      subtitle: '${d.code} · ${d.durationLabel}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
