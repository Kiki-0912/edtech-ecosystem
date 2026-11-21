import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/screens/attendance/attendance_mark_screen.dart';
import 'package:edtech_app/screens/attendance/attendance_screen.dart';
import 'package:edtech_app/screens/departments/departments_screen.dart';
import 'package:edtech_app/screens/notes/notes_screen.dart';
import 'package:edtech_app/screens/students/students_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/csv.dart';
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

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  setUp(() => ApiService.instance.offlineMode = true);

  group('csv', () {
    test('round-trips quotes, commas and newlines', () {
      final csv = toCsv([
        'name',
        'note'
      ], [
        {'name': 'Ada, L.', 'note': 'said "hi"\nthen left'},
      ]);
      final rows = parseCsv(csv);
      expect(rows[1], ['Ada, L.', 'said "hi"\nthen left']);
    });

    test('maps header aliases', () {
      final rows = parseCsvRecords('Full Name,Roll No,Phone\nAda,R1,+1',
          aliases: {
            'fullname': 'name',
            'rollno': 'rollNumber',
            'phone': 'contact'
          });
      expect(rows.single, {'name': 'Ada', 'rollNumber': 'R1', 'contact': '+1'});
    });
  });

  testWidgets('admin adds, edits and removes a student', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('admin');
    await pump(tester, auth, const StudentsScreen());

    await tapKey(tester, 'student-add');
    await tester.enterText(
        find.byKey(const Key('student-name')), 'Test Student');
    await tester.enterText(
        find.byKey(const Key('student-phone')), '+15550007777');
    await tapKey(tester, 'student-save');
    expect(find.text('Student added'), findsOneWidget);
    expect(find.text('Test Student'), findsOneWidget);

    // Edit (new: previously there was no edit UI).
    await tester.enterText(
        find.byKey(const Key('students-search')), 'Test Student');
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('student-name')), 'Renamed Student');
    await tapKey(tester, 'student-save');
    await tester.enterText(find.byKey(const Key('students-search')), '');
    await settle(tester);
    expect(find.text('Renamed Student'), findsOneWidget);

    // Remove with confirmation.
    await tester.enterText(find.byKey(const Key('students-search')), 'Renamed');
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('Renamed Student'), findsNothing);
  });

  testWidgets('admin imports students from pasted CSV', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('admin');
    await pump(tester, auth, const StudentsScreen());

    await tapKey(tester, 'students-import');
    await tester.enterText(
      find.byKey(const Key('import-csv')),
      'name,rollNumber,contact\nImported One,CIT-9001,+15550009001\nNo Contact,CIT-9002,',
    );
    await settle(tester);
    expect(find.textContaining('1 of 2 rows ready'), findsOneWidget);
    await tapKey(tester, 'import-submit');
    expect(find.textContaining('Imported 1 students'), findsOneWidget);
    expect(find.text('Imported One'), findsOneWidget);
  });

  testWidgets('teachers get a read-only roster with export', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(tester, auth, const StudentsScreen());

    expect(find.byKey(const Key('student-add')), findsNothing);
    expect(find.byKey(const Key('students-import')), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    await tapKey(tester, 'students-export');
    expect(find.byKey(const Key('export-preview')), findsOneWidget);
    expect(find.textContaining('name,rollNumber,contact'), findsOneWidget);
  });

  testWidgets('admin creates, renames and deletes a department',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('admin');
    await pump(tester, auth, const DepartmentsScreen());

    await tapKey(tester, 'department-add');
    await tester.enterText(
        find.byKey(const Key('department-name')), 'Robotics');
    await tester.enterText(find.byKey(const Key('department-code')), 'rob');
    await tapKey(tester, 'department-save');
    expect(find.text('Department created'), findsOneWidget);
    expect(find.text('Robotics'), findsOneWidget);
    expect(find.text('ROB'), findsOneWidget);

    // Open its menu → Edit.
    final menu = find.descendant(
      of: find
          .ancestor(of: find.text('Robotics'), matching: find.byType(Column))
          .first,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu.first);
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('department-name')), 'Robotics & AI');
    await tapKey(tester, 'department-save');
    expect(find.text('Robotics & AI'), findsOneWidget);

    await tester.tap(find
        .descendant(
          of: find
              .ancestor(
                  of: find.text('Robotics & AI'), matching: find.byType(Column))
              .first,
          matching: find.byType(PopupMenuButton<String>),
        )
        .first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('Robotics & AI'), findsNothing);
  });

  testWidgets('admin adds a student to a department', (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('admin');
    await pump(tester, auth, const DepartmentsScreen());

    await tester.tap(find.text('Electrical Technology'));
    await settle(tester);
    final add = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('member-add-'));
    final before = find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('member-remove-'))
        .evaluate()
        .length;
    await tester.ensureVisible(add.first);
    await tester.tap(add.first);
    await settle(tester);
    final after = find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('member-remove-'))
        .evaluate()
        .length;
    expect(after, before + 1);
  });

  testWidgets('marking: add a note (regression), set status, save',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('teacher');
    await pump(
        tester, auth, const AttendanceMarkScreen(initialCourseId: 'c-cs301'));

    // The note button is always available (it used to render only once a
    // note already existed, so a first note could never be added).
    await tapKey(tester, 'mark-note-u-student-1');
    await tester.enterText(
        find.byKey(const Key('attendance-note-input')), 'Doctor visit');
    await tapKey(tester, 'attendance-note-save');
    expect(find.text('Doctor visit'), findsOneWidget);

    await tapKey(tester, 'mark-u-student-1-late');
    await tapKey(tester, 'attendance-save');
    expect(find.text('Attendance saved successfully'), findsOneWidget);

    final records =
        await ApiService.instance.getAttendanceRecords(courseId: 'c-cs301');
    final today = DateTime.now();
    final iso =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final mine =
        records.where((r) => r.studentId == 'u-student-1' && r.date == iso);
    expect(mine.single.status, 'late');
    expect(mine.single.notes, 'Doctor visit');
  });

  testWidgets('students see their record and can request an excuse',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    await pump(tester, auth, const AttendanceScreen());

    expect(find.text('Class entries'), findsOneWidget);
    expect(find.byKey(const Key('attendance-mark')), findsNothing);

    await tapKey(tester, 'attendance-excuse');
    await tester.enterText(
        find.byKey(const Key('excuse-reason')), 'Medical appointment');
    await tapKey(tester, 'excuse-send');
    expect(find.textContaining('Request sent to'), findsOneWidget);
  });

  testWidgets('teacher creates, edits and deletes a note; students read only',
      (tester) async {
    addTearDown(tester.view.reset);
    // u-teacher-1 so the note is authored by this teacher.
    final auth = await signedIn('teacher');
    await pump(tester, auth, const NotesScreen());

    await tapKey(tester, 'note-add');
    await tester.enterText(
        find.byKey(const Key('note-title')), 'Week 3 reading');
    await tester.enterText(find.byKey(const Key('note-book')), 'Don Norman');
    await tester.enterText(
        find.byKey(const Key('note-content')), 'Chapters 1–2');
    await tapKey(tester, 'note-save');
    expect(find.text('Note saved'), findsOneWidget);
    expect(find.text('Week 3 reading'), findsOneWidget);

    await tester.tap(find.text('Week 3 reading'));
    await settle(tester);
    await tapKey(tester, 'note-edit');
    await tester.enterText(
        find.byKey(const Key('note-title')), 'Week 3 reading (updated)');
    await tapKey(tester, 'note-save');
    expect(find.text('Week 3 reading (updated)'), findsOneWidget);

    await tester.tap(find.text('Week 3 reading (updated)'));
    await settle(tester);
    await tapKey(tester, 'note-delete');
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await settle(tester);
    expect(find.text('Week 3 reading (updated)'), findsNothing);

    final student = await signedIn('student');
    await pump(tester, student, const NotesScreen(key: ValueKey('student')));
    expect(find.byKey(const Key('note-add')), findsNothing);
  });
}
