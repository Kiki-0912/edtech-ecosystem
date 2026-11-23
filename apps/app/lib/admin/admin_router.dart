import 'package:edtech_app/admin/admin_access.dart';
import 'package:edtech_app/admin/admin_destinations.dart';
import 'package:edtech_app/admin/admin_login_screen.dart';
import 'package:edtech_app/admin/admin_shell.dart';
import 'package:edtech_app/admin/screens/courses_screen.dart';
import 'package:edtech_app/admin/screens/import_export_screen.dart';
import 'package:edtech_app/admin/screens/integrity_screen.dart';
import 'package:edtech_app/admin/screens/overview_screen.dart';
import 'package:edtech_app/admin/screens/users_screen.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/attendance/attendance_mark_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_screen.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/departments/departments_screen.dart';
import 'package:edtech_app/screens/notes/notes_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const _loginPath = '/login';

StatefulShellBranch _branch(
        AdminDestination dest, Widget Function(GoRouterState state) build,
        {List<RouteBase> routes = const []}) =>
    StatefulShellBranch(routes: [
      GoRoute(
        path: dest.path,
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: build(state)),
        routes: routes,
      ),
    ]);

/// Builds the admin console router. Every route except /login requires a
/// signed-in admin; anything else is sent to /login. Re-evaluated whenever
/// [auth] changes, so sign-in and sign-out navigate automatically.
GoRouter buildAdminRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: adminOverview.path,
    refreshListenable: auth,
    redirect: (context, state) {
      final onLogin = state.matchedLocation == _loginPath;
      if (!isAdminSession(auth)) return onLogin ? null : _loginPath;
      if (onLogin) return adminOverview.path;
      return null;
    },
    routes: [
      GoRoute(
        path: _loginPath,
        builder: (_, __) => const AdminLoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        // IndexedStack keeps visited branches alive; disable heroes so their
        // widgets never collide on shell ⇄ login transitions.
        builder: (context, state, shell) =>
            HeroMode(enabled: false, child: AdminShell(navigationShell: shell)),
        // Order must match kAdminDestinations.
        branches: [
          _branch(adminOverview, (_) => const AdminOverviewScreen()),
          // `/users?role=student`, `/users?status=inactive`: starting filters.
          _branch(
              adminUsers,
              (state) => AdminUsersScreen(
                    initialRole: state.uri.queryParameters['role'],
                    initialStatus: state.uri.queryParameters['status'],
                  )),
          _branch(adminCourses, (_) => const AdminCoursesScreen()),
          // The shared screens below are reused as-is: they only need the
          // AuthProvider and a Scaffold, which the admin shell provides.
          _branch(adminDepartments, (_) => const DepartmentsScreen()),
          _branch(adminCalendar, (_) => const CalendarScreen()),
          _branch(adminAttendance, (_) => const AttendanceScreen(), routes: [
            GoRoute(
              path: 'mark',
              builder: (_, state) => AttendanceMarkScreen(
                key: ValueKey(state.uri.queryParameters['course']),
                initialCourseId: state.uri.queryParameters['course'],
              ),
            ),
          ]),
          _branch(adminNotes, (_) => const NotesScreen()),
          _branch(adminImportExport, (_) => const AdminImportExportScreen()),
          _branch(adminIntegrity, (_) => const AdminIntegrityScreen()),
        ],
      ),
    ],
  );
}
