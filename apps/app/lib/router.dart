import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/login_screen.dart';
import 'package:edtech_app/auth/signup_screen.dart';
import 'package:edtech_app/auth/verify_sms_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_mark_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_screen.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/chat/chat_screen.dart';
import 'package:edtech_app/screens/courses/assignment_screen.dart';
import 'package:edtech_app/screens/courses/course_detail_screen.dart';
import 'package:edtech_app/screens/courses/courses_screen.dart';
import 'package:edtech_app/screens/departments/departments_screen.dart';
import 'package:edtech_app/screens/home/home_screen.dart';
import 'package:edtech_app/screens/integrity/integrity_screen.dart';
import 'package:edtech_app/screens/notes/notes_screen.dart';
import 'package:edtech_app/screens/profile/profile_screen.dart';
import 'package:edtech_app/screens/students/students_screen.dart';
import 'package:edtech_app/shell/app_shell.dart';
import 'package:edtech_app/shell/destinations.dart' as d;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

const _authPaths = {'/login', '/signup', '/verify-sms'};

GoRoute _tab(
  d.AppDestination dest,
  Widget Function() build, {
  List<RouteBase> routes = const [],
}) =>
    GoRoute(
      path: dest.path,
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: build()),
      routes: routes,
    );

/// Builds the app router. Re-evaluates redirects whenever [auth] changes, so
/// sign-in / sign-up / SMS verify / sign-out navigate automatically.
GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final onAuthPage = _authPaths.contains(location);

      if (!auth.isAuthenticated) return onAuthPage ? null : '/login';
      if (onAuthPage) return '/';
      if (!d.canAccess(auth.user?.role, location)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/verify-sms', builder: (_, __) => const VerifySmsScreen()),
      StatefulShellRoute.indexedStack(
        // IndexedStack keeps every visited branch alive; their FABs would
        // share the default hero tag and collide on shell ⇄ login transitions.
        builder: (context, state, shell) =>
            HeroMode(enabled: false, child: AppShell(navigationShell: shell)),
        // Order must match d.kDestinations.
        branches: [
          StatefulShellBranch(routes: [_tab(d.home, () => const HomeScreen())]),
          StatefulShellBranch(
            routes: [
              _tab(
                d.courses,
                () => const CoursesScreen(),
                routes: [
                  GoRoute(
                    path: ':courseId',
                    builder: (_, state) => CourseDetailScreen(
                      key: ValueKey(state.pathParameters['courseId']),
                      courseId: state.pathParameters['courseId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'assignments/:assignmentId',
                        builder: (_, state) => AssignmentScreen(
                          key: ValueKey(state.pathParameters['assignmentId']),
                          courseId: state.pathParameters['courseId']!,
                          assignmentId: state.pathParameters['assignmentId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [_tab(d.calendar, () => const CalendarScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: d.chat.path,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: ChatScreen(
                    initialCourseId: state.uri.queryParameters['course'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: d.integrity.path,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: IntegrityScreen(
                    assignmentId: state.uri.queryParameters['assignment'],
                    studentId: state.uri.queryParameters['student'],
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _tab(
                d.attendance,
                () => const AttendanceScreen(),
                routes: [
                  GoRoute(
                    path: 'mark',
                    builder: (_, state) => AttendanceMarkScreen(
                      key: ValueKey(state.uri.queryParameters['course']),
                      initialCourseId: state.uri.queryParameters['course'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [_tab(d.students, () => const StudentsScreen())],
          ),
          StatefulShellBranch(
            routes: [_tab(d.departments, () => const DepartmentsScreen())],
          ),
          StatefulShellBranch(
            routes: [_tab(d.notes, () => const NotesScreen())],
          ),
          StatefulShellBranch(
            routes: [_tab(d.profile, () => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
}
