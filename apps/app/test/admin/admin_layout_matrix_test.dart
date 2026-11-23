import 'package:edtech_app/admin/admin_destinations.dart';
import 'package:edtech_app/admin/screens/courses_screen.dart';
import 'package:edtech_app/admin/screens/import_export_screen.dart';
import 'package:edtech_app/admin/screens/integrity_screen.dart';
import 'package:edtech_app/admin/screens/overview_screen.dart';
import 'package:edtech_app/admin/screens/users_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_mark_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_screen.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/departments/departments_screen.dart';
import 'package:edtech_app/screens/notes/notes_screen.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_admin_api.dart';

/// Renders every admin console screen (its own and the reused main-app ones)
/// at phone / tablet / desktop widths, in light and dark, plus 1.3x text on a
/// phone, against the fake admin API. Any overflow or exception fails.
final Map<String, Widget Function()> adminScreens = {
  'overview': () => const AdminOverviewScreen(),
  'users': () => const AdminUsersScreen(),
  'courses': () => const AdminCoursesScreen(),
  'departments': () => const DepartmentsScreen(),
  'calendar': () => const CalendarScreen(),
  'attendance': () => const AttendanceScreen(),
  'attendance-mark': () => const AttendanceMarkScreen(),
  'notes': () => const NotesScreen(),
  'import-export': () => const AdminImportExportScreen(),
  'integrity': () => const AdminIntegrityScreen(),
};

const sizes = <String, Size>{
  'phone': Size(390, 844),
  'tablet': Size(800, 1000),
  'desktop': Size(1440, 900),
};

void main() {
  for (final entry in adminScreens.entries) {
    testWidgets('${entry.key} renders at all sizes, light & dark',
        (tester) async {
      addTearDown(tester.view.reset);
      final api = FakeAdminApi();
      final auth = await signIn(api, 'u-admin-1');
      for (final size in sizes.entries) {
        for (final dark in [false, true]) {
          await pumpAdminScreen(
            tester,
            auth,
            KeyedSubtree(
                key: ValueKey('${size.key}-$dark'), child: entry.value()),
            size: size.value,
            dark: dark,
          );
          expect(tester.takeException(), isNull,
              reason: '${entry.key}/${size.key}/${dark ? 'dark' : 'light'}');
        }
      }
    });

    testWidgets('${entry.key} survives 1.3x text on a phone', (tester) async {
      addTearDown(tester.view.reset);
      final api = FakeAdminApi();
      final auth = await signIn(api, 'u-admin-1');
      await pumpAdminScreen(tester, auth, entry.value(),
          size: sizes['phone']!, textScale: 1.3);
      expect(tester.takeException(), isNull, reason: entry.key);
    });
  }

  group('forms survive 1.3x text on a phone', () {
    Future<void> openForm(WidgetTester tester, Widget screen,
        Future<void> Function() open) async {
      addTearDown(tester.view.reset);
      final api = FakeAdminApi();
      final auth = await signIn(api, 'u-admin-1');
      await pumpAdminScreen(tester, auth, screen,
          size: sizes['phone']!, textScale: 1.3);
      await open();
      expect(tester.takeException(), isNull);
    }

    testWidgets('new user', (tester) async {
      await openForm(
          tester, const AdminUsersScreen(), () => tapKey(tester, 'users-add'));
      expect(find.byKey(const Key('user-save')), findsOneWidget);
    });

    testWidgets('reset password', (tester) async {
      await openForm(
          tester,
          const AdminUsersScreen(),
          () => pickMenu(
              tester, 'user-menu-u-student-1', 'user-action-password'));
      expect(find.byKey(const Key('user-password-save')), findsOneWidget);
    });

    testWidgets('new course', (tester) async {
      await openForm(tester, const AdminCoursesScreen(),
          () => tapKey(tester, 'courses-add'));
      expect(find.byKey(const Key('course-save')), findsOneWidget);
    });

    testWidgets('roster', (tester) async {
      await openForm(tester, const AdminCoursesScreen(),
          () => pickMenu(tester, 'course-menu-c-001', 'course-action-roster'));
      expect(find.byKey(const Key('roster-save')), findsOneWidget);
    });
  });

  group('shell', () {
    const shellSizes = <String, Size>{
      ...sizes,
      // Medium width but short: the rail must scroll, not overflow.
      'landscape-phone': Size(844, 390),
    };

    for (final entry in shellSizes.entries) {
      testWidgets('login and console render on ${entry.key}, light & dark',
          (tester) async {
        addTearDown(() => ThemeController.instance.setMode(ThemeMode.system));
        for (final dark in [false, true]) {
          await ThemeController.instance
              .setMode(dark ? ThemeMode.dark : ThemeMode.light);
          // Signed out: the login screen.
          await pumpAdminApp(tester, FakeAdminApi(), size: entry.value);
          expect(find.byKey(const Key('admin-login-submit')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'login/$dark');

          // Signed in: every section inside the shell.
          final api = FakeAdminApi();
          await pumpAdminApp(tester, api,
              userId: 'u-admin-1', size: entry.value);
          for (final d in kAdminDestinations) {
            final context = tester.element(find.byType(Scaffold).first);
            GoRouter.of(context).go(d.path);
            await settle(tester, frames: 4);
            expect(tester.takeException(), isNull,
                reason: '${entry.key}/${d.id}/$dark');
          }
        }
      });
    }

    testWidgets('console survives 1.3x text on a phone', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAdminApp(tester, FakeAdminApi(), size: sizes['phone']!);
      expect(tester.takeException(), isNull, reason: 'login');
      await pumpAdminApp(tester, FakeAdminApi(),
          userId: 'u-admin-1', size: sizes['phone']!);
      for (final d in kAdminDestinations) {
        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go(d.path);
        await settle(tester, frames: 4);
        expect(tester.takeException(), isNull, reason: d.id);
      }
    });
  });
}
