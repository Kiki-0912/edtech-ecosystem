import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/courses/assignment_screen.dart';
import 'package:edtech_app/screens/courses/course_detail_screen.dart';
import 'package:edtech_app/screens/courses/courses_screen.dart';
import 'package:edtech_app/screens/integrity/integrity_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/offline_store.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'layout_matrix_test.dart' show signedIn;

Future<void> pump(WidgetTester tester, AuthProvider auth, Widget screen,
    {Size size = const Size(1280, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance),
    ],
    child: MaterialApp(theme: lightTheme, home: Scaffold(body: screen)),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUp(() => ApiService.instance.offlineMode = true);

  testWidgets('courses lists the student\'s courses and filters by search',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const CoursesScreen());

    expect(find.byKey(const Key('course-c-cs301')), findsOneWidget);
    expect(find.text('Human-Computer Interaction'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('courses-search')), 'data struct');
    await settle(tester);
    expect(find.text('Human-Computer Interaction'), findsNothing);
    expect(find.text('Data Structures'), findsOneWidget);
  });

  testWidgets('course detail shows assignments and enrolled people',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(tester, auth, const CourseDetailScreen(courseId: 'c-cs301'));

    expect(find.text('Human-Computer Interaction'), findsOneWidget);
    expect(find.byKey(const Key('assignment-a1')), findsOneWidget);
    expect(find.text('Aeliya'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student submits a link and the status updates', (tester) async {
    addTearDown(tester.view.reset);
    // a2 has no seeded submission for u-student-1.
    final student = await signedIn('student');
    await pump(tester, student,
        const AssignmentScreen(courseId: 'c-cs301', assignmentId: 'a2'));

    expect(find.text('Usability Study Report'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);

    // Invalid link is rejected.
    await tester.enterText(
        find.byKey(const Key('submission-link')), 'not a url');
    await tester.tap(find.byKey(const Key('submission-submit')));
    await settle(tester);
    expect(find.textContaining('Paste a full link'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('submission-link')),
        'https://docs.example.com/report');
    await tester.tap(find.byKey(const Key('submission-submit')));
    await settle(tester);

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Resubmit'), findsOneWidget);
  });

  testWidgets('teacher sees the roster derived from real submissions',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(tester, auth,
        const AssignmentScreen(courseId: 'c-cs301', assignmentId: 'a1'));

    // Seeded: Aeliya + Sameer submitted a1, Saifi has not.
    expect(find.text('2 of 3 handed in'), findsOneWidget);
    expect(find.byKey(const Key('roster-u-student-3')), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
  });

  testWidgets('integrity: empty state, then a captured report', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth,
        const IntegrityScreen(key: ValueKey('empty'), assignmentId: 'a2'));
    expect(find.text('No writing sessions yet'), findsOneWidget);
    expect(find.text('Ask teacher to review'), findsOneWidget);

    await OfflineStore.instance.setIntegrityReport(<String, dynamic>{
      'submissionId': 'sub-demo',
      'assignmentId': 'a2',
      'studentId': 'u-student-1',
      'effortScore': <String, dynamic>{
        'sessionId': 'ses-demo',
        'assignmentId': 'a2',
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

    await pump(tester, auth,
        const IntegrityScreen(key: ValueKey('report'), assignmentId: 'a2'));
    expect(find.text('of 100 · Strong'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.textContaining('keystrokes typed over'), findsOneWidget);
    expect(find.text('Flagged'), findsOneWidget);
    expect(find.text('paste over 150 words'), findsOneWidget);
  });

  testWidgets('teacher integrity starts on the class overview', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(tester, auth, const IntegrityScreen(assignmentId: 'a1'));

    expect(find.text('Class overview'), findsOneWidget);
    expect(find.text('Effort 79'), findsOneWidget);
    await tester.tap(find.byKey(const Key('integrity-student-u-student-3')));
    await settle(tester);
    expect(find.byKey(const Key('integrity-back-roster')), findsOneWidget);
    expect(find.text('No writing sessions yet'), findsOneWidget);
  });
}
