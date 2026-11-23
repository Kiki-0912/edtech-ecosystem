import 'dart:convert';

import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_admin_api.dart';

void main() {
  final api = ApiService.instance;

  setUp(() => api
    ..offlineMode = false
    ..token = 'admin-token');
  tearDown(() => api
    ..httpClientOverride = null
    ..offlineMode = null
    ..token = null
    ..onUnauthorized = null);

  /// Answers every request with [status] and [body], recording the request.
  List<http.Request> respond(int status, Object body) {
    final seen = <http.Request>[];
    api.httpClientOverride = MockClient((request) async {
      seen.add(request);
      return http.Response(body is String ? body : jsonEncode(body), status,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    return seen;
  }

  group('admin requests', () {
    test('list users sends filters and the bearer token', () async {
      final seen = respond(200, {
        'data': [
          {
            'id': 'u-1',
            'displayName': 'Ada',
            'email': 'ada@example.edu',
            'phone': '',
            'role': 'teacher',
            'isActive': false,
            'isPhoneVerified': false,
            'courseIds': ['c-1'],
            'createdAt': '2026-01-02T03:04:05.000Z',
          }
        ]
      });
      final users = await api.adminListUsers(
          role: 'teacher', query: '  ada ', status: 'inactive');
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/admin/users');
      expect(seen.single.url.queryParameters,
          {'role': 'teacher', 'q': 'ada', 'status': 'inactive'});
      expect(seen.single.headers['Authorization'], 'Bearer admin-token');
      expect(users.single.displayName, 'Ada');
      expect(users.single.isActive, isFalse);
      expect(users.single.isTeacher, isTrue);
    });

    test('create user omits empty contact fields', () async {
      final seen = respond(201, {
        'data': {
          'id': 'u-2',
          'displayName': 'Bo',
          'email': '',
          'phone': '+1555',
          'role': 'admin',
          'isActive': true,
          'isPhoneVerified': false,
          'courseIds': <String>[],
          'createdAt': '2026-01-02T03:04:05.000Z',
        }
      });
      final user = await api.adminCreateUser(
          displayName: 'Bo',
          email: '',
          phone: '+1555',
          role: 'admin',
          password: 'longenough');
      expect(seen.single.method, 'POST');
      expect(jsonDecode(seen.single.body), {
        'displayName': 'Bo',
        'phone': '+1555',
        'role': 'admin',
        'password': 'longenough',
      });
      expect(user.isAdmin, isTrue);
    });

    test('every contract route uses the right method and path', () async {
      final course = {
        'id': 'c-1',
        'title': 'T',
        'code': 'C',
        'term': 'Fall',
        'teacherId': 't',
        'teacherName': 'Teach',
        'studentIds': ['s-1'],
        'studentCount': 1,
        'assignmentCount': 0,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final user = {
        'id': 'u-1',
        'displayName': 'A',
        'email': 'a@x',
        'phone': '',
        'role': 'student',
        'isActive': true,
        'isPhoneVerified': true,
        'courseIds': <String>[],
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final calls = <String>[];
      api.httpClientOverride = MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1/admin', '');
        calls.add('${request.method} $path'
            '${request.body.isEmpty ? '' : ' ${request.body}'}');
        final Object data = switch (path) {
          '/courses' when request.method == 'GET' => [course],
          '/integrity' => <Object>[],
          '/overview' => <String, Object>{},
          _ when path.startsWith('/courses') && request.method != 'DELETE' =>
            course,
          _ when request.method == 'PATCH' => user,
          _ => {'success': true},
        };
        return http.Response(jsonEncode({'data': data}), 200, request: request);
      });

      await api.adminUpdateUser('u-1', role: 'teacher', isActive: false);
      await api.adminResetPassword('u-1', 'new-password');
      await api.adminDeleteUser('u-1');
      await api.adminListCourses();
      await api.adminCreateCourse(
          title: 'T', code: 'C', term: 'Fall', teacherId: 't');
      await api.adminUpdateCourse('c-1', teacherId: 't2');
      await api.adminDeleteCourse('c-1');
      await api.adminSetCourseStudents('c-1', ['s-1', 's-2']);
      await api.adminIntegrity(flaggedOnly: true);
      await api.adminOverview();

      expect(calls, [
        'PATCH /users/u-1 {"role":"teacher","isActive":false}',
        'POST /users/u-1/password {"password":"new-password"}',
        'DELETE /users/u-1',
        'GET /courses',
        'POST /courses {"title":"T","code":"C","term":"Fall","teacherId":"t"}',
        'PATCH /courses/c-1 {"teacherId":"t2"}',
        'DELETE /courses/c-1',
        'PUT /courses/c-1/students {"studentIds":["s-1","s-2"]}',
        'GET /integrity',
        'GET /overview',
      ]);
    });

    test('integrity sends flagged=false by default', () async {
      final seen = respond(200, {'data': <Object>[]});
      await api.adminIntegrity();
      expect(seen.single.url.queryParameters, {'flagged': 'false'});
    });
  });

  group('errors', () {
    test('rethrow ApiException with the envelope code and message', () async {
      respond(409, {
        'error': {'code': 'LAST_ADMIN', 'message': 'Keep one admin'}
      });
      await expectLater(
        api.adminUpdateUser('u-1', isActive: false),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.code, 'code', 'LAST_ADMIN')
            .having((e) => e.message, 'message', 'Keep one admin')
            .having((e) => e.toString(), 'toString', 'Keep one admin')),
      );
    });

    test('never fall back to demo data', () async {
      respond(500, 'upstream exploded');
      await expectLater(
        api.adminListCourses(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 500)
            .having((e) => e.code, 'code', isNull)
            .having((e) => e.message, 'message', 'Request failed (500)')),
      );
      await expectLater(api.adminOverview(), throwsA(isA<ApiException>()));
    });

    test('a 401 triggers onUnauthorized with the API error', () async {
      ApiException? signedOut;
      api.onUnauthorized = (error) => signedOut = error;
      respond(401, {
        'error': {'code': 'SESSION_REVOKED', 'message': 'Session ended'}
      });
      await expectLater(api.adminListUsers(), throwsA(isA<ApiException>()));
      expect(signedOut?.code, 'SESSION_REVOKED');
      expect(signedOut?.message, 'Session ended');
    });

    test('a 403 does not sign out', () async {
      var signedOut = false;
      api.onUnauthorized = (_) => signedOut = true;
      respond(403, {
        'error': {'code': 'FORBIDDEN', 'message': 'Admins only'}
      });
      await expectLater(
          api.adminListUsers(),
          throwsA(
              isA<ApiException>().having((e) => e.code, 'code', 'FORBIDDEN')));
      expect(signedOut, isFalse);
    });
  });

  group('demo fallback', () {
    tearDown(() => api.demoFallback = true);

    test('the main app falls back to demo courses and events', () async {
      respond(500, {
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'}
      });
      expect(await api.getCourses(), isNotEmpty);
      expect(await api.getCalendar(null), isNotEmpty);
    });

    test('with demoFallback off, failures reach the screen', () async {
      api.demoFallback = false;
      respond(500, {
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'}
      });
      final failed = throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'boom'));
      await expectLater(api.getCourses(), failed);
      await expectLater(api.getCalendar('u-admin-1'), failed);
      await expectLater(api.getAssignments('c-1'), failed);
      await expectLater(api.getChannels('c-1'), failed);
      await expectLater(api.getMessages('ch-1'), failed);
    });
  });

  group('friendlyError', () {
    test('a web fetch failure reads as an unreachable server', () {
      const reachMessage =
          'Could not reach the server. Check your connection and try again.';
      expect(
          friendlyError(http.ClientException('Failed to fetch',
              Uri.parse('https://api.example.com/api/v1/admin/overview'))),
          reachMessage);
      expect(
          friendlyError(Exception('SocketException: refused')), reachMessage);
      expect(friendlyError(ApiException(409, 'At least one admin')),
          'At least one admin');
    });
  });

  test('bodiless DELETEs omit the JSON content type (Fastify rejects it)',
      () async {
    final seen = respond(200, {
      'data': {'success': true}
    });
    await api.adminDeleteUser('u-1');
    await api.adminDeleteCourse('c-1');
    // The reused main-app screens delete through these.
    await api.deleteStudent('s-1');
    await api.deleteDepartment('d-1');
    await api.deleteTeacherNote('n-1');
    await api.deleteCalendarEvent('e-1');
    await api.unenrollStudentFromDepartment(
        studentId: 's-1', departmentId: 'd-1');
    expect(seen, hasLength(7));
    for (final request in seen) {
      expect(request.method, 'DELETE');
      expect(request.headers.containsKey('content-type'), isFalse,
          reason: request.url.path);
      expect(request.headers['Authorization'], 'Bearer admin-token');
    }

    await api.adminResetPassword('u-1', 'new-password');
    expect(seen.last.headers['content-type'], startsWith('application/json'));
  });

  test('login sends email or phone, whichever is given', () async {
    final seen = respond(200, {
      'data': {'token': 't', 'user': <String, Object>{}}
    });
    await api.login(email: 'a@example.edu', password: kDemoPassword);
    await api.login(phone: '+1555', password: kDemoPassword);
    expect(jsonDecode(seen[0].body),
        {'email': 'a@example.edu', 'password': kDemoPassword});
    expect(jsonDecode(seen[1].body),
        {'phone': '+1555', 'password': kDemoPassword});
  });

  group('models round-trip through JSON', () {
    test('AdminUser', () {
      final json = {
        'id': 'u-1',
        'displayName': 'Ada',
        'email': 'ada@example.edu',
        'phone': '+1555',
        'role': 'admin',
        'isActive': true,
        'isPhoneVerified': true,
        'courseIds': ['c-1'],
        'createdAt': '2026-01-02T03:04:05.000Z',
      };
      expect(AdminUser.fromJson(json).toJson(), json);
    });

    test('AdminCourse', () {
      final json = {
        'id': 'c-1',
        'title': 'HCI',
        'code': 'CS 301',
        'term': 'Fall 2026',
        'teacherId': 'u-t',
        'teacherName': 'Tayyab',
        'studentIds': ['s-1', 's-2'],
        'studentCount': 2,
        'assignmentCount': 3,
        'createdAt': '2026-01-02T03:04:05.000Z',
      };
      expect(AdminCourse.fromJson(json).toJson(), json);
    });

    test('IntegrityRow', () {
      final json = {
        'studentId': 's-1',
        'studentName': 'Aeliya',
        'assignmentId': 'a-1',
        'assignmentTitle': 'Essay',
        'courseId': 'c-1',
        'courseTitle': 'HCI',
        'score': 42.5,
        'flags': ['large_paste'],
        'computedAt': '2026-01-02T03:04:05.000Z',
      };
      final row = IntegrityRow.fromJson(json);
      expect(row.toJson(), json);
      expect(row.isFlagged, isTrue);
      expect(
          IntegrityRow.fromJson({
            ...json,
            'flags': ['none']
          }).isFlagged,
          isFalse);
    });

    test('AdminOverview', () {
      final json = {
        'counts': {
          'students': 1,
          'teachers': 2,
          'admins': 3,
          'inactiveUsers': 4,
          'courses': 5,
          'departments': 6,
          'assignments': 7,
          'submissions': 8,
          'telemetryBatches': 9,
          'flaggedReports': 10,
        },
        'storage': 'memory',
        'database': 'unreachable',
        'schemaVersion': null,
        'version': '0.3.0',
        'serverTime': '2026-01-02T03:04:05.000Z',
      };
      final overview = AdminOverview.fromJson(json);
      expect(overview.toJson(), json);
      expect(overview.databaseOk, isFalse);
    });
  });
}
