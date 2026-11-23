import 'dart:io';

import 'package:edtech_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Admin API contract against the local API (http://127.0.0.1:4000).
///
/// Run the API first: `npm run dev:api` from the repository root. The suite
/// skips itself when the API is unreachable. Uses the seeded demo admin
/// (memory store password, not a real credential).
void main() {
  final api = ApiService.instance;
  const adminEmail = 'usman.shahid@example.edu';
  const password = 'password123';

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding answers every real HTTP request with 400; restore
    // networking so this suite exercises the live API.
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

  test('admin signs in by email and reads the console data', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final login = await api.login(email: adminEmail, password: password);
    api.token = login['token'] as String;

    final overview = await api.adminOverview();
    expect(overview.counts.admins, greaterThanOrEqualTo(1));
    expect(['memory', 'postgres'], contains(overview.storage));

    final admins = await api.adminListUsers(role: 'admin');
    expect(admins.map((u) => u.email), contains(adminEmail));
    expect(admins.every((u) => u.isAdmin), isTrue);

    final courses = await api.adminListCourses();
    expect(courses, isNotEmpty);
    expect(courses.first.teacherName, isNotEmpty);

    await api.adminIntegrity(flaggedOnly: true);
  });

  test('a deactivated account cannot sign in; delete cleans it up', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final login = await api.login(email: adminEmail, password: password);
    api.token = login['token'] as String;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'admin-itest-$stamp@test.dev';
    final user = await api.adminCreateUser(
      displayName: 'Admin Integration',
      email: email,
      role: 'teacher',
      password: 'temporary-pass',
    );
    try {
      expect(user.isTeacher, isTrue);
      expect(user.isActive, isTrue);

      final disabled = await api.adminUpdateUser(user.id, isActive: false);
      expect(disabled.isActive, isFalse);
      await expectLater(
        api.login(email: email, password: 'temporary-pass'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.code, 'code', 'ACCOUNT_DISABLED')),
      );
    } finally {
      await api.adminDeleteUser(user.id);
    }
  });

  test('a non-admin token is forbidden from the admin API', () async {
    if (!await apiReachable()) {
      markTestSkipped('API not reachable on localhost:4000');
      return;
    }
    final login = await api.login(phone: '+15550001002', password: password);
    api.token = login['token'] as String;
    await expectLater(
      api.adminOverview(),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 403)
          .having((e) => e.code, 'code', 'FORBIDDEN')),
    );
  });
}
