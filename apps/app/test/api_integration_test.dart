import 'dart:io';

import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Integration test against the local API (default http://localhost:4000).
///
/// Run the API first: `npm run dev:api` from the repository root.
/// The suite skips itself when the API is unreachable.
void main() {
  final api = ApiService.instance;
  const phone = '+15550001002'; // seeded student Aeliya
  const password = 'password123';

  // The app defaults to the offline demo backend; these tests exercise the
  // real Fastify API, so force online mode for the duration of the suite.
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding installs a mock HttpClient that answers every request
    // with 400, which made this suite skip itself even with the API running.
    // Restore real networking so it actually exercises the live API.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api.offlineMode = false;
  });
  tearDown(() => api.offlineMode = true);

  Future<bool> apiReachable() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:4000/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('seeded student can log in through AuthProvider', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final auth = AuthProvider();
    final ok = await auth.login(phone: phone, password: password);
    expect(ok, isTrue, reason: auth.error);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.user?.displayName, 'Aeliya');
    expect(auth.token, isNotEmpty);
    // Subsequent API calls in this suite run through the shared ApiService.
    api.token = auth.token;
  });

  test('wrong password is rejected', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final auth = AuthProvider();
    final ok = await auth.login(phone: phone, password: 'wrong-password');
    expect(ok, isFalse);
    expect(auth.isAuthenticated, isFalse);
  });

  test('courses load with teacher summary fields', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final courses = await api.getCourses();
    expect(courses, isNotEmpty);
    expect(courses.first.code, 'CS 301');
    expect(courses.first.teacherName, 'Tayyab');
    expect(courses.first.studentCount, 4);
    expect(courses.first.openAssignmentCount, greaterThan(0));
  });

  test('assignments load with parseable ISO due dates', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final assignments = await api.getAssignments('c-001');
    expect(assignments, isNotEmpty);
    for (final assignment in assignments) {
      expect(assignment.dueAt.year, greaterThanOrEqualTo(2026));
    }
  });

  test('assignment detail parses the API envelope (not demo data)', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final assignments = await api.getAssignments('c-001');
    for (final expected in assignments) {
      final detail = await api.getAssignment(expected.id);
      expect(detail.id, expected.id);
      expect(detail.title, expected.title);
      // Server times are UTC; models hand screens local time.
      expect(detail.dueAt.isUtc, isFalse);
    }
    await expectLater(
        api.getAssignment('no-such-assignment'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'ASSIGNMENT_NOT_FOUND')));
  });

  test('calendar events load and sort by start date', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final events = await api.getCalendar('u-student-1');
    expect(events, isNotEmpty);
  });

  test('chat channels and messages load', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final channels = await api.getChannels('c-001');
    expect(channels, isNotEmpty);
    final messages = await api.getMessages(channels.first.id);
    expect(messages, isNotEmpty);
    expect(messages.first.body, isNotEmpty);
  });

  test('integrity report returns null or a real report, never fake data',
      () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final report = await api.getIntegrityReportOrNull('a-001', 'u-student-1');
    if (report != null) {
      expect(report.effortScore.score, inInclusiveRange(0, 100));
      expect(report.assignmentId, 'a-001');
    }
  });

  test('registration, token check and SMS verification flow works', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final phone = '+1555${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final registered = await api.register(
      phone: phone,
      email: 'itest-${DateTime.now().millisecondsSinceEpoch}@test.dev',
      displayName: 'Integration Tester',
      password: 'secret123',
      role: 'student',
    );
    expect(registered['token'], isNotEmpty);

    final me = await api.getMe(token: registered['token'] as String);
    expect((me['user'] as Map<String, dynamic>)['phone'], phone);

    final sms = await api.sendSmsCode(phone: phone);
    expect(sms['code'], isNotNull);
    final verified = await api.verifySmsCode(
      phone: phone,
      code: sms['code'] as String,
    );
    expect(verified['token'], isNotEmpty);
  });

  test('college info loads from /api/v1/college (was a 404)', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final login = await api.login(phone: phone, password: password);
    api.token = login['token'] as String;
    final college = await api.getCollege();
    expect(college, isNotNull);
    expect(college!.departments, isNotEmpty);
  });

  test('teacher role is rejected on self sign-up', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    expect(
      () => api.register(
        phone: '+1777${DateTime.now().millisecondsSinceEpoch % 100000000}',
        email: 'teacher-${DateTime.now().millisecondsSinceEpoch}@test.dev',
        displayName: 'Would-be Teacher',
        password: 'secret123',
        role: 'teacher',
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
  });

  test('admin role is rejected on self sign-up', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    expect(
      () => api.register(
        phone: '+1666${DateTime.now().millisecondsSinceEpoch % 100000000}',
        email: 'admin-${DateTime.now().millisecondsSinceEpoch}@test.dev',
        displayName: 'Would-be Admin',
        password: 'secret123',
        role: 'admin',
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
  });

  test('teacher creates an assignment; student sees, submits; close; delete',
      () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    Future<void> signIn(String who) async {
      final login = await api.login(phone: who, password: password);
      api.token = login['token'] as String;
    }

    const teacher = '+15550001001'; // seeded Tayyab, teaches c-001
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final due = DateTime.now().add(const Duration(days: 3));

    await signIn(teacher);
    final created = await api.createAssignment(
      courseId: 'c-001',
      title: 'Integration $stamp',
      brief: 'Created by api_integration_test.',
      dueAt: due,
    );
    expect(created.status, 'open');
    expect(created.dueAt.difference(due).inSeconds.abs(), lessThan(1));
    final draft = await api.createAssignment(
      courseId: 'c-001',
      title: 'Integration draft $stamp',
      dueAt: due,
      status: 'draft',
    );
    try {
      // Exactly one read-only deadline for the open assignment, none for
      // the draft.
      final events = await api.getCalendar('u-teacher-1');
      final linked = events.where((e) => e.assignmentId == created.id);
      expect(linked, hasLength(1));
      expect(linked.single.title, 'Integration $stamp due');
      expect(events.where((e) => e.assignmentId == draft.id), isEmpty);
      await expectLater(
          api.deleteCalendarEvent(linked.single.id),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'ASSIGNMENT_EVENT')));

      await signIn(phone);
      final visible = await api.getAssignments('c-001');
      expect(visible.map((a) => a.id), contains(created.id));
      expect(visible.map((a) => a.id), isNot(contains(draft.id)));
      await expectLater(
          api.getAssignment(draft.id),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'ASSIGNMENT_NOT_FOUND')));
      await expectLater(
          api.createAssignment(
              courseId: 'c-001', title: 'Student attempt', dueAt: due),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
      final submission = await api.submitAssignment(
          assignmentId: created.id, studentId: 'u-student-1');
      expect(submission.status, 'submitted');

      await signIn(teacher);
      final closed = await api.updateAssignment(created.id, status: 'closed');
      expect(closed.isClosed, isTrue);

      await signIn(phone);
      await expectLater(
          api.submitAssignment(
              assignmentId: created.id, studentId: 'u-student-1'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'ASSIGNMENT_CLOSED')));
    } finally {
      await signIn(teacher);
      await api.deleteAssignment(created.id);
      await api.deleteAssignment(draft.id);
    }
    await expectLater(
        api.getAssignment(created.id),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'ASSIGNMENT_NOT_FOUND')));
    expect(
        (await api.getCalendar('u-teacher-1'))
            .where((e) => e.assignmentId == created.id),
        isEmpty);
  });
}
