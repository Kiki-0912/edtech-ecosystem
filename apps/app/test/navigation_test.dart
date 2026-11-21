import 'dart:convert';

import 'package:edtech_app/app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/shell/destinations.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _session(String role) => {
      'auth_token': 'offline-demo-token',
      'auth_user': jsonEncode({
        'id': 'u-$role-1',
        'displayName': 'Test ${role[0].toUpperCase()}${role.substring(1)}',
        'email': '$role@example.edu',
        'phone': '+15550000000',
        'role': role,
        'courseIds': ['c-cs301'],
        'createdAt': '2026-07-01T00:00:00.000Z',
      }),
    };

Future<void> _pumpAs(WidgetTester tester, String role) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(_session(role));
  final auth = AuthProvider();
  await auth.init();
  final theme = ThemeController.instance;
  await theme.load();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ],
    child: const EdTechApp(),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('navForRole', () {
    test('student never sees admin sections', () {
      final ids = navForRole('student').all.map((d) => d.id);
      expect(ids, isNot(contains('departments')));
      expect(ids, isNot(contains('students')));
    });

    test('every role keeps at most 4 primary tabs and has Profile', () {
      for (final role in ['student', 'teacher', 'admin']) {
        final nav = navForRole(role);
        expect(nav.primary.length, lessThanOrEqualTo(4), reason: role);
        expect(nav.all, contains(profile), reason: role);
      }
    });

    test('route guards', () {
      expect(canAccess('student', '/departments'), isFalse);
      expect(canAccess('student', '/attendance/mark'), isFalse);
      expect(canAccess('student', '/attendance'), isTrue);
      expect(canAccess('teacher', '/students'), isTrue);
      expect(canAccess('teacher', '/departments'), isFalse);
      expect(canAccess('admin', '/departments'), isTrue);
    });
  });

  for (final role in ['student', 'teacher', 'admin']) {
    testWidgets('$role sees its primary tabs in the bottom bar',
        (tester) async {
      await _pumpAs(tester, role);
      final nav = navForRole(role);
      for (final d in nav.primary) {
        expect(find.byKey(d.navKey), findsOneWidget, reason: '$role → ${d.id}');
      }
      expect(find.byKey(const Key('nav-more')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('student is redirected away from /departments', (tester) async {
    await _pumpAs(tester, 'student');
    final context = tester.element(find.byKey(home.navKey));
    GoRouter.of(context).go('/departments');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(GoRouter.of(context).state.matchedLocation, '/');
  });
}
