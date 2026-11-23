import 'package:edtech_app/admin/admin_access.dart';
import 'package:edtech_app/admin/admin_destinations.dart';
import 'package:edtech_app/admin/screens/users_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_admin_api.dart';

Finder get _loginSubmit => find.byKey(const Key('admin-login-submit'));

Future<void> _signInWith(
    WidgetTester tester, String identifier, String password) async {
  await tester.enterText(
      find.byKey(const Key('admin-login-identifier')), identifier);
  await enterPassword(tester, 'admin-login-password', password);
  await tester.tap(_loginSubmit);
  await settle(tester);
}

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('router guard', () {
    testWidgets('signed out: every route redirects to the login screen',
        (tester) async {
      final api = FakeAdminApi();
      await pumpAdminApp(tester, api);
      expect(_loginSubmit, findsOneWidget);

      for (final d in kAdminDestinations) {
        _router(tester).go(d.path);
        await settle(tester, frames: 3);
        expect(_router(tester).state.matchedLocation, '/login', reason: d.path);
      }
      // Email-or-phone + password only: no sign-up and no SMS sign-in.
      expect(find.byKey(const Key('login-create-account')), findsNothing);
      expect(find.byKey(const Key('login-sms')), findsNothing);
      expect(find.text('Create an account'), findsNothing);
      expect(find.textContaining('code'), findsNothing);
      expect(api.adminCalls, isEmpty);
    });

    testWidgets('a restored non-admin session is signed out', (tester) async {
      final api = FakeAdminApi();
      final auth = await pumpAdminApp(tester, api, userId: 'u-teacher-1');

      expect(auth.isAuthenticated, isFalse);
      expect(_loginSubmit, findsOneWidget);
      expect(find.text(AdminAccess.deniedMessage), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(api.adminCalls, isEmpty);
    });

    testWidgets('an admin session is admitted to the overview', (tester) async {
      final api = FakeAdminApi();
      final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');

      expect(auth.isAuthenticated, isTrue);
      expect(_loginSubmit, findsNothing);
      expect(find.byKey(adminOverview.navKey), findsOneWidget);
      expect(find.byKey(const Key('overview-students')), findsOneWidget);
      expect(api.adminCalls, contains('GET /admin/overview'));

      // An admin on /login is sent back into the console.
      _router(tester).go('/login');
      await settle(tester, frames: 3);
      expect(_router(tester).state.matchedLocation, '/');
    });
  });

  group('sign-in', () {
    testWidgets('a teacher signing in is refused with "Admin access only"',
        (tester) async {
      final api = FakeAdminApi();
      final auth = await pumpAdminApp(tester, api);

      await _signInWith(tester, 'tayyab@example.edu', kDemoPassword);

      expect(api.lastBody('POST', '/auth/login'),
          {'email': 'tayyab@example.edu', 'password': kDemoPassword});
      expect(auth.isAuthenticated, isFalse);
      expect(_loginSubmit, findsOneWidget);
      expect(find.text(AdminAccess.deniedMessage), findsOneWidget);
      expect(api.adminCalls, isEmpty);
    });

    testWidgets('an admin signing in by phone lands on the overview',
        (tester) async {
      final api = FakeAdminApi();
      final auth = await pumpAdminApp(tester, api);

      await _signInWith(tester, '+15550001005', kDemoPassword);

      expect(api.lastBody('POST', '/auth/login'),
          {'phone': '+15550001005', 'password': kDemoPassword});
      expect(auth.user?.id, 'u-admin-1');
      expect(find.byKey(const Key('overview-students')), findsOneWidget);
      expect(ApiService.instance.token, 'u-admin-1');
    });

    testWidgets('wrong password and disabled accounts show the API message',
        (tester) async {
      final api = FakeAdminApi();
      final auth = await pumpAdminApp(tester, api);

      await _signInWith(tester, 'usman.shahid@example.edu', 'wrong-password');
      expect(find.text('Invalid phone/email or password'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);

      api.userById('u-admin-2')!['isActive'] = false;
      await _signInWith(tester, 'zara@example.edu', kDemoPassword);
      expect(find.text('This account has been disabled'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('empty fields are validated', (tester) async {
      final api = FakeAdminApi();
      await pumpAdminApp(tester, api);
      await tester.tap(_loginSubmit);
      await settle(tester);
      expect(find.text('Please enter your email or phone'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      expect(api.requests.where((r) => r.url.path.contains('/auth/login')),
          isEmpty);
    });
  });

  testWidgets('a 401 from any request signs the admin out', (tester) async {
    final api = FakeAdminApi();
    final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');
    expect(auth.isAuthenticated, isTrue);

    // Another admin deactivated this account: its token now gets 401.
    api.userById('u-admin-1')!['isActive'] = false;
    await tester.tap(find.byKey(adminUsers.navKey));
    await settle(tester);

    expect(auth.isAuthenticated, isFalse);
    expect(_loginSubmit, findsOneWidget);
    // The login screen says why.
    expect(find.text('This account has been disabled'), findsOneWidget);
  });

  testWidgets('a revoked or expired session says so on the login screen',
      (tester) async {
    final api = FakeAdminApi()
      ..failures['GET /api/v1/admin/users'] = const Failure(
          401, 'SESSION_REVOKED', 'This session has ended. Sign in again.');
    await pumpAdminApp(tester, api, userId: 'u-admin-1');
    await tester.tap(find.byKey(adminUsers.navKey));
    await settle(tester);
    expect(_loginSubmit, findsOneWidget);
    expect(find.text('This session has ended. Sign in again.'), findsOneWidget);

    // Signing in again clears the notice; a plain 401 reads as expired.
    api.failures['GET /api/v1/admin/overview'] =
        const Failure(401, 'UNAUTHORIZED', 'Invalid or expired token');
    await _signInWith(tester, 'usman.shahid@example.edu', kDemoPassword);
    expect(api.adminCalls.last, 'GET /admin/overview');
    expect(_loginSubmit, findsOneWidget);
    expect(find.text('This session has ended. Sign in again.'), findsNothing);
    expect(
        find.text('Your session has expired. Sign in again.'), findsOneWidget);
  });

  testWidgets('shared screens show an error, never demo data, on API failure',
      (tester) async {
    final api = FakeAdminApi()
      ..failures['GET /api/v1/courses'] =
          const Failure(500, 'INTERNAL_ERROR', 'Database unreachable')
      ..failures['GET /api/v1/calendar'] =
          const Failure(500, 'INTERNAL_ERROR', 'Database unreachable');
    await pumpAdminApp(tester, api, userId: 'u-admin-1');

    await tester.tap(find.byKey(adminAttendance.navKey));
    await settle(tester);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('Data Structures'), findsNothing);

    await tester.tap(find.byKey(adminCalendar.navKey));
    await settle(tester);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('Heuristic Evaluation'), findsNothing);
  });

  testWidgets('editing your own name updates the sidebar', (tester) async {
    final api = FakeAdminApi();
    final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');
    await tester.tap(find.byKey(adminUsers.navKey));
    await settle(tester);

    await pickMenu(tester, 'user-menu-u-admin-1', 'user-action-edit');
    await tester.enterText(find.byKey(const Key('user-name')), 'Usman S.');
    await tapKey(tester, 'user-save');

    expect(auth.user?.displayName, 'Usman S.');
    expect(find.text('Usman Shahid'), findsNothing);
    // The users list and the sidebar footer.
    expect(find.text('Usman S.'), findsNWidgets(2));
  });

  testWidgets('resetting your own password signs you out and says why',
      (tester) async {
    final api = FakeAdminApi();
    final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');
    await tester.tap(find.byKey(adminUsers.navKey));
    await settle(tester);

    await pickMenu(tester, 'user-menu-u-admin-1', 'user-action-password');
    expect(find.textContaining('your own account'), findsOneWidget);
    await enterPassword(tester, 'user-new-password', 'brand-new-pass');
    await tapKey(tester, 'user-password-save');

    expect(api.lastBody('POST', '/admin/users/u-admin-1/password'),
        {'password': 'brand-new-pass'});
    // The reset revoked this session's token too: sign in again right away.
    expect(auth.isAuthenticated, isFalse);
    expect(_loginSubmit, findsOneWidget);
    expect(find.text(kOwnPasswordChangedMessage), findsOneWidget);
  });

  testWidgets("resetting another user's password keeps you signed in",
      (tester) async {
    final api = FakeAdminApi();
    final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');
    await tester.tap(find.byKey(adminUsers.navKey));
    await settle(tester);

    await pickMenu(tester, 'user-menu-u-student-1', 'user-action-password');
    expect(find.textContaining('your own account'), findsNothing);
    await enterPassword(tester, 'user-new-password', 'brand-new-pass');
    await tapKey(tester, 'user-password-save');

    expect(auth.isAuthenticated, isTrue);
    expect(find.text('Password updated for Aeliya'), findsOneWidget);
  });

  testWidgets('overview tiles open Users filtered by role or status',
      (tester) async {
    final api = FakeAdminApi();
    await pumpAdminApp(tester, api, userId: 'u-admin-1');

    Future<void> openTile(String key) async {
      await tester.tap(find.byKey(adminOverview.navKey));
      await settle(tester);
      await tapKey(tester, 'overview-$key');
    }

    await openTile('students');
    expect(api.adminCalls.last, 'GET /admin/users?role=student&status=all');
    expect(find.text('Aeliya'), findsOneWidget);
    expect(find.text('Tayyab'), findsNothing);

    await openTile('teachers');
    expect(api.adminCalls.last, 'GET /admin/users?role=teacher&status=all');

    await openTile('admins');
    expect(api.adminCalls.last, 'GET /admin/users?role=admin&status=all');

    await openTile('inactive');
    expect(api.adminCalls.last, 'GET /admin/users?status=inactive');
    expect(find.text('Sameer'), findsOneWidget);

    // After changing the chips by hand, the same tile still applies its filter.
    await openTile('students');
    await tester.tap(find.text('All roles'));
    await settle(tester);
    expect(api.adminCalls.last, 'GET /admin/users?status=all');
    await openTile('students');
    expect(api.adminCalls.last, 'GET /admin/users?role=student&status=all');
  });

  testWidgets('sign out from the account menu returns to login',
      (tester) async {
    final api = FakeAdminApi();
    final auth = await pumpAdminApp(tester, api, userId: 'u-admin-1');
    await tapKey(tester, 'admin-account');
    await tester.tap(find.byKey(const Key('admin-logout')));
    await settle(tester);
    expect(auth.isAuthenticated, isFalse);
    expect(_loginSubmit, findsOneWidget);
    // A deliberate sign-out is not an access refusal.
    expect(find.text(AdminAccess.deniedMessage), findsNothing);
  });

  group('navigation', () {
    const markers = <String, String>{
      'overview': 'overview-students',
      'users': 'users-add',
      'courses': 'courses-add',
      'departments': 'department-add',
      'calendar': 'calendar-add',
      'attendance': 'attendance-mark',
      'notes': 'notes-search',
      'import-export': 'import-export-import',
      'integrity': 'integrity-filter',
    };

    testWidgets('desktop sidebar opens every section', (tester) async {
      final api = FakeAdminApi();
      await pumpAdminApp(tester, api, userId: 'u-admin-1');
      expect(find.text('Admin'), findsWidgets);
      for (final d in kAdminDestinations) {
        await tester.tap(find.byKey(d.navKey));
        await settle(tester);
        expect(find.byKey(Key(markers[d.id]!)), findsWidgets, reason: d.id);
        expect(tester.takeException(), isNull, reason: d.id);
      }
    });

    testWidgets('tablet rail opens every section', (tester) async {
      final api = FakeAdminApi();
      await pumpAdminApp(tester, api,
          userId: 'u-admin-1', size: const Size(800, 1000));
      expect(find.byType(NavigationRail), findsOneWidget);
      for (final d in kAdminDestinations) {
        await tester.ensureVisible(find.byKey(d.navKey));
        await tester.tap(find.byKey(d.navKey));
        await settle(tester);
        expect(find.byKey(Key(markers[d.id]!)), findsWidgets, reason: d.id);
      }
    });

    testWidgets('phone bottom bar and More sheet open every section',
        (tester) async {
      final api = FakeAdminApi();
      await pumpAdminApp(tester, api,
          userId: 'u-admin-1', size: const Size(390, 844));
      for (final d in adminPrimary) {
        await tester.tap(find.byKey(d.navKey));
        await settle(tester);
        expect(find.byKey(Key(markers[d.id]!)), findsWidgets, reason: d.id);
      }
      for (final d in adminMore) {
        await tester.tap(find.byKey(const Key('nav-more')));
        await settle(tester);
        await tester.tap(find.byKey(Key('more-${d.id}')));
        await settle(tester);
        expect(find.byKey(Key(markers[d.id]!)), findsWidgets, reason: d.id);
        expect(tester.takeException(), isNull, reason: d.id);
      }
    });
  });
}
