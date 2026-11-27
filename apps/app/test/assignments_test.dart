import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/courses/assignment_screen.dart';
import 'package:edtech_app/screens/courses/course_detail_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/offline_store.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'layout_matrix_test.dart' show signedIn;
import 'offline_parity_test.dart' show apiError, call;

/// Pumps a router with the course, assignment and calendar pages, so the
/// screens' `context.go` navigation works, starting at [location].
Future<GoRouter> pumpAt(
    WidgetTester tester, AuthProvider auth, String location) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/courses',
        builder: (_, __) => const Scaffold(body: Text('All courses page')),
        routes: [
          GoRoute(
            path: ':courseId',
            builder: (_, state) => Scaffold(
              body: CourseDetailScreen(
                key: ValueKey(state.pathParameters['courseId']),
                courseId: state.pathParameters['courseId']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'assignments/:assignmentId',
                builder: (_, state) => Scaffold(
                  body: AssignmentScreen(
                    key: ValueKey(state.pathParameters['assignmentId']),
                    courseId: state.pathParameters['courseId']!,
                    assignmentId: state.pathParameters['assignmentId']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/calendar',
        builder: (_, __) => const Scaffold(body: CalendarScreen()),
      ),
    ],
  );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance),
    ],
    child: MaterialApp.router(theme: lightTheme, routerConfig: router),
  ));
  await settle(tester);
  return router;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Selects [day] in the calendar grid, paging forward a month if needed.
Future<void> selectDay(WidgetTester tester, DateTime day) async {
  final key = Key('day-${day.year}-${day.month}-${day.day}');
  if (find.byKey(key).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('calendar-next')));
    await settle(tester);
  }
  await tester.tap(find.byKey(key).first);
  await settle(tester);
}

Future<Map<String, dynamic>> deadlineOf(String assignmentId) async =>
    (await OfflineStore.instance.getCalendarEvents())
        .firstWhere((e) => e['assignmentId'] == assignmentId);

Future<bool> hasDeadline(String assignmentId) async =>
    (await OfflineStore.instance.getCalendarEvents())
        .any((e) => e['assignmentId'] == assignmentId);

void main() {
  final api = ApiService.instance;
  setUp(() => api.offlineMode = true);

  group('offline assignment routes match the API contract', () {
    test('create: permissions, validation and the calendar deadline', () async {
      await signedIn('teacher');
      final due = DateTime.utc(2026, 12, 20, 9);
      final (status, body) =
          await call('POST', '/courses/c-cs301/assignments', body: {
        'title': '  Persona research  ',
        'brief': 'Interview two users.',
        'dueAt': due.toIso8601String(),
      });
      expect(status, 201);
      final created = body['data'] as Map<String, dynamic>;
      expect(created['title'], 'Persona research');
      expect(created['status'], 'open', reason: 'status defaults to open');
      final event = await deadlineOf(created['id'] as String);
      expect(event['title'], 'Persona research due');
      expect(event['kind'], 'assignment');
      expect(event['courseId'], 'c-cs301');
      expect(event['endsAt'], isNull);
      expect(DateTime.parse(event['startsAt'] as String), due);

      // u-teacher-1 does not teach CS 210.
      expect(
          (await call('POST', '/courses/c-cs210/assignments', body: {
            'title': 'Nope',
            'dueAt': due.toIso8601String(),
          }))
              .$1,
          403);
      expect(
          (await call('POST', '/courses/c-nope/assignments', body: {
            'title': 'Nope',
            'dueAt': due.toIso8601String(),
          }))
              .$2['error']['code'],
          'COURSE_NOT_FOUND');
      for (final invalid in <Map<String, dynamic>>[
        {'title': '', 'dueAt': due.toIso8601String()},
        {'title': 'x' * 201, 'dueAt': due.toIso8601String()},
        {'title': 'No date'},
        {'title': 'Bad date', 'dueAt': 'tomorrow'},
        {'title': 'Bad status', 'dueAt': due.toIso8601String(), 'status': 'x'},
        {'title': 'Long', 'dueAt': due.toIso8601String(), 'brief': 'b' * 10001},
      ]) {
        final (code, error) =
            await call('POST', '/courses/c-cs301/assignments', body: invalid);
        expect(code, 400, reason: '$invalid');
        expect(error['error']['code'], 'INVALID_BODY');
      }

      await signedIn('student');
      await expectLater(
          api.createAssignment(
              courseId: 'c-cs301', title: 'Mine', dueAt: DateTime.now()),
          apiError(403, 'FORBIDDEN'));
      await expectLater(api.updateAssignment('a1', title: 'Hacked'),
          apiError(403, 'FORBIDDEN'));
      await expectLater(api.deleteAssignment('a1'), apiError(403, 'FORBIDDEN'));
      // The role check comes first, like the API: no 404 probing.
      expect(
          (await call('PATCH', '/assignments/nope', body: {'title': 'x'})).$1,
          403);
      expect(
          (await call('POST', '/courses/c-nope/assignments', body: {
            'title': 'x',
            'dueAt': due.toIso8601String(),
          }))
              .$1,
          403);
    });

    test('update keeps the deadline in sync; drafts own none', () async {
      await signedIn('admin');
      final a = await api.createAssignment(
          courseId: 'c-cs210',
          title: 'Heaps',
          dueAt: DateTime(2026, 12, 1, 10),
          status: 'draft');
      expect(await hasDeadline(a.id), isFalse);

      final opened = await api.updateAssignment(a.id,
          status: 'open', title: 'Heaps & priority queues');
      expect(opened.status, 'open');
      expect((await deadlineOf(a.id))['title'], 'Heaps & priority queues due');

      final moved = DateTime(2026, 12, 3, 14, 30);
      await api.updateAssignment(a.id, dueAt: moved);
      expect(
          DateTime.parse((await deadlineOf(a.id))['startsAt'] as String)
              .toLocal(),
          moved);
      expect(
          (await OfflineStore.instance.getCalendarEvents())
              .where((e) => e['assignmentId'] == a.id),
          hasLength(1));

      await expectLater(api.updateAssignment('nope', title: 'x'),
          apiError(404, 'ASSIGNMENT_NOT_FOUND'));
      expect(
          (await call('PATCH', '/assignments/${a.id}', body: {'title': ' '}))
              .$2['error']['code'],
          'INVALID_BODY');

      expect((await call('PATCH', '/assignments/${a.id}', body: {})).$1, 400,
          reason: 'an update needs at least one field');
      await api.updateAssignment(a.id, status: 'draft');
      expect(await hasDeadline(a.id), isFalse);
    });

    test('linked calendar events cannot be edited or deleted', () async {
      await signedIn('teacher');
      final a = await api.createAssignment(
          courseId: 'c-cs301', title: 'Locked', dueAt: DateTime(2026, 12, 9));
      final event = await deadlineOf(a.id);
      final id = event['id'] as String;
      final (putStatus, putBody) = await call('PUT', '/calendar/$id',
          body: {'title': 'Moved', 'kind': 'assignment'});
      expect(putStatus, 409);
      expect(putBody['error']['code'], 'ASSIGNMENT_EVENT');
      await expectLater(
          api.deleteCalendarEvent(id), apiError(409, 'ASSIGNMENT_EVENT'));
      // The model carries the link; plain events parse with null.
      final events = await api.getCalendar(null);
      expect(events.firstWhere((e) => e.id == id).assignmentId, a.id);
      expect(events.firstWhere((e) => e.id == 'ev1').assignmentId, isNull);
    });

    test('students never see drafts; closed rejects submissions', () async {
      await signedIn('teacher');
      final draft = await api.createAssignment(
          courseId: 'c-cs301',
          title: 'Secret draft',
          dueAt: DateTime(2026, 12, 12),
          status: 'draft');
      final closed = await api.createAssignment(
          courseId: 'c-cs301',
          title: 'Already closed',
          dueAt: DateTime(2026, 12, 12),
          status: 'closed');
      expect((await api.getAssignments('c-cs301')).map((a) => a.id),
          contains(draft.id));

      await signedIn('student');
      expect((await api.getAssignments('c-cs301')).map((a) => a.id),
          isNot(contains(draft.id)));
      final (_, detail) = await call('GET', '/courses/c-cs301');
      expect((detail['data']['assignments'] as List).map((a) => a['id']),
          isNot(contains(draft.id)));
      await expectLater(
          api.getAssignment(draft.id), apiError(404, 'ASSIGNMENT_NOT_FOUND'));
      await expectLater(
          api.submitAssignment(
              assignmentId: draft.id, studentId: 'u-student-1'),
          apiError(409, 'ASSIGNMENT_DRAFT'));
      expect((await api.getAssignment(closed.id)).isClosed, isTrue);
      await expectLater(
          api.submitAssignment(
              assignmentId: closed.id, studentId: 'u-student-1'),
          apiError(409, 'ASSIGNMENT_CLOSED'));
    });

    test('delete removes submissions and the deadline', () async {
      await signedIn('teacher');
      final a = await api.createAssignment(
          courseId: 'c-cs301', title: 'Short-lived', dueAt: DateTime(2026, 12));
      await signedIn('student');
      await api.submitAssignment(assignmentId: a.id, studentId: 'u-student-1');
      await signedIn('teacher');
      await api.deleteAssignment(a.id);
      expect(await hasDeadline(a.id), isFalse);
      expect(
          (await OfflineStore.instance.getSubmissions())
              .where((s) => s['assignmentId'] == a.id),
          isEmpty);
      await expectLater(
          api.getAssignment(a.id), apiError(404, 'ASSIGNMENT_NOT_FOUND'));
    });
  });

  testWidgets(
      'teacher creates an assignment; it shows on the course and '
      'in the calendar, read-only', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    final router = await pumpAt(tester, auth, '/courses/c-cs301');

    await tester.tap(find.byKey(const Key('assignment-create')));
    await settle(tester);
    // Title is required.
    await tester.tap(find.byKey(const Key('assignment-save')));
    await settle(tester);
    expect(find.text('Give the assignment a title'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('assignment-title')), 'Card sorting study');
    await tester.enterText(find.byKey(const Key('assignment-brief')),
        'Run an open card sort with five participants.');
    await tester.tap(find.byKey(const Key('assignment-save')));
    await settle(tester);

    expect(find.text('Assignment created'), findsOneWidget);
    expect(find.text('Card sorting study'), findsOneWidget);
    final created = (await api.getAssignments('c-cs301'))
        .firstWhere((a) => a.title == 'Card sorting study');
    expect(created.status, 'open');
    expect(find.byKey(Key('assignment-${created.id}')), findsOneWidget);

    // A draft gets a Draft badge for the teacher.
    await tester.tap(find.byKey(const Key('assignment-create')));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('assignment-title')), 'Draft diary study');
    await tester.tap(find.byKey(const Key('assignment-status')));
    await settle(tester);
    await tester.tap(find.text('Draft').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('assignment-save')));
    await settle(tester);
    final draft = (await api.getAssignments('c-cs301'))
        .firstWhere((a) => a.title == 'Draft diary study');
    expect(draft.status, 'draft');
    expect(
        find.descendant(
            of: find.byKey(Key('assignment-${draft.id}')),
            matching: find.text('Draft')),
        findsOneWidget);
    expect(await hasDeadline(draft.id), isFalse);

    // The deadline is on the calendar, read-only, with a link back.
    router.go('/calendar');
    await settle(tester);
    await selectDay(tester, created.dueAt);
    expect(find.text('Card sorting study due'), findsOneWidget);
    expect(find.text('Draft diary study due'), findsNothing);
    await tester.tap(find.text('Card sorting study due'));
    await settle(tester);
    expect(find.byKey(const Key('event-title')), findsNothing,
        reason: 'linked events never open the editor');
    expect(find.byKey(const Key('event-delete')), findsNothing);
    expect(find.byKey(const Key('event-linked-note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-open-assignment')));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/courses/c-cs301/assignments/${created.id}');
    expect(find.byKey(const Key('assignment-edit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher edits, re-statuses and deletes an assignment',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    final a = await api.createAssignment(
        courseId: 'c-cs301',
        title: 'Wireframes',
        brief: 'Low fidelity.',
        dueAt: DateTime.now().add(const Duration(days: 4)));
    final router =
        await pumpAt(tester, auth, '/courses/c-cs301/assignments/${a.id}');

    expect(find.text('Low fidelity.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assignment-edit')));
    await settle(tester);
    // Prefilled.
    expect(find.text('Wireframes'), findsWidgets);
    await tester.enterText(
        find.byKey(const Key('assignment-title')), 'Wireframes v2');
    await tester.enterText(
        find.byKey(const Key('assignment-brief')), 'Mid fidelity now.');
    await tester.tap(find.byKey(const Key('assignment-save')));
    await settle(tester);
    expect(find.text('Assignment updated'), findsOneWidget);
    expect(find.text('Wireframes v2'), findsOneWidget);
    expect(find.text('Mid fidelity now.'), findsOneWidget);
    expect((await deadlineOf(a.id))['title'], 'Wireframes v2 due');

    // Quick status change.
    await tester.tap(find.byKey(const Key('assignment-set-closed')));
    await settle(tester);
    expect((await api.getAssignment(a.id)).status, 'closed');
    expect(find.text('Visible, no longer accepting work'), findsOneWidget);

    // Delete asks first; cancelling keeps it.
    await tester.tap(find.byKey(const Key('assignment-delete')));
    await settle(tester);
    expect(find.text('Delete assignment?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect((await api.getAssignment(a.id)).id, a.id);

    await tester.tap(find.byKey(const Key('assignment-delete')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path,
        '/courses/c-cs301');
    expect(find.byKey(Key('assignment-${a.id}')), findsNothing);
    expect(await hasDeadline(a.id), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('students see no drafts and no management controls',
      (tester) async {
    addTearDown(tester.view.reset);
    await signedIn('teacher');
    final draft = await api.createAssignment(
        courseId: 'c-cs301',
        title: 'Hidden draft',
        dueAt: DateTime.now().add(const Duration(days: 2)),
        status: 'draft');

    final student = await signedIn('student');
    final router = await pumpAt(tester, student, '/courses/c-cs301');
    expect(find.byKey(const Key('assignment-create')), findsNothing);
    expect(find.text('Hidden draft'), findsNothing);
    expect(find.byKey(const Key('assignment-a2')), findsOneWidget);

    router.go('/courses/c-cs301/assignments/a2');
    await settle(tester);
    expect(find.text('Usability Study Report'), findsOneWidget);
    expect(find.byKey(const Key('submission-link')), findsOneWidget);
    for (final key in [
      'assignment-edit',
      'assignment-delete',
      'assignment-status-quick'
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }

    // A draft's page is not found for a student.
    router.go('/courses/c-cs301/assignments/${draft.id}');
    await settle(tester);
    expect(find.text('Hidden draft'), findsNothing);
    expect(find.text('Assignment not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'submitting to an assignment closed meanwhile shows the closed '
      'state', (tester) async {
    addTearDown(tester.view.reset);
    await signedIn('teacher');
    final a = await api.createAssignment(
        courseId: 'c-cs301',
        title: 'Closing soon',
        dueAt: DateTime.now().add(const Duration(days: 1)));

    final student = await signedIn('student');
    await pumpAt(tester, student, '/courses/c-cs301/assignments/${a.id}');
    expect(find.byKey(const Key('assignment-closed')), findsNothing);

    // The teacher closes it while the student has the page open.
    await OfflineStore.instance.updateAssignment(a.id, status: 'closed');

    await tester.enterText(find.byKey(const Key('submission-link')),
        'https://docs.example.com/late');
    await tester.tap(find.byKey(const Key('submission-submit')));
    await settle(tester);
    expect(find.text('Assignment is closed for submissions'), findsOneWidget);
    expect(find.byKey(const Key('assignment-closed')), findsOneWidget);
    expect(find.text('This assignment is closed'), findsOneWidget);
    expect(find.byKey(const Key('submission-link')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('another teacher\'s course shows no create button',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    // CS 210 is taught by u-teacher-2, not the signed-in u-teacher-1.
    await pumpAt(tester, auth, '/courses/c-cs210');
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.byKey(const Key('assignment-create')), findsNothing);

    final admin = await signedIn('admin');
    await pumpAt(tester, admin, '/courses/c-cs210');
    expect(find.byKey(const Key('assignment-create')), findsOneWidget);
  });
}
