import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/screens/courses/assignment_form.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// One course: overview, assignments and people.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  Course? _course;
  List<Assignment> _assignments = const [];
  List<Map<String, dynamic>> _people = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ApiService.instance.assignmentsRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ApiService.instance.assignmentsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final api = ApiService.instance;
    setState(() {
      _loading = _course == null;
      _error = null;
    });
    try {
      final courses = await api.getCourses();
      final course = courses.where((c) => c.id == widget.courseId).firstOrNull;
      if (course == null) throw Exception('Course not found');
      final results = await Future.wait([
        api.getAssignments(course.id),
        api
            .getStudentsByCourse(course.id)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _course = course;
        _assignments = (results[0] as List<Assignment>)
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
        _people = results[1] as List<Map<String, dynamic>>;
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

  Future<void> _create(Course course) async {
    final created = await showAssignmentForm(context, courseId: course.id);
    if (created == null || !mounted) return;
    // The list reloads through ApiService.assignmentsRevision.
    showToast(context, 'Assignment created', kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    final user = context.watch<AuthProvider>().user;

    if (course == null) {
      return AppPage(
        title: 'Course',
        children: [
          _BackLink(),
          AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            isEmpty: false,
            builder: (_) => const SizedBox.shrink(),
          ),
        ],
      );
    }

    final open = _assignments.where((a) => a.isOpen).toList();
    final closed = _assignments.where((a) => !a.isOpen).toList();

    return AppPage(
      title: course.title,
      subtitle: '${course.code} · ${course.term}'
          '${course.teacherName != null ? ' · ${course.teacherName}' : ''}',
      onRefresh: _load,
      actions: [
        if (managesCourse(user, course))
          FilledButton.icon(
            key: const Key('assignment-create'),
            onPressed: () => _create(course),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New assignment'),
          ),
        OutlinedButton.icon(
          key: const Key('course-chat'),
          onPressed: () => context.go('/chat?course=${course.id}'),
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          label: const Text('Class chat'),
        ),
        if (user?.isStudent == false)
          OutlinedButton.icon(
            onPressed: () => context.go('/attendance/mark?course=${course.id}'),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Mark attendance'),
          ),
      ],
      children: [
        _BackLink(),
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            StatTile(
                label: 'Students',
                value: '${course.studentCount}',
                icon: Icons.groups_outlined),
            StatTile(
                label: 'Open assignments',
                value: '${open.length}',
                icon: Icons.assignment_outlined,
                tone: open.isEmpty ? Tone.success : Tone.warning),
            StatTile(
                label: 'Next due',
                value: open.isEmpty ? '—' : dayMonth(open.first.dueAt),
                icon: Icons.event_outlined,
                tone: Tone.info),
          ],
        ),
        TwoPane(
          primary: SectionCard(
            title: 'Assignments',
            subtitle: '${_assignments.length} total',
            child: _assignments.isEmpty
                ? const EmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No assignments yet')
                : Column(
                    children: [
                      for (final a in [...open, ...closed])
                        AssignmentRow(courseId: course.id, assignment: a),
                    ],
                  ),
          ),
          secondary: SectionCard(
            title: 'People',
            subtitle: '${_people.length} enrolled',
            child: _people.isEmpty
                ? const EmptyState(
                    icon: Icons.groups_outlined, title: 'No students enrolled')
                : Column(
                    children: [
                      for (final p in _people)
                        ListRow(
                          dense: true,
                          leading: Avatar(
                              name: p['displayName']?.toString() ?? '?',
                              size: 32),
                          title: p['displayName']?.toString() ?? 'Student',
                          subtitle: p['rollNumber']?.toString() ??
                              p['email']?.toString(),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _BackLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('back-to-courses'),
        onPressed: () => context.go('/courses'),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text('All courses'),
      ),
    );
  }
}

class AssignmentRow extends StatelessWidget {
  const AssignmentRow(
      {super.key, required this.courseId, required this.assignment});

  final String courseId;
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final (label, tone) = assignmentStatus(a);
    return ListRow(
      key: Key('assignment-${a.id}'),
      leading: IconBadge(icon: Icons.assignment_outlined, tone: tone, size: 36),
      title: a.title,
      subtitle: 'Due ${shortDate(a.dueAt)} · ${clockTime(a.dueAt)}',
      trailing: StatusBadge(label: label, tone: tone),
      onTap: () => context.go('/courses/$courseId/assignments/${a.id}'),
    );
  }
}

/// Like the API: admins manage every course, teachers the ones they teach.
/// Managers create, edit and delete assignments and see drafts.
bool managesCourse(User? user, Course? course) {
  if (user == null) return false;
  if (user.isAdmin) return true;
  return user.isTeacher && course != null && course.teacherId == user.id;
}

(String, Tone) assignmentStatus(Assignment a) {
  if (a.isDraft) return ('Draft', Tone.info);
  if (!a.isOpen) return ('Closed', Tone.neutral);
  if (a.isOverdue) return ('Overdue', Tone.danger);
  final days = a.dueAt.difference(DateTime.now()).inDays;
  if (days <= 2) return ('Due soon', Tone.warning);
  return ('Open', Tone.success);
}
