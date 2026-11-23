import 'package:edtech_app/admin/screens/courses_screen.dart';
import 'package:edtech_app/admin/screens/import_export_screen.dart';
import 'package:edtech_app/admin/screens/integrity_screen.dart';
import 'package:edtech_app/admin/screens/overview_screen.dart';
import 'package:edtech_app/admin/screens/users_screen.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/attendance/attendance_screen.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/departments/departments_screen.dart';
import 'package:edtech_app/screens/notes/notes_screen.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_admin_api.dart';

/// Signs in as the seeded admin against a fresh fake and pumps [screen].
Future<FakeAdminApi> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(1280, 900),
    void Function(FakeAdminApi api)? setup}) async {
  addTearDown(tester.view.reset);
  final api = FakeAdminApi();
  setup?.call(api);
  final AuthProvider auth = await signIn(api, 'u-admin-1');
  await pumpAdminScreen(tester, auth, screen, size: size);
  return api;
}

void main() {
  group('overview', () {
    testWidgets('shows counts and system status', (tester) async {
      final api = await _pump(tester, const AdminOverviewScreen());
      expect(api.adminCalls, ['GET /admin/overview']);
      String tile(String key) =>
          (tester.widget<StatTile>(find.byKey(Key('overview-$key')))).value;
      expect(tile('students'), '2');
      expect(tile('teachers'), '1');
      expect(tile('admins'), '2');
      expect(tile('inactive'), '1');
      expect(tile('courses'), '1');
      expect(tile('telemetry'), '1,234');
      expect(tile('flagged'), '1');
      expect(find.text('PostgreSQL'), findsOneWidget);
      expect(find.text('Reachable'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // schema version
      expect(find.text('0.3.0'), findsOneWidget);
    });

    testWidgets('shows the API error instead of demo data', (tester) async {
      addTearDown(tester.view.reset);
      final api = FakeAdminApi()
        ..failures['GET /api/v1/admin/overview'] =
            const Failure(500, 'INTERNAL', 'Database unreachable');
      final auth = await signIn(api, 'u-admin-1');
      await pumpAdminScreen(tester, auth, const AdminOverviewScreen());
      expect(find.text('Database unreachable'), findsOneWidget);
      expect(find.byKey(const Key('overview-students')), findsNothing);
    });
  });

  group('users', () {
    testWidgets('lists, searches and filters through the API', (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      expect(api.adminCalls.last, 'GET /admin/users?status=all');
      expect(find.text('Usman Shahid'), findsOneWidget);
      expect(find.text('Sameer'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(
          tester
              .widget<StatusBadge>(
                  find.byKey(const Key('user-status-u-student-2')))
              .label,
          'Inactive');

      await tester.enterText(find.byKey(const Key('users-search')), 'tay');
      await settle(tester, frames: 4); // past the 300 ms debounce
      expect(api.adminCalls.last, 'GET /admin/users?q=tay&status=all');
      expect(find.text('Tayyab'), findsOneWidget);
      expect(find.text('Aeliya'), findsNothing);

      await tester.enterText(find.byKey(const Key('users-search')), '');
      await settle(tester, frames: 4);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('users-role-filter')),
          matching: find.text('Students')));
      await settle(tester);
      expect(api.adminCalls.last, 'GET /admin/users?role=student&status=all');

      await tester.tap(find.descendant(
          of: find.byKey(const Key('users-status-filter')),
          matching: find.text('Inactive')));
      await settle(tester);
      expect(
          api.adminCalls.last, 'GET /admin/users?role=student&status=inactive');
      expect(find.text('Sameer'), findsOneWidget);
      expect(find.text('Aeliya'), findsNothing);
    });

    testWidgets('creates a user with any role and a password', (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await tapKey(tester, 'users-add');

      // Validation: name, a contact and an 8+ character password.
      await tapKey(tester, 'user-save');
      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter an email or a phone number'), findsOneWidget);
      expect(find.text('Enter a password'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('user-name')), 'Nadia Khan');
      await tester.enterText(
          find.byKey(const Key('user-email')), 'nadia@example.edu');
      await enterPassword(tester, 'user-password', 'short');
      await tapKey(tester, 'user-save');
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      await tapKey(tester, 'user-role');
      await tester.tap(find.text('Teacher').last);
      await settle(tester);
      await enterPassword(tester, 'user-password', 'longenough1');
      await tapKey(tester, 'user-save');

      expect(api.lastBody('POST', '/admin/users'), {
        'displayName': 'Nadia Khan',
        'email': 'nadia@example.edu',
        'role': 'teacher',
        'password': 'longenough1',
      });
      expect(find.text('User created'), findsOneWidget);
      expect(find.text('Nadia Khan'), findsOneWidget);
    });

    testWidgets('shows USER_EXISTS in the form and keeps it open',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await tapKey(tester, 'users-add');
      await tester.enterText(find.byKey(const Key('user-name')), 'Copy');
      await tester.enterText(
          find.byKey(const Key('user-email')), 'tayyab@example.edu');
      await enterPassword(tester, 'user-password', 'longenough1');
      await tapKey(tester, 'user-save');

      expect(api.adminCalls.last, 'POST /admin/users');
      expect(find.byKey(const Key('user-form-error')), findsOneWidget);
      expect(find.text('A user with this email or phone already exists'),
          findsOneWidget);
      expect(find.byKey(const Key('user-save')), findsOneWidget);
    });

    testWidgets('edits only the changed fields', (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-teacher-1', 'user-action-edit');
      await tester.enterText(
          find.byKey(const Key('user-name')), 'Tayyab Ahmed');
      await tester.enterText(find.byKey(const Key('user-phone')), '');
      await tapKey(tester, 'user-role');
      await tester.tap(find.text('Admin').last);
      await settle(tester);
      await tapKey(tester, 'user-save');
      // A role change is confirmed first (see the next test).
      await tapKey(tester, 'confirm-dialog-ok');

      expect(api.adminCalls.last, 'GET /admin/users?status=all');
      expect(api.lastBody('PATCH', '/admin/users/u-teacher-1'), {
        'displayName': 'Tayyab Ahmed',
        'phone': '',
        'role': 'admin',
      });
      expect(find.text('User updated'), findsOneWidget);
      expect(find.text('Tayyab Ahmed'), findsOneWidget);
    });

    testWidgets('asks before changing a role; Cancel sends nothing',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-student-1', 'user-action-edit');
      await tapKey(tester, 'user-role');
      await tester.tap(find.text('Teacher').last);
      await settle(tester);

      await tapKey(tester, 'user-save');
      expect(
          find.text('Change Aeliya from Student to Teacher?'), findsOneWidget);
      expect(find.textContaining('removed from every course roster'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(api.adminCalls.where((c) => c.startsWith('PATCH')), isEmpty);
      // The form stays open with the choice, ready to save or change.
      expect(find.byKey(const Key('user-save')), findsOneWidget);

      await tapKey(tester, 'user-save');
      await tapKey(tester, 'confirm-dialog-ok');
      expect(api.lastBody('PATCH', '/admin/users/u-student-1'),
          {'role': 'teacher'});
      expect(find.text('User updated'), findsOneWidget);
    });

    testWidgets('promoting to admin warns about full access', (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-teacher-1', 'user-action-edit');
      await tapKey(tester, 'user-role');
      await tester.tap(find.text('Admin').last);
      await settle(tester);
      await tapKey(tester, 'user-save');
      expect(find.textContaining('Admins can manage every account'),
          findsOneWidget);
      expect(find.textContaining('course roster'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(api.adminCalls.where((c) => c.startsWith('PATCH')), isEmpty);
    });

    testWidgets('a name-only edit saves without a confirmation',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-student-1', 'user-action-edit');
      await tester.enterText(find.byKey(const Key('user-name')), 'Aeliya K');
      await tapKey(tester, 'user-save');
      expect(find.byKey(const Key('confirm-dialog-ok')), findsNothing);
      expect(api.lastBody('PATCH', '/admin/users/u-student-1'),
          {'displayName': 'Aeliya K'});
    });

    testWidgets('each row menu is labelled with its user', (tester) async {
      await _pump(tester, const AdminUsersScreen());
      expect(find.byTooltip('Actions'), findsNothing);
      expect(find.byTooltip('Actions for Aeliya'), findsOneWidget);
      expect(find.byTooltip('Actions for Usman Shahid'), findsOneWidget);
    });

    testWidgets('password fields for other users are new-password fields',
        (tester) async {
      List<String>? hints(String key) => tester
          .widget<TextField>(find.descendant(
              of: find.byKey(Key(key)), matching: find.byType(TextField)))
          .autofillHints
          ?.toList();

      await _pump(tester, const AdminUsersScreen());
      await tapKey(tester, 'users-add');
      expect(hints('user-password'), [AutofillHints.newPassword]);
      await tester.tapAt(const Offset(4, 4)); // dismiss the dialog
      await settle(tester);

      await pickMenu(tester, 'user-menu-u-student-1', 'user-action-password');
      expect(hints('user-new-password'), [AutofillHints.newPassword]);
    });

    testWidgets('starts with the role or status filter it was opened with',
        (tester) async {
      var api =
          await _pump(tester, const AdminUsersScreen(initialRole: 'student'));
      expect(api.adminCalls.single, 'GET /admin/users?role=student&status=all');
      expect(find.text('Aeliya'), findsOneWidget);
      expect(find.text('Tayyab'), findsNothing);

      api = await _pump(
          tester,
          const AdminUsersScreen(
              key: ValueKey('inactive'), initialStatus: 'inactive'));
      expect(api.adminCalls.single, 'GET /admin/users?status=inactive');
      expect(find.text('Sameer'), findsOneWidget);
      expect(find.text('Aeliya'), findsNothing);

      // Unknown values fall back to no filter.
      api = await _pump(
          tester,
          const AdminUsersScreen(
              key: ValueKey('bad'), initialRole: 'owner', initialStatus: 'x'));
      expect(api.adminCalls.single, 'GET /admin/users?status=all');
    });

    testWidgets('cannot deactivate, delete or re-role yourself',
        (tester) async {
      await _pump(tester, const AdminUsersScreen());
      await tapKey(tester, 'user-menu-u-admin-1');
      expect(
          tester
              .widget<PopupMenuItem<Object?>>(
                  find.byKey(const Key('user-action-delete')))
              .enabled,
          isFalse);
      expect(
          tester
              .widget<PopupMenuItem<Object?>>(
                  find.byKey(const Key('user-action-deactivate')))
              .enabled,
          isFalse);
      await tester.tap(find.byKey(const Key('user-action-edit')));
      await settle(tester);
      expect(find.text('You cannot change your own role'), findsOneWidget);
    });

    testWidgets('deactivates after confirming and shows LAST_ADMIN',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());

      await pickMenu(tester, 'user-menu-u-admin-2', 'user-action-deactivate');
      // Cancel first: nothing is sent.
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(api.adminCalls.where((c) => c.startsWith('PATCH')), isEmpty);

      api.failures['PATCH /api/v1/admin/users/u-admin-2'] = const Failure(
          409, 'LAST_ADMIN', 'At least one active admin account must remain');
      await pickMenu(tester, 'user-menu-u-admin-2', 'user-action-deactivate');
      await tapKey(tester, 'confirm-dialog-ok');
      expect(
          api.lastBody('PATCH', '/admin/users/u-admin-2'), {'isActive': false});
      expect(find.text('At least one active admin account must remain'),
          findsOneWidget);

      await pickMenu(tester, 'user-menu-u-teacher-1', 'user-action-deactivate');
      await tapKey(tester, 'confirm-dialog-ok');
      expect(api.lastBody('PATCH', '/admin/users/u-teacher-1'),
          {'isActive': false});
      expect(find.text('Account deactivated'), findsOneWidget);
      expect(
          tester
              .widget<StatusBadge>(
                  find.byKey(const Key('user-status-u-teacher-1')))
              .label,
          'Inactive');
    });

    testWidgets('activates an inactive account without confirmation',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-student-2', 'user-action-activate');
      expect(api.lastBody('PATCH', '/admin/users/u-student-2'),
          {'isActive': true});
      expect(find.text('Account activated'), findsOneWidget);
    });

    testWidgets('resets a password', (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());
      await pickMenu(tester, 'user-menu-u-student-1', 'user-action-password');
      await enterPassword(tester, 'user-new-password', 'short');
      await tapKey(tester, 'user-password-save');
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(api.adminCalls.where((c) => c.contains('/password')), isEmpty);

      await enterPassword(tester, 'user-new-password', 'brand-new-pass');
      await tapKey(tester, 'user-password-save');
      expect(api.lastBody('POST', '/admin/users/u-student-1/password'),
          {'password': 'brand-new-pass'});
      expect(find.text('Password updated for Aeliya'), findsOneWidget);
    });

    testWidgets('deletes after confirming and shows USER_IN_USE',
        (tester) async {
      final api = await _pump(tester, const AdminUsersScreen());

      api.failures['DELETE /api/v1/admin/users/u-teacher-1'] = const Failure(
          409, 'USER_IN_USE', 'This teacher still teaches CS 301');
      await pickMenu(tester, 'user-menu-u-teacher-1', 'user-action-delete');
      await tapKey(tester, 'confirm-dialog-ok');
      expect(api.adminCalls, contains('DELETE /admin/users/u-teacher-1'));
      expect(find.text('This teacher still teaches CS 301'), findsOneWidget);
      expect(find.text('Tayyab'), findsOneWidget);

      await pickMenu(tester, 'user-menu-u-student-1', 'user-action-delete');
      expect(find.textContaining('removes them from every course'),
          findsOneWidget);
      await tapKey(tester, 'confirm-dialog-ok');
      expect(api.adminCalls, contains('DELETE /admin/users/u-student-1'));
      expect(find.text('User deleted'), findsOneWidget);
      expect(find.text('Aeliya'), findsNothing);
    });
  });

  group('courses', () {
    testWidgets('each row menu is labelled with its course', (tester) async {
      await _pump(tester, const AdminCoursesScreen());
      expect(find.byTooltip('Actions'), findsNothing);
      expect(find.byTooltip('Actions for CS 301'), findsOneWidget);
    });

    testWidgets('lists courses with teacher and counts', (tester) async {
      final api = await _pump(tester, const AdminCoursesScreen());
      expect(api.adminCalls,
          containsAll(['GET /admin/courses', 'GET /admin/users?status=all']));
      expect(find.text('CS 301 · Human-Computer Interaction'), findsOneWidget);
      expect(find.text('Fall 2026 · Tayyab'), findsOneWidget);
      expect(find.text('1 student'), findsOneWidget);
      expect(find.text('2 assignments'), findsOneWidget);
    });

    testWidgets('creates a course with a teacher from the picker',
        (tester) async {
      final api = await _pump(tester, const AdminCoursesScreen(),
          setup: (api) => api.users.add({
                ...api.userById('u-teacher-1')!,
                'id': 'u-teacher-2',
                'displayName': 'Hina',
                'email': 'hina@example.edu',
                'phone': '',
              }));
      await tapKey(tester, 'courses-add');
      await tester.enterText(
          find.byKey(const Key('course-title')), 'Data Structures');
      await tester.enterText(find.byKey(const Key('course-code')), 'CS 210');
      await tester.enterText(
          find.byKey(const Key('course-term')), 'Spring 2027');
      await tapKey(tester, 'course-teacher');
      await tester.tap(find.text('Hina').last);
      await settle(tester);
      await tapKey(tester, 'course-save');

      expect(api.lastBody('POST', '/admin/courses'), {
        'title': 'Data Structures',
        'code': 'CS 210',
        'term': 'Spring 2027',
        'teacherId': 'u-teacher-2',
      });
      expect(find.text('Course created'), findsOneWidget);
      expect(find.text('CS 210 · Data Structures'), findsOneWidget);
    });

    testWidgets('edits a course and shows INVALID_TEACHER', (tester) async {
      final api = await _pump(tester, const AdminCoursesScreen());
      api.failures['PATCH /api/v1/admin/courses/c-001'] =
          const Failure(400, 'INVALID_TEACHER', 'Pick an existing teacher');
      await pickMenu(tester, 'course-menu-c-001', 'course-action-edit');
      await tester.enterText(find.byKey(const Key('course-term')), 'Fall 2027');
      await tapKey(tester, 'course-save');
      expect(find.text('Pick an existing teacher'), findsOneWidget);

      await tapKey(tester, 'course-save');
      expect(
          api.lastBody('PATCH', '/admin/courses/c-001'), {'term': 'Fall 2027'});
      expect(find.text('Course updated'), findsOneWidget);
    });

    testWidgets('replaces the roster with the selected students',
        (tester) async {
      final api = await _pump(tester, const AdminCoursesScreen());
      await pickMenu(tester, 'course-menu-c-001', 'course-action-roster');
      expect(find.text('1 selected'), findsOneWidget);
      // Only students are offered.
      expect(find.byKey(const Key('roster-student-u-teacher-1')), findsNothing);

      await tapKey(tester, 'roster-student-u-student-2');
      await tapKey(tester, 'roster-student-u-student-1');
      expect(find.text('1 selected'), findsOneWidget);
      await tapKey(tester, 'roster-save');

      expect(api.lastBody('PUT', '/admin/courses/c-001/students'), {
        'studentIds': ['u-student-2'],
      });
      expect(find.text('Roster saved'), findsOneWidget);
    });

    testWidgets('deletes a course after confirming', (tester) async {
      final api = await _pump(tester, const AdminCoursesScreen());
      await pickMenu(tester, 'course-menu-c-001', 'course-action-delete');
      expect(find.textContaining('assignments, submissions'), findsOneWidget);
      await tapKey(tester, 'confirm-dialog-ok');
      expect(api.adminCalls, contains('DELETE /admin/courses/c-001'));
      expect(find.text('No courses yet'), findsOneWidget);
    });
  });

  group('integrity', () {
    testWidgets('lists reports newest first and filters flagged only',
        (tester) async {
      final api = await _pump(tester, const AdminIntegrityScreen());
      expect(api.adminCalls.last, 'GET /admin/integrity?flagged=false');
      expect(find.text('large paste'), findsOneWidget);
      expect(find.text('No flags'), findsOneWidget);
      final sameer = tester.getTopLeft(find.text('Sameer')).dy;
      final aeliya = tester.getTopLeft(find.text('Aeliya')).dy;
      expect(sameer, lessThan(aeliya), reason: 'newest computedAt first');

      await tester.tap(find.descendant(
          of: find.byKey(const Key('integrity-filter')),
          matching: find.text('Flagged only')));
      await settle(tester);
      expect(api.adminCalls.last, 'GET /admin/integrity?flagged=true');
      expect(find.text('Aeliya'), findsOneWidget);
      expect(find.text('Sameer'), findsNothing);
    });
  });

  group('import/export', () {
    testWidgets('exports through the shared CSV dialog', (tester) async {
      final api = await _pump(tester, const AdminImportExportScreen());
      expect(api.adminCalls, ['GET /admin/courses']);
      await tapKey(tester, 'import-export-students');
      expect(find.byKey(const Key('export-preview')), findsOneWidget);
      expect(api.requests.last.url.path, '/api/v1/excel/export/students');
    });

    testWidgets('opens the shared student import form', (tester) async {
      await _pump(tester, const AdminImportExportScreen());
      await tapKey(tester, 'import-export-import');
      expect(find.byKey(const Key('import-csv')), findsOneWidget);
      expect(find.text('CS 301 · Human-Computer Interaction'), findsWidgets);
    });
  });

  group('reused main-app screens render for an admin against the API', () {
    final screens = <String, Widget Function()>{
      'departments': () => const DepartmentsScreen(),
      'calendar': () => const CalendarScreen(),
      'attendance': () => const AttendanceScreen(),
      'notes': () => const NotesScreen(),
    };
    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        final api = await _pump(tester, entry.value());
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorState), findsNothing);
        expect(api.requests, isNotEmpty);
      });
    }
  });
}
