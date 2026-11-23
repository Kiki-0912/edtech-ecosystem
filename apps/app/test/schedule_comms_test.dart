import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/calendar/calendar_screen.dart';
import 'package:edtech_app/screens/chat/chat_screen.dart';
import 'package:edtech_app/services/api_service.dart';
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

  testWidgets('students can view the calendar but not edit it', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const CalendarScreen());

    expect(find.byKey(const Key('calendar-add')), findsNothing);
    expect(find.byKey(const Key('calendar-next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher creates, edits and deletes an event', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(tester, auth, const CalendarScreen());

    // Teachers can edit (previously admin-only, although the API allows it).
    await tester.tap(find.byKey(const Key('calendar-add')));
    await settle(tester);
    // Campus-wide events are admin-only, so a teacher's event gets one of
    // their courses (no "Campus-wide" choice), and they can edit it later.
    expect(find.byKey(const Key('event-course')), findsOneWidget);
    expect(find.text('Campus-wide'), findsNothing);
    await tester.enterText(find.byKey(const Key('event-title')), 'Lab review');
    await tester.tap(find.byKey(const Key('event-add-end')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('event-save')));
    await settle(tester);

    expect(find.text('Event added'), findsOneWidget);
    expect(find.text('Lab review'), findsOneWidget);

    await tester.tap(find.text('Lab review'));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('event-title')), 'Lab review (moved)');
    await tester.tap(find.byKey(const Key('event-save')));
    await settle(tester);
    expect(find.text('Event updated'), findsOneWidget);
    expect(find.text('Lab review (moved)'), findsOneWidget);

    // Their own course's event (HCI Quiz 1, CS 301, seeded 3 days out).
    final now = DateTime.now();
    final quizDay = DateTime(now.year, now.month, now.day + 3);
    if (quizDay.month != now.month) {
      await tester.tap(find.byKey(const Key('calendar-next')));
      await settle(tester);
    }
    await tester.tap(
        find.byKey(Key('day-${quizDay.year}-${quizDay.month}-${quizDay.day}')));
    await settle(tester);
    await tester.tap(find.text('HCI Quiz 1'));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('event-title')), 'HCI Quiz 1 (moved)');
    await tester.tap(find.byKey(const Key('event-save')));
    await settle(tester);
    expect(find.text('HCI Quiz 1 (moved)'), findsOneWidget);

    // Delete requires confirmation.
    await tester.tap(find.text('HCI Quiz 1 (moved)'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('event-delete')));
    await settle(tester);
    expect(find.text('Delete event?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('HCI Quiz 1 (moved)'), findsNothing);
  });

  testWidgets('admins may add campus-wide events', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('admin');
    await pump(tester, auth, const CalendarScreen());
    await tester.tap(find.byKey(const Key('calendar-add')));
    await settle(tester);
    expect(find.text('Campus-wide'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-title')), 'Open day');
    await tester.tap(find.byKey(const Key('event-save')));
    await settle(tester);
    expect(find.text('Event added'), findsOneWidget);
    expect(find.text('Open day'), findsOneWidget);
  });

  testWidgets('empty day shows an empty state instead of every event',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const CalendarScreen());
    // Jump far ahead to a month with no seeded events.
    for (var i = 0; i < 24; i++) {
      await tester.tap(find.byKey(const Key('calendar-next')));
    }
    await settle(tester);
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + 24, 15);
    await tester.tap(find.byKey(Key('day-${target.year}-${target.month}-15')));
    await settle(tester);
    expect(find.text('Clear on this date'), findsOneWidget);
  });

  testWidgets('student sends a chat message', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const ChatScreen(), size: const Size(390, 844));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Hello world');
    await tester.tap(find.byKey(const Key('chat-send')));
    await settle(tester);
    expect(find.text('Hello world'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('students cannot post in announcements', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const ChatScreen());

    await tester.tap(find.byKey(const Key('channel-ch-announce')));
    await settle(tester);
    expect(find.byKey(const Key('chat-input')), findsNothing);
    expect(find.text('Only teachers and admins can post announcements.'),
        findsOneWidget);
  });

  testWidgets('chat honours ?course= and channels are per course',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const ChatScreen(initialCourseId: 'c-cs210'));

    expect(find.byKey(const Key('channel-ch-general-c-cs210')), findsOneWidget);
    // CS 301's seeded student reply must not leak into CS 210 (offline, an
    // empty channel only shows the synthetic welcome message).
    expect(find.text('Thanks, excited to start.'), findsNothing);
    expect(find.text('Welcome to the course!'), findsOneWidget);
  });
}
