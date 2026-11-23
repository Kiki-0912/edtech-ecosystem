import 'dart:convert';

import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/login_screen.dart';
import 'package:edtech_app/auth/verify_sms_screen.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/offline_client.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signs in offline as a seeded account (the stored session is the caller).
Future<void> session(String id, String role) async {
  SharedPreferences.setMockInitialValues({
    'auth_token': OfflineClient.legacyToken,
    'auth_user': jsonEncode({
      'id': id,
      'displayName': id,
      'email': '$id@example.edu',
      'phone': '',
      'role': role,
      'courseIds': <String>[],
      'createdAt': '2026-07-01T00:00:00.000Z',
    }),
  });
}

/// A raw offline request, for status codes ApiService does not expose.
Future<(int, Map<String, dynamic>)> call(String method, String path,
    {Object? body}) async {
  final request = http.Request(method, Uri.parse('http://offline/api/v1$path'));
  if (body != null) request.body = jsonEncode(body);
  final response =
      await http.Response.fromStream(await OfflineClient().send(request));
  return (
    response.statusCode,
    jsonDecode(response.body) as Map<String, dynamic>
  );
}

Matcher apiError(int status, String code) => throwsA(isA<ApiException>()
    .having((e) => e.statusCode, 'status', status)
    .having((e) => e.code, 'code', code));

void main() {
  final api = ApiService.instance;

  setUp(() {
    api
      ..offlineMode = true
      ..httpClientOverride = null
      ..token = null;
  });
  tearDown(() {
    api
      ..offlineMode = null
      ..httpClientOverride = null
      ..token = null;
  });

  group('assignment detail', () {
    test('online: parses the { assignment, course } envelope', () async {
      api
        ..offlineMode = false
        ..httpClientOverride = MockClient((request) async {
          expect(request.url.path, '/api/v1/assignments/a-9');
          return http.Response(
              jsonEncode({
                'data': {
                  'assignment': {
                    'id': 'a-9',
                    'courseId': 'c-1',
                    'title': 'Real assignment',
                    'brief': 'From the server',
                    'dueAt': '2026-12-01T09:00:00.000Z',
                    'status': 'open',
                    'createdAt': '2026-11-01T09:00:00.000Z',
                  },
                  'course': {'id': 'c-1'},
                },
              }),
              200);
        });
      final assignment = await api.getAssignment('a-9');
      expect(assignment.id, 'a-9');
      expect(assignment.title, 'Real assignment');
    });

    test('online: a 404 is an error, never the demo assignment', () async {
      api
        ..offlineMode = false
        ..httpClientOverride = MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'ASSIGNMENT_NOT_FOUND',
                'message': 'Assignment not found'
              }
            }),
            404));
      await expectLater(
          api.getAssignment('nope'), apiError(404, 'ASSIGNMENT_NOT_FOUND'));
    });

    test('online: an unreachable server is an error, not demo data', () async {
      api
        ..offlineMode = false
        ..httpClientOverride = MockClient(
            (request) async => throw http.ClientException('down', request.url));
      await expectLater(api.getCourses(), throwsA(isA<http.ClientException>()));
      await expectLater(
          api.getCalendar(null), throwsA(isA<http.ClientException>()));
    });

    test('offline returns the same envelope and the right assignment',
        () async {
      await session('u-student-1', 'student');
      final (status, body) = await call('GET', '/assignments/a2');
      expect(status, 200);
      final data = body['data'] as Map<String, dynamic>;
      expect((data['assignment'] as Map)['title'], 'Usability Study Report');
      expect((data['course'] as Map)['id'], 'c-cs301');
      expect((await api.getAssignment('a2')).title, 'Usability Study Report');
    });

    test('offline uses the API not-found codes', () async {
      await session('u-admin-1', 'admin');
      await expectLater(
          api.getAssignment('nope'), apiError(404, 'ASSIGNMENT_NOT_FOUND'));
      await expectLater(
          api.getAssignments('nope'), apiError(404, 'COURSE_NOT_FOUND'));
      await expectLater(
          api.getChannels('nope'), apiError(404, 'COURSE_NOT_FOUND'));
    });
  });

  group('offline permissions mirror the API', () {
    test('a request without a session is 401', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await expectLater(api.getCourses(), apiError(401, 'UNAUTHORIZED'));
    });

    test('calendar writes are admin/teacher only', () async {
      await session('u-student-1', 'student');
      await expectLater(
          api.createCalendarEvent(
              title: 'Party', kind: 'class', startsAt: DateTime.now()),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.deleteCalendarEvent('ev1'), apiError(403, 'FORBIDDEN'));
    });

    test('a teacher cannot add or edit events of courses they do not teach',
        () async {
      await session('u-teacher-1', 'teacher');
      await expectLater(
          api.createCalendarEvent(
              title: 'BST',
              kind: 'class',
              startsAt: DateTime.now(),
              courseId: 'c-cs210'),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.updateCalendarEvent(
              id: 'ev3',
              title: 'Moved',
              kind: 'class',
              startsAt: DateTime.now()),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.updateCalendarEvent(
              id: 'missing',
              title: 'X',
              kind: 'class',
              startsAt: DateTime.now()),
          apiError(404, 'EVENT_NOT_FOUND'));
      final (status, body) = await call('POST', '/calendar',
          body: {'title': 'No start', 'kind': 'class'});
      expect(status, 400);
      expect((body['error'] as Map)['code'], 'INVALID_BODY');
    });

    test('campus-wide (course-less) events are admin-only, like the API',
        () async {
      await session('u-teacher-1', 'teacher');
      await expectLater(
          api.createCalendarEvent(
              title: 'Open day', kind: 'institution', startsAt: DateTime.now()),
          apiError(403, 'FORBIDDEN'));
      final own = await api.createCalendarEvent(
          title: 'Lab',
          kind: 'class',
          startsAt: DateTime.now(),
          courseId: 'c-cs301');
      final moved = await api.updateCalendarEvent(
          id: own.id,
          title: 'Lab (moved)',
          kind: 'class',
          startsAt: DateTime.now(),
          courseId: 'c-cs301');
      expect(moved.title, 'Lab (moved)');

      await session('u-admin-1', 'admin');
      final campus = await api.createCalendarEvent(
          title: 'Open day', kind: 'institution', startsAt: DateTime.now());
      expect(campus.courseId, isNull);
    });

    test('notes: staff create as themselves; author or admin edit', () async {
      await session('u-student-1', 'student');
      await expectLater(
          api.createTeacherNote(
              courseId: 'c-cs301',
              bookName: 'B',
              courseCode: 'C',
              title: 'T',
              content: ''),
          apiError(403, 'FORBIDDEN'));

      await session('u-teacher-1', 'teacher');
      final note = await api.createTeacherNote(
          courseId: 'c-cs301',
          bookName: 'B',
          courseCode: 'C',
          title: 'Mine',
          content: '');
      expect(note.authorId, 'u-teacher-1');
      // note-2 was written by u-teacher-2.
      await expectLater(api.updateTeacherNote(id: 'note-2', title: 'Hijack'),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.deleteTeacherNote('note-2'), apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.createTeacherNote(
              courseId: 'c-cs301',
              bookName: '',
              courseCode: 'C',
              title: 'T',
              content: ''),
          apiError(400, 'INVALID_BODY'));

      await session('u-admin-1', 'admin');
      final edited = await api.updateTeacherNote(id: note.id, title: 'Admin');
      expect(edited.title, 'Admin');
      await api.deleteTeacherNote(note.id);
    });

    test('students, departments and imports are admin only', () async {
      await session('u-teacher-1', 'teacher');
      await expectLater(
          api.createStudent(displayName: 'X', email: 'x@e.edu', phone: ''),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.deleteStudent('u-student-2'), apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.createDepartment(
              name: 'X', code: 'X', category: '3 Years', durationMonths: 36),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.enrollStudentInDepartment(
              studentId: 'u-student-2', departmentId: 'dept-eee'),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.importStudentsFromExcel(courseId: 'c-cs301', rows: const []),
          apiError(403, 'FORBIDDEN'));
      // Exports stay available to teachers.
      expect((await api.exportStudentsToExcel())['rows'], isNotEmpty);

      await session('u-admin-1', 'admin');
      await expectLater(
          api.createStudent(displayName: 'X', email: '', phone: ''),
          apiError(400, 'INVALID_BODY'));
      await expectLater(
          api.createStudent(
              displayName: 'X',
              email: 'x@e.edu',
              phone: '',
              courseId: 'c-none'),
          apiError(400, 'INVALID_REFERENCE'));
      await expectLater(
          api.deleteStudent('u-nobody'), apiError(404, 'NOT_FOUND'));
    });

    test('attendance writes are staff only, for courses they manage', () async {
      await session('u-student-1', 'student');
      await expectLater(
          api.markAttendance(
              courseId: 'c-cs301',
              studentId: 'u-student-1',
              date: '2026-09-01',
              status: 'present'),
          apiError(403, 'FORBIDDEN'));
      // Students only ever see their own records.
      final mine = await api.getAttendanceRecords();
      expect(mine.every((r) => r.studentId == 'u-student-1'), isTrue);

      await session('u-teacher-1', 'teacher');
      await expectLater(
          api.markAttendance(
              courseId: 'c-cs210',
              studentId: 'u-student-4',
              date: '2026-09-01',
              status: 'present'),
          apiError(403, 'FORBIDDEN'));
      await expectLater(
          api.markAttendance(
              courseId: 'c-cs301',
              studentId: 'u-student-1',
              date: '2026-09-01',
              status: 'asleep'),
          apiError(400, 'INVALID_BODY'));
      final record = await api.markAttendance(
          courseId: 'c-cs301',
          studentId: 'u-student-1',
          date: '2026-09-01',
          status: 'late');
      expect(record.markedBy, 'u-teacher-1');
    });

    test('chat: author is the caller, members only, no student announcements',
        () async {
      await session('u-student-1', 'student');
      final message = await api.postMessage(
          channelId: 'ch-general', authorId: 'u-teacher-1', body: ' Hi ');
      expect(message.authorId, 'u-student-1');
      expect(message.body, 'Hi');
      await expectLater(
          api.postMessage(
              channelId: 'ch-general', authorId: 'u-student-1', body: '  '),
          apiError(400, 'INVALID_BODY'));
      await expectLater(
          api.postMessage(
              channelId: 'ch-announce', authorId: 'u-student-1', body: 'Hi'),
          apiError(403, 'ANNOUNCEMENT_RESTRICTED'));
      await expectLater(
          api.getMessages('ch-nope'), apiError(404, 'CHANNEL_NOT_FOUND'));

      // u-student-4 is only in CS 210.
      await session('u-student-4', 'student');
      await expectLater(
          api.getMessages('ch-general'), apiError(403, 'NOT_A_MEMBER'));
      await expectLater(
          api.postMessage(
              channelId: 'ch-general', authorId: 'u-student-4', body: 'Hi'),
          apiError(403, 'NOT_A_MEMBER'));

      await session('u-teacher-1', 'teacher');
      final announcement = await api.postMessage(
          channelId: 'ch-announce', authorId: 'x', body: 'Quiz Friday');
      expect(announcement.authorId, 'u-teacher-1');
    });

    test('submissions: own id, enrolment, and 201 then 200', () async {
      await session('u-student-3', 'student');
      final (created, first) = await call('POST', '/assignments/a2/submissions',
          body: {'attachments': <Object>[]});
      expect(created, 201);
      expect((first['data'] as Map)['studentId'], 'u-student-3');
      final (updated, _) = await call('POST', '/assignments/a2/submissions',
          body: {'studentId': 'u-student-3', 'attachments': <Object>[]});
      expect(updated, 200);

      await expectLater(
          api.submitAssignment(assignmentId: 'a2', studentId: 'u-student-2'),
          apiError(403, 'FORBIDDEN'));
      // u-student-3 is not in CS 210 (a3).
      await expectLater(
          api.submitAssignment(assignmentId: 'a3', studentId: 'u-student-3'),
          apiError(403, 'NOT_ENROLLED'));
      await expectLater(
          api.submitAssignment(assignmentId: 'nope', studentId: 'u-student-3'),
          apiError(404, 'ASSIGNMENT_NOT_FOUND'));

      await session('u-admin-1', 'admin');
      await expectLater(
          api.submitAssignment(assignmentId: 'a2', studentId: 'u-ghost'),
          apiError(404, 'STUDENT_NOT_FOUND'));
    });

    test('the roster is for the course teacher and admins', () async {
      await session('u-student-1', 'student');
      await expectLater(api.getRoster('a1'), apiError(403, 'FORBIDDEN'));
      await session('u-teacher-1', 'teacher');
      expect(await api.getRoster('a1'), hasLength(3));
      // CS 210 is taught by someone else.
      await expectLater(api.getRoster('a3'), apiError(403, 'FORBIDDEN'));
    });
  });

  group('offline behaviour matches the API', () {
    test('department enrolment adds instead of moving', () async {
      await session('u-admin-1', 'admin');
      await api.enrollStudentInDepartment(
          studentId: 'u-student-1', departmentId: 'dept-eee');
      // Enrolling twice is harmless.
      await api.enrollStudentInDepartment(
          studentId: 'u-student-1', departmentId: 'dept-eee');
      final ids = (await api.getStudentDepartments('u-student-1'))
          .map((d) => d['id'])
          .toList();
      expect(ids, containsAll(<String>['dept-cit', 'dept-eee']));
      expect(ids.where((id) => id == 'dept-eee'), hasLength(1));
      await expectLater(
          api.enrollStudentInDepartment(
              studentId: 'u-student-1', departmentId: 'dept-none'),
          apiError(400, 'INVALID_REFERENCE'));
    });

    test('the calendar is scoped to the caller\'s courses', () async {
      Future<Set<String?>> courses(String id, String role) async {
        await session(id, role);
        return (await api.getCalendar(id)).map((e) => e.courseId).toSet();
      }

      // u-teacher-1 teaches CS 301 only.
      final teacher = await courses('u-teacher-1', 'teacher');
      expect(teacher, contains('c-cs301'));
      expect(teacher, isNot(contains('c-cs210')));
      expect(teacher, contains(null));
      // u-student-4 is enrolled in CS 210 only.
      final student = await courses('u-student-4', 'student');
      expect(student, contains('c-cs210'));
      expect(student, isNot(contains('c-cs301')));
      final admin = await courses('u-admin-1', 'admin');
      expect(admin, containsAll(<String>['c-cs301', 'c-cs210', 'c-des150']));
    });

    test('updating an event keeps its course', () async {
      await session('u-teacher-1', 'teacher');
      final updated = await api.updateCalendarEvent(
          id: 'ev1',
          title: 'HCI Quiz 1 (moved)',
          kind: 'quiz',
          startsAt: DateTime.now().add(const Duration(days: 4)));
      expect(updated.courseId, 'c-cs301');
      expect(updated.title, 'HCI Quiz 1 (moved)');
    });

    test('sign-in uses the seeded account\'s role, else the demo admin',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      Future<Map<String, dynamic>> user(String phone) async =>
          (await api.login(phone: phone, password: 'password123'))['user']
              as Map<String, dynamic>;

      final teacher = await user('+15550001001');
      expect(teacher['id'], 'u-teacher-1');
      expect(teacher['role'], 'teacher');
      expect(teacher['courseIds'], ['c-cs301']);
      final student = await user('+15550001003');
      expect(student['id'], 'u-student-2');
      expect(student['role'], 'student');
      expect((await user('+15550009999'))['role'], 'admin');

      final byEmail =
          await api.login(email: 'Aeliya@example.edu', password: 'password123');
      expect((byEmail['user'] as Map)['id'], 'u-student-1');
    });

    test('/auth/me reflects the token\'s user', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final login =
          await api.login(phone: '+15550001001', password: 'password123');
      final token = login['token'] as String;
      // A different stored session must not change who the token is.
      await session('u-admin-1', 'admin');
      final me = await api.getMe(token: token);
      expect((me['user'] as Map)['id'], 'u-teacher-1');
      expect((me['user'] as Map)['role'], 'teacher');
      await expectLater(
          api.getMe(token: 'garbage'), apiError(401, 'UNAUTHORIZED'));
    });

    test('AuthProvider signs a teacher in as a teacher', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final auth = AuthProvider();
      await auth.init();
      expect(await auth.login(phone: '+15550001001', password: 'password123'),
          isTrue);
      expect(auth.user?.role, 'teacher');
    });
  });

  group('times', () {
    test('server UTC timestamps become local time in models', () {
      final event = CalendarEvent.fromJson({
        'id': 'e',
        'courseId': null,
        'title': 'T',
        'kind': 'class',
        'startsAt': '2026-09-01T09:30:00.000Z',
        'endsAt': '2026-09-01T10:30:00.000Z',
      });
      final expected = DateTime.utc(2026, 9, 1, 9, 30).toLocal();
      expect(event.startsAt.isUtc, isFalse);
      expect(event.startsAt, expected);
      expect(event.startsAt.hour, expected.hour);
      expect(event.endsAt!.isUtc, isFalse);
      expect(parseServerTime(null), isNull);
      expect(parseServerTime('not a date'), isNull);
    });

    test('isSameDay compares local calendar days', () {
      final local = DateTime(2026, 9, 1, 12);
      expect(isSameDay(local.toUtc(), local), isTrue);
      expect(isSameDay(local, DateTime(2026, 9, 2, 12)), isFalse);
    });

    test('calendar writes send UTC ISO strings', () async {
      final bodies = <Map<String, dynamic>>[];
      api
        ..offlineMode = false
        ..httpClientOverride = MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              jsonEncode({
                'data': {
                  'id': 'e1',
                  'courseId': 'c-1',
                  'title': 'T',
                  'kind': 'class',
                  'startsAt': '2026-09-01T09:30:00.000Z',
                  'endsAt': null,
                },
              }),
              200);
        });
      final start = DateTime(2026, 9, 1, 9, 30);
      await api.createCalendarEvent(
          title: 'T',
          kind: 'class',
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)));
      await api.updateCalendarEvent(
          id: 'e1', title: 'T', kind: 'class', startsAt: start);
      for (final body in bodies) {
        expect(body['startsAt'], start.toUtc().toIso8601String());
        expect(body['startsAt'] as String, endsWith('Z'));
      }
      expect(bodies.first['endsAt'] as String, endsWith('Z'));
      // An update without a course keeps the event's course.
      expect(bodies.last.containsKey('courseId'), isFalse);
    });
  });

  test('User.fromJson reads isPhoneVerified (and the old snake_case)', () {
    Map<String, dynamic> json(Map<String, dynamic> extra) => {
          'id': 'u',
          'displayName': 'U',
          'email': 'u@e.edu',
          'role': 'student',
          'courseIds': <String>[],
          ...extra,
        };
    expect(
        User.fromJson(json({'isPhoneVerified': true})).isPhoneVerified, isTrue);
    expect(User.fromJson(json({'is_phone_verified': true})).isPhoneVerified,
        isTrue);
    expect(User.fromJson(json({})).isPhoneVerified, isFalse);
  });

  group('code sign-in entry point', () {
    Future<void> pump(WidgetTester tester, Widget screen) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final auth = AuthProvider();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ThemeController>.value(
              value: ThemeController.instance),
        ],
        child: MaterialApp(theme: lightTheme, home: screen),
      ));
      await tester.pump();
    }

    testWidgets('offline offers it', (tester) async {
      await pump(tester, const LoginScreen());
      expect(find.byKey(const Key('login-sms')), findsOneWidget);
    });

    testWidgets('online hides it (no SMS provider) and explains why',
        (tester) async {
      api.offlineMode = false;
      await pump(tester, const LoginScreen());
      expect(find.byKey(const Key('login-sms')), findsNothing);

      await pump(tester, const VerifySmsScreen());
      expect(find.byKey(const Key('sms-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('sms-send')), findsNothing);
    });
  });
}
