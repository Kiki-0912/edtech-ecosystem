import 'dart:io';

import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Admin console contract (`/api/v1/admin/*`) against the local API
/// (http://127.0.0.1:4000), exercised through [ApiService] and the
/// `lib/models/admin.dart` parsers.
///
/// Run the API first: `npm run dev:api` from the repository root. The suite
/// skips itself when the API is unreachable. Every record it creates carries a
/// unique tag and is deleted again, so it can run repeatedly against one API.
void main() {
  final api = ApiService.instance;
  const adminPhone = '+15550001005'; // seeded admin Usman Shahid
  const studentPhone = '+15550001002'; // seeded student Aeliya
  // Seeded local demo password (memory store); not a real credential.
  const password = 'password123';

  // The app defaults to the offline demo backend; force online mode so the
  // suite exercises the real Fastify API.
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding answers every real HTTP request with 400; restore
    // networking so this suite reaches the live API.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api.offlineMode = false;
  });
  tearDown(() {
    api
      ..offlineMode = null
      ..token = null;
  });

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

  /// Signs in as the seeded admin and keeps the token on [api].
  Future<String> signInAdmin() async {
    final data = await api.login(phone: adminPhone, password: password);
    expect((data['user'] as Map<String, dynamic>)['role'], 'admin');
    final token = data['token'] as String;
    api.token = token;
    return token;
  }

  Matcher apiError(int status, String code) => throwsA(isA<ApiException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.code, 'code', code));

  /// Best-effort cleanup: the record may already be gone.
  Future<void> quietly(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (_) {}
  }

  /// A tag unique to this run, so searches only see this test's records.
  String newTag() => 'itest${DateTime.now().microsecondsSinceEpoch}';

  test('seeded admin signs in by phone and reads the overview', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    await signInAdmin();

    final overview = await api.adminOverview();
    expect(['memory', 'postgres'], contains(overview.storage));
    expect(overview.database, 'ok');
    expect(overview.databaseOk, isTrue);
    expect(overview.version, isNotEmpty);
    if (overview.storage == 'postgres') {
      expect(overview.schemaVersion, greaterThanOrEqualTo(2));
    }
    expect(
      overview.serverTime.difference(DateTime.now()).abs(),
      lessThan(const Duration(hours: 1)),
    );
    final counts = overview.counts;
    expect(counts.admins, greaterThanOrEqualTo(1));
    expect(counts.teachers, greaterThanOrEqualTo(1));
    expect(counts.students, greaterThanOrEqualTo(1));
    expect(counts.courses, greaterThanOrEqualTo(1));
    expect(counts.inactiveUsers, greaterThanOrEqualTo(0));
    expect(counts.flaggedReports, greaterThanOrEqualTo(0));

    final admins = await api.adminListUsers(role: 'admin');
    expect(admins, isNotEmpty);
    expect(admins.every((u) => u.isAdmin), isTrue);
    expect(admins.map((u) => u.phone), contains(adminPhone));
  });

  test('user lifecycle: create, list, patch, deactivate, reset, delete',
      () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final adminToken = await signInAdmin();
    final tag = newTag();
    final email = '$tag@test.dev';
    final phone = '+1444${DateTime.now().millisecondsSinceEpoch % 100000000}';

    final created = await api.adminCreateUser(
      displayName: '  Admin ITest $tag  ',
      email: email,
      phone: phone,
      role: 'student',
      password: 'initial-pass',
    );
    try {
      expect(created.id, isNotEmpty);
      expect(created.displayName, 'Admin ITest $tag');
      expect(created.email, email);
      expect(created.phone, phone);
      expect(created.role, 'student');
      expect(created.isActive, isTrue);
      expect(created.isPhoneVerified, isFalse);
      expect(created.courseIds, isEmpty);
      expect(
        created.createdAt.difference(DateTime.now()).abs(),
        lessThan(const Duration(hours: 1)),
      );

      // q matches name, email or phone, case-insensitively.
      final byTag = await api.adminListUsers(query: tag.toUpperCase());
      expect(byTag.map((u) => u.id), [created.id]);
      final byPhone = await api.adminListUsers(query: phone);
      expect(byPhone.map((u) => u.id), [created.id]);
      expect(await api.adminListUsers(role: 'teacher', query: tag), isEmpty);

      // Duplicate email or phone, and bad bodies.
      await expectLater(
        api.adminCreateUser(
            displayName: 'Dup',
            email: email,
            role: 'student',
            password: 'x' * 8),
        apiError(409, 'USER_EXISTS'),
      );
      await expectLater(
        api.adminCreateUser(
            displayName: 'Dup',
            phone: phone,
            role: 'teacher',
            password: 'x' * 8),
        apiError(409, 'USER_EXISTS'),
      );
      await expectLater(
        api.adminCreateUser(
            displayName: 'Short',
            email: 'short-$email',
            role: 'student',
            password: 'x' * 7),
        apiError(400, 'INVALID_BODY'),
      );
      await expectLater(
        api.adminCreateUser(
            displayName: 'No contact', role: 'student', password: 'x' * 8),
        apiError(400, 'INVALID_BODY'),
      );

      final renamed =
          await api.adminUpdateUser(created.id, displayName: 'Renamed $tag');
      expect(renamed.displayName, 'Renamed $tag');
      expect(renamed.email, email);

      // A signed-in user's token stops working once the account is disabled.
      final userLogin = await api.login(email: email, password: 'initial-pass');
      final userToken = userLogin['token'] as String;
      expect(await api.getMe(token: userToken), isNotNull);

      final disabled = await api.adminUpdateUser(created.id, isActive: false);
      expect(disabled.isActive, isFalse);
      expect(
        (await api.adminListUsers(status: 'inactive', query: tag))
            .map((u) => u.id),
        [created.id],
      );
      expect(await api.adminListUsers(status: 'active', query: tag), isEmpty);
      await expectLater(
        api.login(email: email, password: 'initial-pass'),
        apiError(403, 'ACCOUNT_DISABLED'),
      );
      await expectLater(
        api.getMe(token: userToken),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );

      final enabled = await api.adminUpdateUser(created.id, isActive: true);
      expect(enabled.isActive, isTrue);

      // Password reset: the old password stops working, the new one works.
      await expectLater(
        api.adminResetPassword(created.id, 'short'),
        apiError(400, 'INVALID_BODY'),
      );
      await api.adminResetPassword(created.id, 'reset-pass-2');
      await expectLater(
        api.login(email: email, password: 'initial-pass'),
        apiError(401, 'INVALID_CREDENTIALS'),
      );
      final relogin = await api.login(email: email, password: 'reset-pass-2');
      expect(relogin['token'], isNotEmpty);
      api.token = adminToken;

      await api.adminDeleteUser(created.id);
      expect(await api.adminListUsers(query: tag), isEmpty);
      await expectLater(
        api.adminDeleteUser(created.id),
        apiError(404, 'USER_NOT_FOUND'),
      );
      await expectLater(
        api.adminUpdateUser(created.id, displayName: 'Gone'),
        apiError(404, 'USER_NOT_FOUND'),
      );
      await expectLater(
        api.adminResetPassword(created.id, 'another-pass'),
        apiError(404, 'USER_NOT_FOUND'),
      );
    } finally {
      api.token = adminToken;
      await quietly(() => api.adminDeleteUser(created.id));
    }
  });

  test('an admin cannot demote, disable or delete their own account', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    await signInAdmin();
    final me =
        (await api.adminListUsers(role: 'admin', query: adminPhone)).single;

    // CANNOT_MODIFY_SELF, whether or not this is the only active admin.
    final selfBlocked = throwsA(isA<ApiException>()
        .having((e) => e.statusCode, 'statusCode', 409)
        .having((e) => e.code, 'code', 'CANNOT_MODIFY_SELF'));
    await expectLater(api.adminUpdateUser(me.id, role: 'teacher'), selfBlocked);
    await expectLater(api.adminUpdateUser(me.id, isActive: false), selfBlocked);
    await expectLater(api.adminDeleteUser(me.id), selfBlocked);

    final after = (await api.adminListUsers(query: adminPhone)).single;
    expect(after.role, 'admin');
    expect(after.isActive, isTrue);
  });

  test('course lifecycle: create, roster, patch, delete', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    await signInAdmin();
    final tag = newTag();

    // Teachers can only be created by an admin now.
    final teacher = await api.adminCreateUser(
      displayName: 'Teacher $tag',
      email: '$tag-teacher@test.dev',
      role: 'teacher',
      password: 'teacher-pass',
    );
    final s1 = await api.adminCreateUser(
      displayName: 'Student One $tag',
      email: '$tag-s1@test.dev',
      role: 'student',
      password: 'student-pass',
    );
    final s2 = await api.adminCreateUser(
      displayName: 'Student Two $tag',
      email: '$tag-s2@test.dev',
      role: 'student',
      password: 'student-pass',
    );
    AdminCourse? course;
    Future<AdminUser> reload(AdminUser user) async =>
        (await api.adminListUsers(query: user.email)).single;

    try {
      expect(teacher.isTeacher, isTrue);

      await expectLater(
        api.adminCreateCourse(
            title: 'Bad', code: 'BAD 1', term: 'Fall 2026', teacherId: s1.id),
        apiError(400, 'INVALID_TEACHER'),
      );
      await expectLater(
        api.adminCreateCourse(
            title: ' ',
            code: 'BAD 2',
            term: 'Fall 2026',
            teacherId: teacher.id),
        apiError(400, 'INVALID_BODY'),
      );

      course = await api.adminCreateCourse(
        title: 'Integration $tag',
        code: 'IT $tag',
        term: 'Fall 2026',
        teacherId: teacher.id,
      );
      expect(course.id, isNotEmpty);
      expect(course.title, 'Integration $tag');
      expect(course.code, 'IT $tag');
      expect(course.term, 'Fall 2026');
      expect(course.teacherId, teacher.id);
      expect(course.teacherName, 'Teacher $tag');
      expect(course.studentIds, isEmpty);
      expect(course.studentCount, 0);
      expect(course.assignmentCount, 0);
      expect(
        course.createdAt.difference(DateTime.now()).abs(),
        lessThan(const Duration(hours: 1)),
      );

      final listed = (await api.adminListCourses())
          .where((c) => c.id == course!.id)
          .single;
      expect(listed.toJson(), course.toJson());

      // Roster replace keeps users' courseIds in step, both ways.
      var roster = await api.adminSetCourseStudents(course.id, [s1.id, s2.id]);
      expect(roster.studentIds, unorderedEquals([s1.id, s2.id]));
      expect(roster.studentCount, 2);
      expect((await reload(s1)).courseIds, contains(course.id));
      expect((await reload(s2)).courseIds, contains(course.id));

      roster = await api.adminSetCourseStudents(course.id, [s2.id]);
      expect(roster.studentIds, [s2.id]);
      expect(roster.studentCount, 1);
      expect((await reload(s1)).courseIds, isNot(contains(course.id)));
      expect((await reload(s2)).courseIds, contains(course.id));

      await expectLater(
        api.adminSetCourseStudents(course.id, [s2.id, teacher.id]),
        apiError(400, 'INVALID_STUDENT'),
      );
      expect(
        (await api.adminListCourses())
            .where((c) => c.id == course!.id)
            .single
            .studentIds,
        [s2.id],
      );

      final patched =
          await api.adminUpdateCourse(course.id, title: 'Renamed $tag');
      expect(patched.title, 'Renamed $tag');
      expect(patched.code, 'IT $tag');
      expect(patched.studentIds, [s2.id]);
      await expectLater(
        api.adminUpdateCourse(course.id, teacherId: s1.id),
        apiError(400, 'INVALID_TEACHER'),
      );

      // A teacher still assigned to a course cannot be deleted.
      await expectLater(
        api.adminDeleteUser(teacher.id),
        apiError(409, 'USER_IN_USE'),
      );

      await api.adminDeleteCourse(course.id);
      expect(
        (await api.adminListCourses()).map((c) => c.id),
        isNot(contains(course.id)),
      );
      expect((await reload(s2)).courseIds, isNot(contains(course.id)));
      await expectLater(
        api.adminDeleteCourse(course.id),
        apiError(404, 'COURSE_NOT_FOUND'),
      );
      await expectLater(
        api.adminUpdateCourse(course.id, title: 'Gone'),
        apiError(404, 'COURSE_NOT_FOUND'),
      );
      await expectLater(
        api.adminSetCourseStudents(course.id, const []),
        apiError(404, 'COURSE_NOT_FOUND'),
      );

      // With the course gone the teacher can be deleted.
      await api.adminDeleteUser(teacher.id);
    } finally {
      final created = course;
      if (created != null) {
        await quietly(() => api.adminDeleteCourse(created.id));
      }
      for (final user in [s1, s2, teacher]) {
        await quietly(() => api.adminDeleteUser(user.id));
      }
    }
  });

  test('integrity rows parse, filter on flags and sort newest first', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    await signInAdmin();

    final all = await api.adminIntegrity();
    final flagged = await api.adminIntegrity(flaggedOnly: true);
    final overview = await api.adminOverview();

    String key(IntegrityRow r) => '${r.studentId}/${r.assignmentId}';
    expect(flagged.every((r) => r.isFlagged), isTrue);
    expect(all.map(key).toSet(), containsAll(flagged.map(key)));
    expect(all.where((r) => r.isFlagged).length, flagged.length);
    expect(overview.counts.flaggedReports, flagged.length);
    for (final row in all) {
      expect(row.studentId, isNotEmpty);
      expect(row.assignmentId, isNotEmpty);
      expect(row.courseId, isNotEmpty);
      expect(row.score, inInclusiveRange(0, 100));
      expect(row.flags, isNotEmpty);
    }
    for (var i = 1; i < all.length; i++) {
      expect(
        all[i - 1].computedAt.isBefore(all[i].computedAt),
        isFalse,
        reason: 'rows must be newest computedAt first',
      );
    }
  });

  test('a student token gets 403 and no token gets 401 on admin routes',
      () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final login = await api.login(phone: studentPhone, password: password);
    expect((login['user'] as Map<String, dynamic>)['role'], 'student');
    api.token = login['token'] as String;

    await expectLater(api.adminOverview(), apiError(403, 'FORBIDDEN'));
    await expectLater(api.adminListUsers(), apiError(403, 'FORBIDDEN'));
    await expectLater(api.adminIntegrity(), apiError(403, 'FORBIDDEN'));
    final tag = newTag();
    await expectLater(
      api.adminCreateUser(
          displayName: 'Sneaky $tag',
          email: '$tag@test.dev',
          role: 'admin',
          password: 'sneaky-pass'),
      apiError(403, 'FORBIDDEN'),
    );

    api.token = null;
    await expectLater(api.adminOverview(), apiError(401, 'UNAUTHORIZED'));

    // Nothing was created by the forbidden request.
    await signInAdmin();
    expect(await api.adminListUsers(query: tag), isEmpty);
  });
}
