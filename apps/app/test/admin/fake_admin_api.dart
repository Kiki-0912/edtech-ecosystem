import 'dart:convert';

import 'package:edtech_app/admin/admin_app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
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

/// Seeded demo password (memory store). Not a real credential.
const kDemoPassword = 'password123';

/// The API's message for a disabled account (403 at sign-in, 401 for tokens).
const _disabledMessage = 'This account has been disabled';

/// A scripted failure for the next matching request.
class Failure {
  const Failure(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}

Map<String, dynamic> _user(
  String id,
  String name,
  String role, {
  String email = '',
  String phone = '',
  bool active = true,
  List<String> courseIds = const [],
}) =>
    {
      'id': id,
      'displayName': name,
      'email': email,
      'phone': phone,
      'role': role,
      'isActive': active,
      'isPhoneVerified': true,
      'courseIds': courseIds,
      'createdAt': '2026-07-01T00:00:00.000Z',
    };

/// In-memory fake of the admin API contract behind a `MockClient`.
///
/// `/api/v1/admin/*`, `/auth/login` and `/auth/me` are answered here; every
/// other route is forwarded to the app's [OfflineClient] so the reused main-app
/// screens (departments, calendar, notes, attendance, exports) get realistic
/// data. Every request is recorded in [requests].
class FakeAdminApi {
  FakeAdminApi() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final OfflineClient _offline = OfflineClient();

  /// Every request, in order.
  final List<http.Request> requests = [];

  /// `'METHOD /path'` → failure returned once for the next matching request.
  final Map<String, Failure> failures = {};

  final List<Map<String, dynamic>> users = [
    _user('u-admin-1', 'Usman Shahid', 'admin',
        email: 'usman.shahid@example.edu', phone: '+15550001005'),
    _user('u-admin-2', 'Zara Admin', 'admin', email: 'zara@example.edu'),
    _user('u-teacher-1', 'Tayyab', 'teacher',
        email: 'tayyab@example.edu', phone: '+15550001001'),
    _user('u-student-1', 'Aeliya', 'student',
        email: 'aeliya@example.edu',
        phone: '+15550001002',
        courseIds: ['c-001']),
    _user('u-student-2', 'Sameer', 'student',
        email: 'sameer@example.edu', phone: '+15550001003', active: false),
  ];

  final List<Map<String, dynamic>> courses = [
    {
      'id': 'c-001',
      'title': 'Human-Computer Interaction',
      'code': 'CS 301',
      'term': 'Fall 2026',
      'teacherId': 'u-teacher-1',
      'studentIds': ['u-student-1'],
      'assignmentCount': 2,
      'createdAt': '2026-08-20T00:00:00.000Z',
    },
  ];

  final List<Map<String, dynamic>> integrity = [
    {
      'studentId': 'u-student-1',
      'studentName': 'Aeliya',
      'assignmentId': 'a-001',
      'assignmentTitle': 'Heuristic Evaluation',
      'courseId': 'c-001',
      'courseTitle': 'Human-Computer Interaction',
      'score': 34,
      'flags': ['large_paste', 'ai_tab_switch'],
      'computedAt': '2026-11-20T10:00:00.000Z',
    },
    {
      'studentId': 'u-student-2',
      'studentName': 'Sameer',
      'assignmentId': 'a-001',
      'assignmentTitle': 'Heuristic Evaluation',
      'courseId': 'c-001',
      'courseTitle': 'Human-Computer Interaction',
      'score': 88,
      'flags': ['none'],
      'computedAt': '2026-11-21T10:00:00.000Z',
    },
  ];

  /// Requests to the admin API, as `'METHOD /admin/path?query'`.
  List<String> get adminCalls => [
        for (final r in requests)
          if (r.url.path.startsWith('/api/v1/admin'))
            '${r.method} ${r.url.path.substring('/api/v1'.length)}'
                '${r.url.hasQuery ? '?${r.url.query}' : ''}',
      ];

  /// The decoded JSON body of the last request matching [method] and [path].
  Map<String, dynamic> lastBody(String method, String path) {
    final request = requests
        .lastWhere((r) => r.method == method && r.url.path == '/api/v1$path');
    return jsonDecode(request.body) as Map<String, dynamic>;
  }

  Map<String, dynamic>? userById(String id) =>
      users.where((u) => u['id'] == id).firstOrNull;

  Map<String, dynamic> _course(Map<String, dynamic> c) {
    final ids = List<String>.from(c['studentIds'] as List);
    return {
      ...c,
      'teacherName': userById(c['teacherId'] as String)?['displayName'] ?? '',
      'studentIds': ids,
      'studentCount': ids.length,
    };
  }

  http.Response _json(http.Request request, int status, Object body) =>
      http.Response(jsonEncode(body), status,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response _error(
          http.Request request, int status, String code, String message) =>
      _json(request, status, {
        'error': {'code': code, 'message': message}
      });

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final failure = failures.remove('${request.method} $path');
    if (failure != null) {
      return _error(request, failure.status, failure.code, failure.message);
    }
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    if (path == '/api/v1/auth/me') {
      final token =
          request.headers['Authorization']?.replaceFirst('Bearer ', '');
      final user = token == null ? null : userById(token);
      if (user == null) {
        return _error(request, 401, 'UNAUTHORIZED', 'Invalid or expired token');
      }
      if (user['isActive'] != true) {
        return _error(request, 401, 'ACCOUNT_DISABLED', _disabledMessage);
      }
      return _json(request, 200, {
        'data': {'user': user}
      });
    }
    if (path == '/api/v1/auth/login') {
      final id = body['email'] ?? body['phone'];
      final user = users
          .where((u) => id != null && (u['email'] == id || u['phone'] == id))
          .firstOrNull;
      if (user == null || body['password'] != kDemoPassword) {
        return _error(request, 401, 'INVALID_CREDENTIALS',
            'Invalid phone/email or password');
      }
      if (user['isActive'] != true) {
        return _error(request, 403, 'ACCOUNT_DISABLED', _disabledMessage);
      }
      // The fake uses the user id as the bearer token.
      return _json(request, 200, {
        'data': {'user': user, 'token': user['id']}
      });
    }
    if (path.startsWith('/api/v1/admin/')) {
      // Same guards as the API: authenticate() then the admin-only hook.
      final token =
          request.headers['Authorization']?.replaceFirst('Bearer ', '');
      final caller = token == null ? null : userById(token);
      if (caller == null) {
        return _error(request, 401, 'UNAUTHORIZED', 'Invalid or expired token');
      }
      if (caller['isActive'] != true) {
        return _error(request, 401, 'ACCOUNT_DISABLED', _disabledMessage);
      }
      if (caller['role'] != 'admin') {
        return _error(request, 403, 'FORBIDDEN', 'Admins only');
      }
      return _admin(
          request, path.substring('/api/v1/admin/'.length).split('/'), body);
    }
    return http.Response.fromStream(await _offline.send(request));
  }

  http.Response _admin(
      http.Request request, List<String> parts, Map<String, dynamic> body) {
    final method = request.method;
    final query = request.url.queryParameters;
    http.Response ok(Object data, [int status = 200]) =>
        _json(request, status, {'data': data});
    http.Response notFound(String code) =>
        _error(request, 404, code, 'Not found');
    const success = {'success': true};

    switch (parts) {
      case ['overview'] when method == 'GET':
        int count(String role) => users.where((u) => u['role'] == role).length;
        return ok({
          'counts': {
            'students': count('student'),
            'teachers': count('teacher'),
            'admins': count('admin'),
            'inactiveUsers': users.where((u) => u['isActive'] != true).length,
            'courses': courses.length,
            'departments': 3,
            'assignments': 4,
            'submissions': 12,
            'telemetryBatches': 1234,
            'flaggedReports': integrity
                .where((r) => (r['flags'] as List).any((f) => f != 'none'))
                .length,
          },
          'storage': 'postgres',
          'database': 'ok',
          'schemaVersion': 2,
          'version': '0.3.0',
          'serverTime': '2026-11-22T12:00:00.000Z',
        });
      case ['users'] when method == 'GET':
        final q = query['q']?.toLowerCase();
        final status = query['status'] ?? 'all';
        return ok([
          for (final u in users)
            if ((query['role'] == null || u['role'] == query['role']) &&
                (status == 'all' ||
                    (status == 'active') == (u['isActive'] == true)) &&
                (q == null ||
                    [
                      'displayName',
                      'email',
                      'phone'
                    ].any((k) => (u[k] as String).toLowerCase().contains(q))))
              u,
        ]);
      case ['users'] when method == 'POST':
        final taken = users.any((u) => ['email', 'phone'].any(
            (k) => (body[k] as String? ?? '').isNotEmpty && u[k] == body[k]));
        if (taken) {
          return _error(request, 409, 'USER_EXISTS',
              'A user with this email or phone already exists');
        }
        final user = _user('u-new-${users.length + 1}',
            body['displayName'] as String, body['role'] as String,
            email: body['email'] as String? ?? '',
            phone: body['phone'] as String? ?? '');
        users.add(user);
        return ok(user, 201);
      case ['users', final id] when method == 'PATCH':
        final user = userById(id);
        if (user == null) return notFound('USER_NOT_FOUND');
        user.addAll(body);
        return ok(user);
      case ['users', final id] when method == 'DELETE':
        if (userById(id) == null) return notFound('USER_NOT_FOUND');
        users.removeWhere((u) => u['id'] == id);
        return ok(success);
      case ['users', final id, 'password'] when method == 'POST':
        if (userById(id) == null) return notFound('USER_NOT_FOUND');
        return ok(success);
      case ['courses'] when method == 'GET':
        return ok([for (final c in courses) _course(c)]);
      case ['courses'] when method == 'POST':
        final course = {
          'id': 'c-new-${courses.length + 1}',
          ...body,
          'studentIds': <String>[],
          'assignmentCount': 0,
          'createdAt': '2026-11-22T00:00:00.000Z',
        };
        courses.add(course);
        return ok(_course(course), 201);
      case ['courses', final id] when method == 'PATCH':
        final course = courses.where((c) => c['id'] == id).firstOrNull;
        if (course == null) return notFound('COURSE_NOT_FOUND');
        course.addAll(body);
        return ok(_course(course));
      case ['courses', final id] when method == 'DELETE':
        if (!courses.any((c) => c['id'] == id)) {
          return notFound('COURSE_NOT_FOUND');
        }
        courses.removeWhere((c) => c['id'] == id);
        return ok(success);
      case ['courses', final id, 'students'] when method == 'PUT':
        final course = courses.where((c) => c['id'] == id).firstOrNull;
        if (course == null) return notFound('COURSE_NOT_FOUND');
        course['studentIds'] = List<String>.from(body['studentIds'] as List);
        return ok(_course(course));
      case ['integrity'] when method == 'GET':
        final flaggedOnly = query['flagged'] == 'true';
        return ok([
          for (final r in integrity)
            if (!flaggedOnly || (r['flags'] as List).any((f) => f != 'none')) r,
        ]);
    }
    return _error(request, 404, 'NOT_FOUND', 'Unknown admin route');
  }
}

/// A persisted session for [userId] in the shape `AuthProvider` restores.
Map<String, Object> sessionFor(FakeAdminApi api, String userId) => {
      // The fake's bearer token is the user id.
      'auth_token': userId,
      'auth_user': jsonEncode(api.userById(userId)),
    };

/// Points [ApiService] at [api] (online mode) for the current test.
void useFakeApi(FakeAdminApi api) {
  ApiService.instance
    ..offlineMode = false
    ..httpClientOverride = api.client
    ..token = null;
  addTearDown(() {
    ApiService.instance
      ..httpClientOverride = null
      ..offlineMode = null
      ..token = null
      ..onUnauthorized = null;
  });
}

/// Restores the session (if [userId] is set) and returns the AuthProvider.
Future<AuthProvider> signIn(FakeAdminApi api, String? userId) async {
  SharedPreferences.setMockInitialValues(
      userId == null ? <String, Object>{} : sessionFor(api, userId));
  useFakeApi(api);
  final auth = AuthProvider();
  await auth.init();
  ApiService.instance.token = auth.token;
  return auth;
}

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Advances the clock without waiting for looping animations to settle.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Pumps the whole admin console (router, shell, login).
Future<AuthProvider> pumpAdminApp(
  WidgetTester tester,
  FakeAdminApi api, {
  String? userId,
  Size size = const Size(1440, 900),
}) async {
  setSize(tester, size);
  final auth = await signIn(api, userId);
  final theme = ThemeController.instance;
  await theme.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ],
    // A fresh key so a second pump in one test builds a new app state.
    child: AdminApp(key: UniqueKey()),
  ));
  await settle(tester);
  return auth;
}

/// Pumps one screen on its own (no router), the way the layout matrix does.
Future<void> pumpAdminScreen(
  WidgetTester tester,
  AuthProvider auth,
  Widget screen, {
  Size size = const Size(1280, 900),
  bool dark = false,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance),
    ],
    child: MaterialApp(
      theme: dark ? darkTheme : lightTheme,
      home: Scaffold(body: screen),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await settle(tester);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

/// Opens a row's popup menu and picks the item with [actionKey].
Future<void> pickMenu(
    WidgetTester tester, String menuKey, String actionKey) async {
  await tapKey(tester, menuKey);
  await tester.tap(find.byKey(Key(actionKey)));
  await settle(tester);
}

/// Types into a `PasswordField` (its key sits on the wrapper widget).
Future<void> enterPassword(
    WidgetTester tester, String key, String password) async {
  await tester.enterText(
      find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(TextFormField)),
      password);
}
