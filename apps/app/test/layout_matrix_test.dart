import 'dart:convert';

import 'package:edtech_app/auth/auth_provider.dart';
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
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders each redesigned screen for every role, at phone / tablet / desktop
/// widths, in light and dark. Any overflow or exception fails the test.
///
/// Add new screens to [screens] as they are rebuilt.
final Map<String, Widget Function()> screens = {
  'home': () => const HomeScreen(),
  'profile': () => const ProfileScreen(),
  'courses': () => const CoursesScreen(),
  'course-detail': () => const CourseDetailScreen(courseId: 'c-cs301'),
  'assignment': () =>
      const AssignmentScreen(courseId: 'c-cs301', assignmentId: 'a1'),
  'integrity': () => const IntegrityScreen(),
  'calendar': () => const CalendarScreen(),
  'chat': () => const ChatScreen(),
  'attendance': () => const AttendanceScreen(),
  'attendance-mark': () => const AttendanceMarkScreen(),
  'students': () => const StudentsScreen(),
  'departments': () => const DepartmentsScreen(),
  'notes': () => const NotesScreen(),
};

const sizes = <String, Size>{
  'phone': Size(390, 844),
  'tablet': Size(800, 1000),
  'desktop': Size(1440, 900),
};

const roleIds = <String, String>{
  // Seeded offline ids so role-filtered data is non-empty.
  'student': 'u-student-1',
  'teacher': 'u-teacher-1',
  'admin': 'u-admin-1',
};

Future<AuthProvider> signedIn(String role) async {
  SharedPreferences.setMockInitialValues({
    'auth_token': 'offline-demo-token',
    'auth_user': jsonEncode({
      'id': roleIds[role],
      'displayName': 'Test ${role[0].toUpperCase()}${role.substring(1)}',
      'email': '$role@example.edu',
      'phone': '+15550000000',
      'role': role,
      'courseIds': ['c-cs301', 'c-cs210', 'c-des150'],
      'createdAt': '2026-07-01T00:00:00.000Z',
    }),
  });
  final auth = AuthProvider();
  await auth.init();
  return auth;
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required Widget screen,
  required AuthProvider auth,
  required Size size,
  required bool dark,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(
          value: ThemeController.instance),
    ],
    child: MaterialApp(
      theme: dark ? darkTheme : lightTheme,
      home: Scaffold(body: screen),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  for (final role in roleIds.keys) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders for $role at all sizes, light & dark',
          (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = await signedIn(role);
        for (final size in sizes.entries) {
          for (final dark in [false, true]) {
            await pumpScreen(tester,
                screen: KeyedSubtree(
                    key: ValueKey('${size.key}-$dark'), child: entry.value()),
                auth: auth,
                size: size.value,
                dark: dark);
            expect(tester.takeException(), isNull,
                reason:
                    '${entry.key}/$role/${size.key}/${dark ? 'dark' : 'light'}');
          }
        }
      });
    }
  }

  for (final entry in screens.entries) {
    testWidgets('${entry.key} survives 1.3x text on a phone', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final role in ['student', 'admin']) {
        final auth = await signedIn(role);
        await pumpScreen(tester,
            screen: KeyedSubtree(key: ValueKey(role), child: entry.value()),
            auth: auth,
            size: sizes['phone']!,
            dark: false,
            textScale: 1.3);
        expect(tester.takeException(), isNull, reason: '${entry.key}/$role');
      }
    });
  }

  testWidgets('calendar day cells fit a 320px phone with 1.3x text',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final role in ['student', 'admin']) {
      final auth = await signedIn(role);
      await pumpScreen(tester,
          screen:
              KeyedSubtree(key: ValueKey(role), child: const CalendarScreen()),
          auth: auth,
          size: const Size(320, 640),
          dark: false,
          textScale: 1.3);
      expect(tester.takeException(), isNull, reason: 'calendar/$role');
    }
  });

  testWidgets('home shows role-specific content', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpAs(String role) =>
        signedIn(role).then((auth) => pumpScreen(tester,
            screen:
                KeyedSubtree(key: ValueKey(role), child: const HomeScreen()),
            auth: auth,
            size: const Size(1440, 900),
            dark: false));

    await pumpAs('student');
    expect(find.text('Due this week'), findsWidgets);
    expect(find.text('My attendance'), findsOneWidget);

    await pumpAs('teacher');
    expect(find.text('Open assignments'), findsOneWidget);
    expect(find.text('Mark attendance'), findsOneWidget);

    await pumpAs('admin');
    expect(find.text('Attendance this week'), findsOneWidget);
    expect(find.text('Departments'), findsOneWidget);
  });
}
