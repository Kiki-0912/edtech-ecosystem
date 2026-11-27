import 'dart:convert';

import 'package:edtech_app/services/offline_store.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// An in-process replacement for the network client.
///
/// It answers the same REST routes as the Fastify API, but reads and writes the
/// persistent [OfflineStore] instead of making HTTP requests. This lets every
/// screen work in the standalone APK with no server at all.
///
/// It also mirrors the API's access rules (role checks, course scoping,
/// channel membership) and its `{ error: { code, message } }` codes and status
/// codes, so the offline build behaves like the hosted one. The caller is the
/// signed-in session stored by `AuthProvider` (or, failing that, the user
/// encoded in the offline bearer token).
class OfflineClient extends http.BaseClient {
  final OfflineStore _store = OfflineStore.instance;

  /// `AuthProvider`'s persisted user key.
  static const _sessionUserKey = 'auth_user';

  /// Offline tokens are `offline.<base64url(user json)>`.
  static const _tokenPrefix = 'offline.';

  /// Token issued by older builds; resolves to the stored session.
  static const legacyToken = 'offline-demo-token';

  static final List<Map<String, dynamic>> _courses = [
    {
      'id': 'c-cs301',
      'code': 'CS 301',
      'title': 'Human-Computer Interaction',
      'teacherId': 'u-teacher-1',
      'term': 'Fall 2026',
      'createdAt': '2026-08-20T00:00:00.000Z',
    },
    {
      'id': 'c-cs210',
      'code': 'CS 210',
      'title': 'Data Structures',
      'teacherId': 'u-teacher-2',
      'term': 'Fall 2026',
      'createdAt': '2026-08-20T00:00:00.000Z',
    },
    {
      'id': 'c-des150',
      'code': 'DES 150',
      'title': 'Design Foundations',
      'teacherId': 'u-teacher-3',
      'term': 'Fall 2026',
      'createdAt': '2026-08-20T00:00:00.000Z',
    },
  ];

  /// Staff accounts, matching the API seed (students live in [OfflineStore]).
  static const List<Map<String, dynamic>> _staff = [
    {
      'id': 'u-teacher-1',
      'displayName': 'Tayyab',
      'email': 'tayyab@example.edu',
      'phone': '+15550001001',
      'role': 'teacher',
      'isPhoneVerified': true,
      'createdAt': '2026-07-01T00:00:00.000Z',
    },
    {
      'id': 'u-admin-1',
      'displayName': 'Usman Shahid',
      'email': 'usman.shahid@example.edu',
      'phone': '+15550001005',
      'role': 'admin',
      'isPhoneVerified': true,
      'createdAt': '2026-07-01T00:00:00.000Z',
    },
  ];

  /// Mirrors the API seed, which only names u-teacher-1.
  static const Map<String, String> _teacherNames = {'u-teacher-1': 'Tayyab'};

  static const _eventKinds = {'assignment', 'quiz', 'class', 'institution'};
  static const _attendanceStatuses = {'present', 'absent', 'late', 'excused'};
  static const _assignmentStatuses = {'draft', 'open', 'closed'};

  /// The bearer token for [user] (its id, role and profile, base64url JSON).
  static String tokenFor(Map<String, dynamic> user) =>
      '$_tokenPrefix${base64Url.encode(utf8.encode(jsonEncode(user)))}';

  static Map<String, dynamic>? _userFromToken(String? token) {
    if (token == null || !token.startsWith(_tokenPrefix)) return null;
    try {
      final json = utf8.decode(base64Url
          .decode(base64Url.normalize(token.substring(_tokenPrefix.length))));
      final user = jsonDecode(json);
      return user is Map<String, dynamic> && user['id'] is String ? user : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final path = uri.path;
    final method = request.method;
    Object? decoded;
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        decoded = jsonDecode(request.body);
      } catch (_) {
        return _json(400, _error('INVALID_BODY', 'Body is not valid JSON'));
      }
    }
    final body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final token = _bearer(request.headers);

    try {
      final result =
          await _route(method, path, uri.queryParameters, body, token);
      return _json(result.status, result.body);
    } catch (error) {
      return _json(500, _error('INTERNAL_ERROR', error.toString()));
    }
  }

  static String? _bearer(Map<String, String> headers) {
    final value = headers['Authorization'] ?? headers['authorization'];
    if (value == null || !value.startsWith('Bearer ')) return null;
    final token = value.substring(7);
    return token.isEmpty ? null : token;
  }

  /* ============================================
     CALLER / DIRECTORY
     ============================================ */

  Future<Map<String, dynamic>?> _storedSessionUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _sessionUserKey,
    );
    if (raw == null) return null;
    try {
      final user = jsonDecode(raw);
      return user is Map<String, dynamic> && user['id'] is String ? user : null;
    } catch (_) {
      return null;
    }
  }

  /// The signed-in caller: the stored session (what the app shows as signed
  /// in), else the user in the offline token. `null` means unauthenticated.
  Future<_Caller?> _caller(String? token) async {
    final user = await _storedSessionUser() ?? _userFromToken(token);
    if (user == null) return null;
    return _Caller(
      id: user['id'] as String,
      role: user['role']?.toString() ?? 'student',
    );
  }

  /// Staff plus the stored students, keyed by id.
  Future<List<Map<String, dynamic>>> _users() async =>
      [..._staff, ...await _store.getStudents()];

  Future<Map<String, dynamic>?> _userById(String id) async =>
      (await _users()).where((u) => u['id'] == id).firstOrNull;

  /// A user as `/auth/*` returns it, with the course ids the role implies.
  Future<Map<String, dynamic>> _authUser(Map<String, dynamic> user) async {
    final role = user['role']?.toString() ?? 'student';
    final id = user['id'] as String;
    final courseIds = switch (role) {
      'admin' => [for (final c in _courses) c['id'] as String],
      'teacher' => [
          for (final c in _courses)
            if (c['teacherId'] == id) c['id'] as String,
        ],
      _ => List<String>.from(user['courseIds'] as List? ?? const []),
    };
    return {
      'id': id,
      'displayName': user['displayName'] ?? 'User',
      'email': user['email'] ?? '',
      'phone': user['phone'] ?? '',
      'role': role,
      'courseIds': courseIds,
      'isPhoneVerified': user['isPhoneVerified'] ?? true,
      'createdAt': user['createdAt'] ?? '2026-07-01T00:00:00.000Z',
    };
  }

  Map<String, dynamic>? _course(String? id) =>
      _courses.where((c) => c['id'] == id).firstOrNull;

  /// Drafts are visible only to the course's managers, like the API.
  bool _canSee(_Caller caller, Map<String, dynamic> assignment) =>
      assignment['status'] != 'draft' ||
      _manages(caller, assignment['courseId']?.toString());

  /// A course's assignments as [caller] may list them (drafts hidden from
  /// anyone who does not manage the course).
  Future<List<Map<String, dynamic>>> _courseAssignments(
          String courseId, _Caller caller) async =>
      [
        for (final a in await _store.getAssignments(courseId: courseId))
          if (_canSee(caller, a)) a,
      ];

  /// Enrolled student ids: the stored students' `courseIds` are the truth
  /// (creating, moving and importing students all update them).
  Future<List<String>> _enrolledIds(String courseId) async => [
        for (final s in await _store.getStudentsByCourse(courseId))
          s['id'] as String,
      ];

  /// Like the API's `readableCourseIds`: every course for admins, taught
  /// courses for teachers, enrolled courses for students.
  Future<Set<String>> _readableCourseIds(_Caller caller) async {
    if (caller.isAdmin) return {for (final c in _courses) c['id'] as String};
    if (caller.role == 'teacher') {
      return {
        for (final c in _courses)
          if (c['teacherId'] == caller.id) c['id'] as String,
      };
    }
    final student = await _userById(caller.id);
    return Set<String>.from(student?['courseIds'] as List? ?? const []);
  }

  /// Like the API's `managesCourseId`: admins manage everything, teachers the
  /// courses they teach.
  bool _manages(_Caller caller, String? courseId) {
    if (caller.isAdmin) return true;
    if (courseId == null) return false;
    return caller.role == 'teacher' &&
        _course(courseId)?['teacherId'] == caller.id;
  }

  /* ============================================
     ROUTING
     ============================================ */

  Future<_Result> _route(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
    String? token,
  ) async {
    final segments = Uri.parse(path).pathSegments;
    if (path == '/health') {
      return _Result(200, {'status': 'ok', 'mode': 'offline'});
    }
    final isV1 =
        segments.length >= 3 && segments[0] == 'api' && segments[1] == 'v1';
    // '/college' is kept for old builds; the API serves /api/v1/college.
    if (!isV1 && path != '/college') {
      return _notFound('Unknown route $path');
    }
    final rest = isV1 ? segments.sublist(2) : const ['college'];

    if (rest[0] == 'auth') return _auth(rest, method, body, token);

    // Every other route needs a session, like the API's global preHandler.
    final caller = await _caller(token);
    if (caller == null) {
      return _fail(401, 'UNAUTHORIZED', 'Missing or invalid token');
    }

    switch (rest[0]) {
      case 'college':
        return _college();
      case 'courses':
        return _coursesRoute(rest, method, body, caller);
      case 'assignments':
        return _assignmentsRoute(rest, method, body, caller);
      case 'students':
        return _studentsRoute(rest, method, body, caller);
      case 'departments':
        return _departmentsRoute(rest, method, body, caller);
      case 'attendance':
        return _attendanceRoute(rest, method, query, body, caller);
      case 'notes':
        return _notesRoute(rest, method, query, body, caller);
      case 'excel':
        return _excelRoute(rest, method, query, body, caller);
      case 'calendar':
        return _calendarRoute(rest, method, query, body, caller);
      case 'channels':
        return _channelsRoute(rest, method, body, caller);
      case 'telemetry':
        return _Result(200, {
          'data': {'status': 'ok'}
        });
      case 'integrity':
        return _integrityRoute(rest, method);
      default:
        return _notFound('Unknown route $path');
    }
  }

  Future<_Result> _college() async {
    final departments = await _store.getDepartments();
    return _Result(200, {
      'data': {
        'id': 'col-cttc',
        'name': 'Christian Technical Training Center',
        'shortName': 'CTTC',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'departments': departments,
        'departmentCount': departments.length,
      },
    });
  }

  /* ============================================
     AUTH
     ============================================ */

  Future<_Result> _auth(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    String? token,
  ) async {
    final action = rest.length > 1 ? rest[1] : '';
    if (action == 'me') {
      if (method != 'GET') return _methodNotAllowed();
      return _me(token);
    }
    if (method != 'POST') return _methodNotAllowed();

    // Mirror the API: public sign-up creates student accounts only.
    if (action == 'register') {
      final requested = body['role']?.toString();
      if (requested != null && requested != 'student') {
        return _fail(
            400,
            'INVALID_BODY',
            'Public sign-up creates student accounts; '
                'teachers are added by an admin');
      }
      return _signedIn({
        'id': 'u-student-1',
        'displayName': body['display_name']?.toString() ??
            body['displayName']?.toString() ??
            'Demo student',
        'email': body['email']?.toString() ?? 'demo@example.edu',
        'phone': body['phone']?.toString() ?? '',
        'role': 'student',
        'courseIds': ['c-cs301', 'c-cs210', 'c-des150'],
      });
    }

    // Demo-friendly sign-in: any password works. A phone or email that
    // belongs to a seeded account signs in as that account (and its role);
    // anything else signs in as the demo admin.
    final phone = body['phone']?.toString().trim() ?? '';
    final email = body['email']?.toString().trim().toLowerCase() ?? '';
    final match = (await _users())
        .where((u) =>
            (phone.isNotEmpty && u['phone'] == phone) ||
            (email.isNotEmpty && u['email']?.toString().toLowerCase() == email))
        .firstOrNull;
    if (action == 'send-sms') {
      return _Result(200, {
        'data': {'sent': true},
      });
    }
    return _signedIn(match ??
        {
          ..._staff.firstWhere((u) => u['id'] == 'u-admin-1'),
          if (phone.isNotEmpty) 'phone': phone,
          if (email.isNotEmpty) 'email': email,
        });
  }

  Future<_Result> _signedIn(Map<String, dynamic> account) async {
    final user = await _authUser(account);
    return _Result(200, {
      'data': {'token': tokenFor(user), 'user': user},
    });
  }

  /// `/auth/me` reflects the token's user (refreshed from the directory).
  Future<_Result> _me(String? token) async {
    final fromToken = token == legacyToken
        ? await _storedSessionUser()
        : _userFromToken(token);
    if (fromToken == null) {
      return _fail(401, 'UNAUTHORIZED', 'Missing or invalid token');
    }
    final current = await _userById(fromToken['id'] as String);
    return _Result(200, {
      'data': {'user': await _authUser(current ?? fromToken)},
    });
  }

  /* ============================================
     COURSES / ASSIGNMENTS
     ============================================ */

  Future<Map<String, dynamic>> _courseJson(Map<String, dynamic> c) async => {
        ...c,
        'studentIds': await _enrolledIds(c['id'] as String),
      };

  Future<_Result> _coursesRoute(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length == 3 && rest[2] == 'assignments' && method == 'POST') {
      return _createAssignment(rest[1], body, caller);
    }
    if (method != 'GET') return _methodNotAllowed();
    if (rest.length == 1) {
      // Same enrichment as the API's GET /courses.
      return _Result(200, {
        'data': [
          for (final c in _courses)
            {
              ...await _courseJson(c),
              'teacherName': _teacherNames[c['teacherId']] ?? 'Unassigned',
              'studentCount': (await _enrolledIds(c['id'] as String)).length,
              'openAssignmentCount':
                  (await _store.getAssignments(courseId: c['id'] as String))
                      .where((a) => a['status'] == 'open')
                      .length,
            },
        ],
      });
    }
    final courseId = rest[1];
    final course = _course(courseId);
    if (course == null) {
      return _fail(404, 'COURSE_NOT_FOUND', 'Course not found');
    }
    if (rest.length == 2) {
      // Same shape as the API's GET /courses/:id.
      final students = await _store.getStudentsByCourse(courseId);
      return _Result(200, {
        'data': {
          'course': await _courseJson(course),
          'teacher': await _userById(course['teacherId'] as String),
          'roster': students,
          'assignments': await _courseAssignments(courseId, caller),
        },
      });
    }
    if (rest.length == 3 && rest[2] == 'assignments') {
      // Already sorted by due date.
      return _Result(200, {'data': await _courseAssignments(courseId, caller)});
    }
    if (rest.length == 3 && rest[2] == 'channels') {
      return _Result(200, {'data': await _channelsFor(course)});
    }
    if (rest.length == 3 && rest[2] == 'students') {
      return _Result(200, {'data': await _store.getStudentsByCourse(courseId)});
    }
    return _notFound('Unknown course route');
  }

  Future<_Result> _assignmentsRoute(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length < 2) return _notFound('Unknown assignment route');
    final changing =
        rest.length == 2 && (method == 'PATCH' || method == 'DELETE');
    // Like the API, the role check comes before the lookup.
    if (changing && !caller.isStaff) {
      return _fail(
          403, 'FORBIDDEN', 'Only teachers and admins can change assignments');
    }
    final assignment = await _store.getAssignment(rest[1]);
    if (assignment == null) {
      return _fail(404, 'ASSIGNMENT_NOT_FOUND', 'Assignment not found');
    }
    final course = _course(assignment['courseId'] as String);

    if (changing) {
      if (!_manages(caller, assignment['courseId']?.toString())) {
        return _fail(403, 'FORBIDDEN',
            'You can only change assignments of courses you teach');
      }
      if (method == 'DELETE') {
        await _store.deleteAssignment(assignment['id'] as String);
        return _success();
      }
      final invalid = _invalidAssignment(body, creating: false);
      if (invalid != null) return _fail(400, 'INVALID_BODY', invalid);
      final updated = await _store.updateAssignment(
        assignment['id'] as String,
        title:
            body.containsKey('title') ? (body['title'] as String).trim() : null,
        brief: body['brief'] as String?,
        dueAt: body.containsKey('dueAt')
            ? DateTime.parse(body['dueAt'] as String)
            : null,
        status: body['status'] as String?,
      );
      return _Result(200, {'data': updated});
    }
    if (rest.length == 2 && method == 'GET' && !_canSee(caller, assignment)) {
      // A student (or another course's teacher) cannot see a draft.
      return _fail(404, 'ASSIGNMENT_NOT_FOUND', 'Assignment not found');
    }

    if (rest.length == 2 && method == 'GET') {
      // The API wraps the assignment with its course.
      return _Result(200, {
        'data': {
          'assignment': assignment,
          'course': course == null ? null : await _courseJson(course),
        },
      });
    }
    if (rest.length == 3 && rest[2] == 'roster' && method == 'GET') {
      if (course == null) {
        return _fail(404, 'COURSE_NOT_FOUND', 'Course not found');
      }
      if (!_manages(caller, course['id'] as String)) {
        return _fail(403, 'FORBIDDEN',
            "Only the course's teacher or an admin can view the roster");
      }
      // Every enrolled student, with their submission if any.
      final students = await _store.getStudents();
      final submissions = (await _store.getSubmissions())
          .where((s) => s['assignmentId'] == assignment['id'])
          .toList();
      final roster = [
        for (final id in await _enrolledIds(course['id'] as String))
          () {
            final student = students.where((s) => s['id'] == id).firstOrNull;
            final sub =
                submissions.where((s) => s['studentId'] == id).firstOrNull;
            return <String, dynamic>{
              'studentId': id,
              'displayName': student?['displayName'] ?? 'Unknown student',
              'status': sub?['status'] ?? 'missing',
              'submittedAt': sub?['submittedAt'],
              'effortScore': sub?['effortScore'],
              'grade': sub?['grade'],
            };
          }(),
      ];
      return _Result(200, {
        'data': {'assignment': assignment, 'roster': roster},
      });
    }
    if (rest.length == 3 && rest[2] == 'submissions' && method == 'POST') {
      return _submit(assignment, course, body, caller);
    }
    return _notFound('Unknown assignment route');
  }

  /// POST /courses/:courseId/assignments: admin or the course's teacher.
  Future<_Result> _createAssignment(
    String courseId,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    // Same order as the API: role, then course, then ownership.
    if (!caller.isStaff) {
      return _fail(
          403, 'FORBIDDEN', 'Only teachers and admins can create assignments');
    }
    if (_course(courseId) == null) {
      return _fail(404, 'COURSE_NOT_FOUND', 'Course not found');
    }
    if (!_manages(caller, courseId)) {
      return _fail(403, 'FORBIDDEN',
          'You can only add assignments to courses you teach');
    }
    final invalid = _invalidAssignment(body, creating: true);
    if (invalid != null) return _fail(400, 'INVALID_BODY', invalid);
    final assignment = await _store.createAssignment(
      courseId: courseId,
      title: (body['title'] as String).trim(),
      brief: body['brief'] as String? ?? '',
      dueAt: DateTime.parse(body['dueAt'] as String),
      status: body['status'] as String? ?? 'open',
    );
    return _Result(201, {'data': assignment});
  }

  /// The API's body checks for an assignment. Returns an error message or
  /// null. [creating] makes title and dueAt required.
  String? _invalidAssignment(Map<String, dynamic> body,
      {required bool creating}) {
    const fields = ['title', 'brief', 'dueAt', 'status'];
    if (!creating && !fields.any(body.containsKey)) {
      return 'Provide at least one of ${fields.join(', ')}';
    }
    final title = body['title'];
    if (creating || body.containsKey('title')) {
      if (title is! String || title.trim().isEmpty) {
        return 'title is required';
      }
      if (title.length > 200) {
        return 'title must be at most 200 characters';
      }
    }
    final brief = body['brief'];
    if (body.containsKey('brief')) {
      if (brief is! String) return 'brief must be a string';
      if (brief.length > 10000) return 'brief must be at most 10000 characters';
    }
    final dueAt = body['dueAt'];
    if (creating || body.containsKey('dueAt')) {
      if (dueAt is! String || DateTime.tryParse(dueAt) == null) {
        return 'dueAt must be an ISO date';
      }
    }
    if (body.containsKey('status') &&
        !_assignmentStatuses.contains(body['status'])) {
      return 'status must be one of ${_assignmentStatuses.join(', ')}';
    }
    return null;
  }

  /// POST /assignments/:id/submissions, with the API's checks and codes.
  Future<_Result> _submit(
    Map<String, dynamic> assignment,
    Map<String, dynamic>? course,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    // Students can only submit their own work; staff may pass studentId.
    final requested = body['studentId']?.toString();
    final studentId = caller.role == 'student' ? caller.id : requested;
    if (studentId == null || studentId.isEmpty) {
      return _fail(400, 'INVALID_BODY', 'studentId is required');
    }
    if (caller.role == 'student' &&
        requested != null &&
        requested.isNotEmpty &&
        requested != caller.id) {
      return _fail(403, 'FORBIDDEN', 'Students can only submit their own work');
    }
    final student = await _userById(studentId);
    if (student == null) {
      return _fail(404, 'STUDENT_NOT_FOUND', 'Student not found');
    }
    if (course == null ||
        !(await _enrolledIds(course['id'] as String)).contains(studentId)) {
      return _fail(
          403, 'NOT_ENROLLED', 'Student is not enrolled in this course');
    }
    final rawAttachments = body['attachments'] ?? const [];
    if (rawAttachments is! List) {
      return _fail(400, 'INVALID_BODY', 'attachments must be an array');
    }
    if (assignment['status'] == 'draft') {
      return _fail(
          409, 'ASSIGNMENT_DRAFT', 'Assignment is not open for submissions');
    }
    if (assignment['status'] == 'closed') {
      return _fail(
          409, 'ASSIGNMENT_CLOSED', 'Assignment is closed for submissions');
    }
    final attachments = rawAttachments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map((item) => <String, dynamic>{
              'id':
                  item['id'] ?? 'att-${DateTime.now().microsecondsSinceEpoch}',
              'fileName': item['fileName'] ?? 'submission.txt',
              'mimeType': item['mimeType'] ?? 'text/plain',
              'sizeBytes': item['sizeBytes'] ?? 0,
              'url': item['url'] ?? 'offline://submission',
            })
        .toList();
    final resubmitting = (await _store.getSubmissions()).any((s) =>
        s['assignmentId'] == assignment['id'] && s['studentId'] == studentId);
    final dueAt = DateTime.tryParse(assignment['dueAt']?.toString() ?? '');
    final submission = await _store.createSubmission(
      assignmentId: assignment['id'] as String,
      studentId: studentId,
      attachments: attachments,
      status: dueAt != null && dueAt.isBefore(DateTime.now())
          ? 'late'
          : 'submitted',
    );
    // The API answers 200 when it updates an existing submission.
    return _Result(resubmitting ? 200 : 201, {'data': submission});
  }

  /* ============================================
     STUDENTS / DEPARTMENTS
     ============================================ */

  Future<_Result> _studentsRoute(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length == 1 && method == 'GET') {
      final students = await _store.getStudents();
      if (caller.role != 'student') {
        return _Result(200, {'data': students});
      }
      // Students get only their classmates, as names without contacts.
      final mine = await _readableCourseIds(caller);
      return _Result(200, {
        'data': [
          for (final s in students)
            if (s['id'] == caller.id ||
                (s['courseIds'] as List? ?? const []).any(mine.contains))
              {
                'id': s['id'],
                'displayName': s['displayName'],
                'role': s['role'],
              },
        ],
      });
    }
    if (rest.length == 3 && rest[2] == 'departments') {
      return _studentDepartments(rest[1], method, body, caller);
    }
    if (rest.length == 4 && rest[2] == 'departments' && method == 'DELETE') {
      if (!caller.isAdmin) return _adminOnly();
      await _store.unenrollStudentFromDepartment(
        studentId: rest[1],
        departmentId: rest[3],
      );
      return _success();
    }
    if (rest.length == 2 && method == 'GET') {
      if (caller.role == 'student' && caller.id != rest[1]) {
        return _fail(
            403, 'FORBIDDEN', 'Students can only view their own record');
      }
      final student = await _student(rest[1]);
      return student == null
          ? _fail(404, 'NOT_FOUND', 'Student not found')
          : _Result(200, {'data': student});
    }
    if (rest.length > 2) return _notFound('Unknown student route');

    // Writes: admin only, checked before the body like the API.
    if (!caller.isAdmin) return _adminOnly();
    if (rest.length == 1 && method == 'POST') {
      final name = body['displayName']?.toString().trim() ?? '';
      final email = body['email']?.toString().trim() ?? '';
      final phone = body['phone']?.toString().trim() ?? '';
      final courseId = _optional(body['courseId']);
      final departmentId = _optional(body['departmentId']);
      if (name.isEmpty) {
        return _fail(400, 'INVALID_BODY', 'displayName is required');
      }
      if (email.isEmpty && phone.isEmpty) {
        return _fail(400, 'INVALID_BODY', 'Phone or email is required');
      }
      if (courseId != null && _course(courseId) == null) {
        return _fail(400, 'INVALID_REFERENCE', 'Course not found');
      }
      if (departmentId != null && !await _departmentExists(departmentId)) {
        return _fail(400, 'INVALID_REFERENCE', 'Department not found');
      }
      final student = await _store.createStudent(
        displayName: name,
        email: email,
        phone: phone,
        courseId: courseId,
        departmentId: departmentId,
        enrolledBy: caller.id,
      );
      return _Result(201, {'data': student});
    }
    final id = rest.length == 2 ? rest[1] : '';
    if (rest.length == 2 && method == 'PUT') {
      if (await _student(id) == null) {
        return _fail(404, 'NOT_FOUND', 'Student not found');
      }
      final courseId = _optional(body['courseId']);
      if (courseId != null && _course(courseId) == null) {
        return _fail(400, 'INVALID_REFERENCE', 'Course not found');
      }
      final student = await _store.updateStudent(
        studentId: id,
        displayName: body['displayName']?.toString().trim(),
        email: body['email']?.toString().trim(),
        phone: body['phone']?.toString().trim(),
        courseId: courseId,
      );
      return _Result(200, {'data': student});
    }
    if (rest.length == 2 && method == 'DELETE') {
      if (await _student(id) == null) {
        return _fail(404, 'NOT_FOUND', 'Student not found');
      }
      await _store.deleteStudent(id);
      return _success();
    }
    return _notFound('Unknown student route');
  }

  Future<_Result> _studentDepartments(
    String studentId,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (method == 'GET') {
      return _Result(
          200, {'data': await _store.getStudentDepartments(studentId)});
    }
    if (method != 'POST') return _methodNotAllowed();
    if (!caller.isAdmin) return _adminOnly();
    final departmentId = _optional(body['departmentId']);
    if (departmentId == null) {
      return _fail(400, 'INVALID_BODY', 'departmentId is required');
    }
    if (await _student(studentId) == null) {
      return _fail(404, 'NOT_FOUND', 'Student not found');
    }
    if (!await _departmentExists(departmentId)) {
      return _fail(400, 'INVALID_REFERENCE', 'Department not found');
    }
    // Adds a department; existing enrolments are kept, like the API.
    final enrollment = await _store.enrollStudentInDepartment(
      studentId: studentId,
      departmentId: departmentId,
      enrolledBy: caller.id,
    );
    return _Result(201, {'data': enrollment});
  }

  Future<Map<String, dynamic>?> _student(String id) async =>
      (await _store.getStudents()).where((s) => s['id'] == id).firstOrNull;

  Future<bool> _departmentExists(String id) async =>
      (await _store.getDepartments()).any((d) => d['id'] == id);

  Future<_Result> _departmentsRoute(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (method == 'GET') {
      if (rest.length == 1) {
        return _Result(200, {'data': await _store.getDepartments()});
      }
      if (rest.length == 3 && rest[2] == 'students') {
        return _Result(200, {
          'data': await _store.getStudentsByDepartment(rest[1]),
        });
      }
      return _notFound('Unknown department route');
    }
    if (!caller.isAdmin) return _adminOnly();
    const notFound = 'Department not found';
    if (rest.length == 1 && method == 'POST') {
      final name = body['name']?.toString().trim() ?? '';
      final code = body['code']?.toString().trim() ?? '';
      if (name.isEmpty || code.isEmpty) {
        return _fail(400, 'INVALID_BODY', 'Name and code are required');
      }
      return _Result(201, {
        'data': await _store.createDepartment(
          name: name,
          code: code,
          category: body['category']?.toString() ?? '3 Years',
          durationMonths: (body['durationMonths'] as num?)?.toInt() ?? 36,
        ),
      });
    }
    if (rest.length == 2 && method == 'PUT') {
      final updated = await _store.updateDepartment(rest[1], body);
      return updated == null
          ? _fail(404, 'NOT_FOUND', notFound)
          : _Result(200, {'data': updated});
    }
    if (rest.length == 2 && method == 'DELETE') {
      return await _store.deleteDepartment(rest[1])
          ? _success()
          : _fail(404, 'NOT_FOUND', notFound);
    }
    return _methodNotAllowed();
  }

  /* ============================================
     INTEGRITY
     ============================================ */

  /// `GET /integrity/:assignmentId/:studentId` — the stored telemetry report,
  /// or 404 when none has been captured for that pair.
  Future<_Result> _integrityRoute(List<String> rest, String method) async {
    if (method != 'GET' || rest.length < 3) return _methodNotAllowed();
    final report = await _store.getIntegrityReport(rest[1], rest[2]);
    if (report == null) return _notFound('No integrity report');
    return _Result(200, {'data': report});
  }

  /* ============================================
     ATTENDANCE
     ============================================ */

  static const _noCourseAccess = 'You do not have access to this course';

  Future<_Result> _attendanceRoute(
    List<String> rest,
    String method,
    Map<String, String> query,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (method == 'POST') {
      // requireRoles('admin', 'teacher') runs before body validation.
      if (!caller.isStaff) {
        return _fail(403, 'FORBIDDEN', 'Insufficient role for this route');
      }
      if (rest.length == 1) return _markOne(body, caller);
      if (rest.length == 2 && rest[1] == 'bulk') return _markBulk(body, caller);
      return _notFound('Unknown attendance route');
    }
    if (method != 'GET') return _methodNotAllowed();

    if (rest.length == 1) {
      final courseId = query['courseId'];
      var records = await _store.getAttendanceRecords(
        courseId: courseId,
        date: query['date'],
      );
      // Students see their own records, teachers their courses', admins all.
      if (caller.role == 'student') {
        records = records.where((r) => r['studentId'] == caller.id).toList();
      } else if (!caller.isAdmin) {
        if (courseId != null && !_manages(caller, courseId)) {
          return _fail(403, 'FORBIDDEN', _noCourseAccess);
        }
        final taught = await _readableCourseIds(caller);
        records = records.where((r) => taught.contains(r['courseId'])).toList();
      }
      return _Result(200, {'data': records});
    }
    if (rest.length == 4 && rest[1] == 'course' && rest[3] == 'students') {
      final courseId = rest[2];
      if (caller.role != 'student' && !_manages(caller, courseId)) {
        return _fail(403, 'FORBIDDEN', _noCourseAccess);
      }
      var rows = await _store.getCourseStudentsWithAttendance(
        courseId: courseId,
        date: query['date'],
      );
      if (caller.role == 'student') {
        rows = rows.where((r) => r['id'] == caller.id).toList();
      }
      return _Result(200, {'data': rows});
    }
    if (rest.length == 2) {
      final record = (await _store.getAttendanceRecords())
          .where((r) => r['id'] == rest[1])
          .firstOrNull;
      if (record == null) {
        return _fail(404, 'NOT_FOUND', 'Attendance record not found');
      }
      final allowed = caller.role == 'student'
          ? record['studentId'] == caller.id
          : _manages(caller, record['courseId']?.toString());
      if (!allowed) {
        return _fail(403, 'FORBIDDEN', 'You do not have access to this record');
      }
      return _Result(200, {'data': record});
    }
    return _notFound('Unknown attendance route');
  }

  Future<_Result> _markOne(Map<String, dynamic> body, _Caller caller) async {
    final courseId = _optional(body['courseId']);
    final studentId = _optional(body['studentId']);
    final date = _optional(body['date']);
    final status = body['status']?.toString();
    if (courseId == null ||
        studentId == null ||
        date == null ||
        !_attendanceStatuses.contains(status)) {
      return _fail(400, 'INVALID_BODY',
          'courseId, studentId, date and a valid status are required');
    }
    if (!_manages(caller, courseId)) {
      return _fail(403, 'FORBIDDEN', _noCourseAccess);
    }
    final record = await _store.markAttendance(
      courseId: courseId,
      studentId: studentId,
      date: date,
      status: status!,
      notes: body['notes']?.toString(),
      markedBy: caller.id,
    );
    return _Result(201, {'data': record});
  }

  Future<_Result> _markBulk(Map<String, dynamic> body, _Caller caller) async {
    final courseId = _optional(body['courseId']);
    final date = _optional(body['date']);
    final raw = body['records'];
    final records = raw is List
        ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : null;
    if (courseId == null ||
        date == null ||
        records == null ||
        records.length != (raw as List).length ||
        records.any((r) =>
            _optional(r['studentId']) == null ||
            !_attendanceStatuses.contains(r['status']))) {
      return _fail(400, 'INVALID_BODY',
          'courseId, date and records with studentId and status are required');
    }
    if (!_manages(caller, courseId)) {
      return _fail(403, 'FORBIDDEN', _noCourseAccess);
    }
    if (_course(courseId) == null) {
      return _fail(400, 'INVALID_REFERENCE', 'Course not found');
    }
    final known = {for (final u in await _users()) u['id']};
    final unknown =
        records.where((r) => !known.contains(r['studentId'])).firstOrNull;
    if (unknown != null) {
      return _fail(
          400, 'INVALID_REFERENCE', 'Unknown student: ${unknown['studentId']}');
    }
    return _Result(201, {
      'data': await _store.bulkMarkAttendance(
        courseId: courseId,
        date: date,
        records: records,
        markedBy: caller.id,
      ),
    });
  }

  /* ============================================
     NOTES
     ============================================ */

  Future<_Result> _notesRoute(
    List<String> rest,
    String method,
    Map<String, String> query,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length == 1 && method == 'GET') {
      return _Result(200, {
        'data': await _store.getTeacherNotes(
          courseId: query['courseId'],
          courseCode: query['courseCode'],
        ),
      });
    }
    if (rest.length == 1 && method == 'POST') {
      if (!caller.isStaff) {
        return _fail(403, 'FORBIDDEN', 'Insufficient role for this route');
      }
      final courseId = _optional(body['courseId']);
      final bookName = _optional(body['bookName']);
      final courseCode = _optional(body['courseCode']);
      final title = _optional(body['title']);
      if (courseId == null ||
          bookName == null ||
          courseCode == null ||
          title == null) {
        return _fail(400, 'INVALID_BODY',
            'courseId, bookName, courseCode and title are required');
      }
      if (_course(courseId) == null) {
        return _fail(400, 'INVALID_REFERENCE', 'Course not found');
      }
      final note = await _store.createTeacherNote(
        courseId: courseId,
        bookName: bookName,
        courseCode: courseCode,
        title: title,
        content: body['content']?.toString() ?? '',
        authorId: caller.id,
      );
      return _Result(201, {'data': note});
    }
    if (rest.length != 2) return _notFound('Unknown notes route');

    final note = (await _store.getTeacherNotes())
        .where((n) => n['id'] == rest[1])
        .firstOrNull;
    if (note == null) return _fail(404, 'NOT_FOUND', 'Note not found');
    if (method == 'GET') return _Result(200, {'data': note});
    // Edits and deletes: the author or an admin.
    if (!caller.isAdmin && note['authorId'] != caller.id) {
      return _fail(403, 'FORBIDDEN', 'Not the author');
    }
    if (method == 'PUT') {
      for (final field in ['bookName', 'courseCode', 'title']) {
        if (body.containsKey(field) && _optional(body[field]) == null) {
          return _fail(400, 'INVALID_BODY', '$field must not be empty');
        }
      }
      final updated = await _store.updateTeacherNote(
        id: rest[1],
        bookName: body['bookName']?.toString(),
        courseCode: body['courseCode']?.toString(),
        title: body['title']?.toString(),
        content: body['content']?.toString(),
      );
      return _Result(200, {'data': updated});
    }
    if (method == 'DELETE') {
      await _store.deleteTeacherNote(rest[1]);
      return _success();
    }
    return _methodNotAllowed();
  }

  /* ============================================
     EXCEL
     ============================================ */

  Future<_Result> _excelRoute(
    List<String> rest,
    String method,
    Map<String, String> query,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length == 3 &&
        rest[1] == 'import' &&
        rest[2] == 'students' &&
        method == 'POST') {
      if (!caller.isAdmin) return _adminOnly();
      final raw = body['rows'];
      if (raw is! List) {
        return _fail(400, 'INVALID_BODY', 'rows must be an array');
      }
      final courseId = _optional(body['courseId']);
      if (courseId != null && _course(courseId) == null) {
        return _fail(400, 'INVALID_REFERENCE', 'Course not found');
      }
      return _Result(201, {
        'data': await _store.importStudents(
          courseId: courseId ?? '',
          rows: raw.whereType<Map>().map(Map<String, dynamic>.from).toList(),
          enrolledBy: caller.id,
        ),
      });
    }
    if (rest.length == 3 && rest[1] == 'export' && method == 'GET') {
      if (!caller.isStaff) {
        return _fail(403, 'FORBIDDEN', 'Admin or teacher only');
      }
      switch (rest[2]) {
        case 'students':
          return _Result(200, {
            'data': await _store.exportStudents(courseId: query['courseId']),
          });
        case 'attendance':
          return _Result(200, {
            'data': await _store.exportAttendance(
              courseId: query['courseId'],
              date: query['date'],
            ),
          });
        case 'notes':
          return _Result(200, {
            'data': await _store.exportNotes(
              courseId: query['courseId'],
              courseCode: query['courseCode'],
            ),
          });
      }
    }
    return _notFound('Unknown excel route');
  }

  /* ============================================
     CALENDAR
     ============================================ */

  Future<_Result> _calendarRoute(
    List<String> rest,
    String method,
    Map<String, String> query,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length == 1 && method == 'GET') return _calendar(query, caller);
    if (!caller.isStaff) {
      return _fail(403, 'FORBIDDEN', 'Admin or teacher only');
    }
    if (rest.length == 1 && method == 'POST') {
      final title = _optional(body['title']);
      final kind = body['kind']?.toString();
      final startsAt = body['startsAt']?.toString();
      if (title == null || kind == null || startsAt == null) {
        return _fail(
            400, 'INVALID_BODY', 'title, kind and startsAt are required');
      }
      final invalid = _invalidEvent(body);
      if (invalid != null) return _fail(400, 'INVALID_BODY', invalid);
      final courseId = _optional(body['courseId']);
      // Course-less (institution-wide) events are admin-only, like the API.
      if (!_manages(caller, courseId)) {
        return _fail(
            403, 'FORBIDDEN', 'You can only add events to courses you teach');
      }
      final event = await _store.createCalendarEvent(
        title: title,
        kind: kind,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.tryParse(body['endsAt']?.toString() ?? ''),
        departmentId: _optional(body['departmentId']),
        courseId: courseId,
      );
      return _Result(201, {'data': event});
    }
    if (rest.length != 2) return _notFound('Unknown calendar route');

    final id = rest[1];
    if (method == 'PUT' || method == 'PATCH') {
      final invalid = _invalidEvent(body);
      if (invalid != null) return _fail(400, 'INVALID_BODY', invalid);
      final existing = await _store.getCalendarEvent(id);
      if (existing == null) {
        return _fail(404, 'EVENT_NOT_FOUND', 'Calendar event not found');
      }
      // A teacher may edit only their own courses' events, and not move one
      // into a course they do not teach.
      if (!_manages(caller, existing['courseId']?.toString()) ||
          (body.containsKey('courseId') &&
              !_manages(caller, _optional(body['courseId'])))) {
        return _fail(
            403, 'FORBIDDEN', 'You can only edit events of courses you teach');
      }
      if (existing['assignmentId'] != null) return _assignmentEvent();
      // Absent keys keep their value; an explicit null clears it.
      final event = await _store.updateCalendarEvent(
        id: id,
        title: _optional(body['title']),
        kind: body['kind']?.toString(),
        startsAt: DateTime.tryParse(body['startsAt']?.toString() ?? ''),
        endsAt: DateTime.tryParse(body['endsAt']?.toString() ?? ''),
        clearEndsAt: body.containsKey('endsAt') && body['endsAt'] == null,
        departmentId: _optional(body['departmentId']),
        clearDepartment:
            body.containsKey('departmentId') && body['departmentId'] == null,
        courseId: _optional(body['courseId']),
        clearCourse: body.containsKey('courseId') && body['courseId'] == null,
      );
      return _Result(200, {'data': event});
    }
    if (method == 'DELETE') {
      final existing = await _store.getCalendarEvent(id);
      if (existing == null) {
        return _fail(404, 'EVENT_NOT_FOUND', 'Calendar event not found');
      }
      if (!_manages(caller, existing['courseId']?.toString())) {
        return _fail(403, 'FORBIDDEN',
            'You can only delete events of courses you teach');
      }
      if (existing['assignmentId'] != null) return _assignmentEvent();
      await _store.deleteCalendarEvent(id);
      return _success();
    }
    return _methodNotAllowed();
  }

  static _Result _assignmentEvent() => _fail(409, 'ASSIGNMENT_EVENT',
      'This deadline comes from an assignment; edit the assignment instead');

  /// GET /calendar, scoped like the API: non-admins always get their own
  /// courses' events (plus course-less ones); admins may pass `userId`.
  Future<_Result> _calendar(Map<String, String> query, _Caller caller) async {
    final departmentId = query['departmentId'];
    if (!caller.isAdmin) {
      final courseIds = await _readableCourseIds(caller);
      final events = await _store.getCalendarEvents(
        courseIds: courseIds,
        departmentId: departmentId,
      );
      return _Result(200, {
        'data': events
            .where((e) =>
                e['courseId'] == null || courseIds.contains(e['courseId']))
            .toList(),
      });
    }
    Set<String>? courseIds;
    final userId = query['userId'];
    if (userId != null && userId.isNotEmpty) {
      final user = await _userById(userId);
      if (user == null) {
        return _fail(404, 'USER_NOT_FOUND', 'User not found');
      }
      courseIds = await _readableCourseIds(
          _Caller(id: userId, role: user['role']?.toString() ?? 'student'));
    }
    return _Result(200, {
      'data': await _store.getCalendarEvents(
        courseIds: courseIds,
        departmentId: departmentId,
      ),
    });
  }

  /// The API's body checks for an event. Returns an error message or null.
  String? _invalidEvent(Map<String, dynamic> body) {
    if (body.containsKey('title') && _optional(body['title']) == null) {
      return 'title must not be empty';
    }
    if (body.containsKey('kind') && !_eventKinds.contains(body['kind'])) {
      return 'kind must be one of ${_eventKinds.join(', ')}';
    }
    if (body.containsKey('startsAt') &&
        DateTime.tryParse(body['startsAt']?.toString() ?? '') == null) {
      return 'startsAt must be a date';
    }
    if (body['endsAt'] != null &&
        DateTime.tryParse(body['endsAt'].toString()) == null) {
      return 'endsAt must be a date or null';
    }
    return null;
  }

  /* ============================================
     CHAT
     ============================================ */

  /// Per-course channels. CS 301 keeps the original ids that the seeded
  /// messages belong to; other courses get suffixed ids so messages don't
  /// leak between courses. Members: the teacher plus enrolled students.
  Future<List<Map<String, dynamic>>> _channelsFor(
      Map<String, dynamic> course) async {
    final courseId = course['id'] as String;
    final suffix = courseId == 'c-cs301' ? '' : '-$courseId';
    final members = <String>[
      course['teacherId'] as String,
      ...await _enrolledIds(courseId),
    ];
    return [
      {
        'id': 'ch-general$suffix',
        'courseId': courseId,
        'name': 'General',
        'kind': 'discussion',
        'memberIds': members,
      },
      {
        'id': 'ch-announce$suffix',
        'courseId': courseId,
        'name': 'Announcements',
        'kind': 'announcement',
        'memberIds': members,
      },
    ];
  }

  Future<Map<String, dynamic>?> _channel(String id) async {
    for (final course in _courses) {
      for (final channel in await _channelsFor(course)) {
        if (channel['id'] == id) return channel;
      }
    }
    return null;
  }

  Future<_Result> _channelsRoute(
    List<String> rest,
    String method,
    Map<String, dynamic> body,
    _Caller caller,
  ) async {
    if (rest.length != 3 || rest[2] != 'messages') {
      return _notFound('Unknown channel route');
    }
    final channel = await _channel(rest[1]);
    if (channel == null) {
      return _fail(404, 'CHANNEL_NOT_FOUND', 'Channel not found');
    }
    final isMember = (channel['memberIds'] as List).contains(caller.id);
    if (method == 'GET') {
      // Reading is members-only, like posting.
      if (!isMember) return _notAMember();
      return _Result(200, {'data': await _store.getMessages(rest[1])});
    }
    if (method != 'POST') return _methodNotAllowed();
    // The author is always the caller; a body authorId is ignored.
    final text = body['body']?.toString().trim() ?? '';
    if (text.isEmpty) return _fail(400, 'INVALID_BODY', 'body is required');
    if (!isMember) return _notAMember();
    if (channel['kind'] == 'announcement' && caller.role == 'student') {
      return _fail(403, 'ANNOUNCEMENT_RESTRICTED',
          'Students cannot post in announcement channels');
    }
    final message = await _store.postMessage(
      channelId: rest[1],
      authorId: caller.id,
      body: text,
    );
    return _Result(201, {'data': message});
  }

  _Result _notAMember() =>
      _fail(403, 'NOT_A_MEMBER', 'User is not a member of this channel');

  /* ============================================
     HELPERS
     ============================================ */

  /// A non-blank string, trimmed, or null.
  static String? _optional(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Map<String, dynamic> _error(String code, String message) => {
        'error': {'code': code, 'message': message},
      };

  static _Result _fail(int status, String code, String message) =>
      _Result(status, _error(code, message));

  static _Result _notFound(String message) => _fail(404, 'NOT_FOUND', message);

  static _Result _adminOnly() => _fail(403, 'FORBIDDEN', 'Admin only');

  static _Result _methodNotAllowed() =>
      _fail(405, 'METHOD_NOT_ALLOWED', 'Method not allowed');

  static _Result _success() => _Result(200, {
        'data': {'success': true}
      });

  http.StreamedResponse _json(int status, Object? payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      contentLength: bytes.length,
    );
  }
}

class _Caller {
  const _Caller({required this.id, required this.role});

  final String id;
  final String role;

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'admin' || role == 'teacher';
}

class _Result {
  final int status;
  final Map<String, dynamic> body;
  _Result(this.status, this.body);
}
