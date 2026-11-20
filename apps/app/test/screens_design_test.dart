import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/attendance_screen.dart';
import 'package:edtech_app/screens/courses_screen.dart';
import 'package:edtech_app/screens/dashboard_screen.dart';
import 'package:edtech_app/screens/integrity_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/offline_store.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders every screen built from the Sleek designs against the bundled demo
/// store, so a layout regression fails the suite instead of shipping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthProvider auth;

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: Scaffold(body: screen),
        ),
      ),
    );
    // Let the screen's initial load resolve. Deliberately not pumpAndSettle:
    // the skeleton shimmer animates forever.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }

  testWidgets('all four designed screens render', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    auth = AuthProvider();
    await auth.init();

    await pumpScreen(tester, const DashboardScreen());
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Due this week'), findsOneWidget);

    await pumpScreen(tester, const CoursesScreen());
    expect(find.text('My Courses'), findsOneWidget);

    await pumpScreen(tester, const AttendanceScreen());
    expect(find.textContaining('Attendance'), findsOneWidget);
    expect(find.text('Class entries'), findsOneWidget);
    expect(find.text('Request excuse'), findsOneWidget);

    // No telemetry has been captured yet, so the empty state shows.
    // The key forces a fresh element: without it the second `pumpScreen` below
    // would hand back the identical const widget and Flutter would reuse the
    // mounted state, skipping `initState`/`_load()` entirely.
    await pumpScreen(tester, const IntegrityScreen(key: ValueKey('integrity-empty')));
    expect(find.text('Integrity'), findsOneWidget);
    expect(find.text('No writing sessions yet'), findsOneWidget);
    expect(find.text('Ask teacher to review'), findsNothing);

    // Capture a report the way the store would once the extension records one.
    final api = ApiService.instance;
    final courses = await api.getCourses();
    final assignments = await api.getAssignments(courses.first.id);
    await OfflineStore.instance.setIntegrityReport(<String, dynamic>{
      'submissionId': 'sub-demo',
      'assignmentId': assignments.first.id,
      'studentId': 'u-student-1',
      'effortScore': <String, dynamic>{
        'sessionId': 'ses-demo',
        'assignmentId': assignments.first.id,
        'studentId': 'u-student-1',
        'score': 82,
        'keystrokes': 4210,
        'pastes': 2,
        'pasteVolume': 340,
        'aiTabSwitches': 3,
        'activeSeconds': 7800,
        'computedAt': '2026-06-11T18:20:00.000Z',
      },
      'flags': <String>['paste_over_150_words'],
      'replayAvailable': false,
      'generatedAt': '2026-06-11T18:20:00.000Z',
    });

    await pumpScreen(tester, const IntegrityScreen());
    // The report page is taller than the viewport and the ListView builds
    // lazily, so the session/flag sections sit below the fold and are not
    // mounted yet. Scroll them into view before asserting on them — but not so
    // far that the score ring caption scrolls out of the cache window.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('of 100 · Strong'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.textContaining('keystrokes typed over'), findsOneWidget);
    expect(find.text('Flagged'), findsOneWidget);
    expect(find.text('Ask teacher to review'), findsOneWidget);
  });
}
