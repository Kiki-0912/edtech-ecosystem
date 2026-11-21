import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/attendance.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/services/api_service.dart';

/// Progress of one open assignment: how many students have submitted.
class AssignmentProgress {
  const AssignmentProgress({
    required this.assignment,
    required this.course,
    required this.submitted,
    required this.total,
  });

  final Assignment assignment;
  final Course course;
  final int submitted;
  final int total;

  double get ratio => total == 0 ? 0 : submitted / total;
}

/// Attendance totals by status.
class AttendanceSummary {
  const AttendanceSummary({
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.excused = 0,
  });

  factory AttendanceSummary.of(Iterable<AttendanceRecord> records) {
    var p = 0, l = 0, a = 0, e = 0;
    for (final r in records) {
      switch (r.status) {
        case 'present':
          p++;
        case 'late':
          l++;
        case 'absent':
          a++;
        case 'excused':
          e++;
      }
    }
    return AttendanceSummary(present: p, late: l, absent: a, excused: e);
  }

  final int present;
  final int late;
  final int absent;
  final int excused;

  int get total => present + late + absent + excused;

  /// Share of sessions attended (present or late), 0..1.
  double get rate => total == 0 ? 0 : (present + late) / total;

  String get percentLabel => total == 0 ? '—' : '${(rate * 100).round()}%';
}

/// Everything the home dashboards need, loaded once per refresh.
class HomeData {
  HomeData({
    required this.courses,
    required this.events,
    required this.attendance,
    this.studentCount = 0,
    this.departmentCount = 0,
    this.progress = const [],
  });

  final List<Course> courses;
  final List<CalendarEvent> events;
  final List<AttendanceRecord> attendance;
  final int studentCount;
  final int departmentCount;
  final List<AssignmentProgress> progress;

  static Future<HomeData> load(User user) async {
    final api = ApiService.instance;
    final results = await Future.wait([
      api.getCourses(),
      api.getCalendar(user.id),
      api.getAttendanceRecords().catchError((_) => <AttendanceRecord>[]),
    ]);
    final allCourses = results[0] as List<Course>;
    final events = (results[1] as List<CalendarEvent>)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final attendance = results[2] as List<AttendanceRecord>;

    final courses = myCourses(user, allCourses);

    if (user.isAdmin) {
      final counts = await Future.wait([
        api.getStudents().then((s) => s.length).catchError((_) => 0),
        api.getDepartments().then((d) => d.length).catchError((_) => 0),
      ]);
      return HomeData(
        courses: allCourses,
        events: events,
        attendance: attendance,
        studentCount: counts[0],
        departmentCount: counts[1],
      );
    }

    if (user.isTeacher) {
      return HomeData(
        courses: courses,
        events: events,
        attendance: attendance
            .where((r) => courses.any((c) => c.id == r.courseId))
            .toList(),
        studentCount: courses.fold(0, (sum, c) => sum + c.studentCount),
        progress: await _progressFor(courses),
      );
    }

    return HomeData(
      courses: courses,
      events: events,
      attendance: attendance.where((r) => r.studentId == user.id).toList(),
    );
  }

  static Future<List<AssignmentProgress>> _progressFor(
      List<Course> courses) async {
    final api = ApiService.instance;
    final out = <AssignmentProgress>[];
    final perCourse = await Future.wait(courses.map(
        (c) => api.getAssignments(c.id).catchError((_) => <Assignment>[])));
    final open = <(Assignment, Course)>[
      for (var i = 0; i < courses.length; i++)
        for (final a in perCourse[i])
          if (a.isOpen) (a, courses[i]),
    ]..sort((x, y) => x.$1.dueAt.compareTo(y.$1.dueAt));

    final rosters = await Future.wait(open.take(5).map((pair) =>
        api.getRoster(pair.$1.id).catchError((_) => <Map<String, dynamic>>[])));
    for (var i = 0; i < rosters.length; i++) {
      final roster = rosters[i];
      out.add(AssignmentProgress(
        assignment: open[i].$1,
        course: open[i].$2,
        submitted: roster
            .where((r) => r['status'] == 'submitted' || r['status'] == 'late')
            .length,
        total: roster.length,
      ));
    }
    return out;
  }

  AttendanceSummary get attendanceSummary => AttendanceSummary.of(attendance);

  List<CalendarEvent> eventsOn(DateTime day) =>
      events.where((e) => isSameDay(e.startsAt, day)).toList();

  /// Assignment/quiz events in the next [days] days (from today).
  List<CalendarEvent> deadlinesWithin(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(Duration(days: days));
    return events
        .where((e) =>
            (e.kind == 'assignment' || e.kind == 'quiz') &&
            !e.startsAt.isBefore(start) &&
            e.startsAt.isBefore(end))
        .toList();
  }

  /// Attendance rate per day for the last [days] days (oldest first).
  List<(DateTime, AttendanceSummary)> dailyAttendance(int days) {
    final now = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i));
          final key = isoDate(day);
          return (
            day,
            AttendanceSummary.of(attendance.where((r) => r.date == key))
          );
        }(),
    ];
  }
}

/// Courses the user belongs to (teaches or is enrolled in).
List<Course> myCourses(User user, List<Course> all) {
  if (user.isAdmin) return all;
  final mine = all
      .where((c) =>
          user.courseIds.contains(c.id) ||
          c.teacherId == user.id ||
          c.studentIds.contains(user.id))
      .toList();
  return mine;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
}
