import 'package:edtech_app/app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AuthProvider> _pumpApp(WidgetTester tester,
    {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthProvider();
  await auth.init();
  final theme = ThemeController.instance;
  await theme.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ],
    child: const EdTechApp(),
  ));
  await _settle(tester);
  return auth;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('login validates empty fields', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await _settle(tester);
    expect(find.text('Please enter your phone number'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('sign up as a teacher lands on the dashboard', (tester) async {
    final auth = await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('login-create-account')));
    await _settle(tester);

    // Admin is not offered: the API only accepts student/teacher.
    expect(find.text('Admin'), findsNothing);
    await tester.tap(find.text('Teacher'));
    await tester.enterText(find.byKey(const Key('signup-name')), 'Ada Teacher');
    await tester.enterText(
        find.byKey(const Key('signup-email')), 'ada@example.edu');
    await tester.enterText(
        find.byKey(const Key('signup-phone')), '+15550009999');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('signup-password')),
            matching: find.byType(TextFormField)),
        'secret123');
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await _settle(tester);

    expect(auth.isAuthenticated, isTrue);
    expect(auth.user?.role, 'teacher');
    // Previously the user stayed on the sign-up page (no router refresh).
    expect(find.byKey(const Key('signup-submit')), findsNothing);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
  });

  testWidgets('SMS code sign-in lands on the dashboard', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('login-sms')));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('sms-phone')), '+15550001005');
    await tester.tap(find.byKey(const Key('sms-send')));
    await _settle(tester);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);

    // Entering the 6th digit submits automatically.
    await tester.enterText(find.byKey(const Key('sms-code')), '123456');
    await _settle(tester);
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
  });

  testWidgets('wide login shows the brand panel', (tester) async {
    await _pumpApp(tester, size: const Size(1280, 800));
    expect(find.textContaining('Your classroom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('offline register rejects the admin role like the API', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = ApiService.instance..offlineMode = true;
    expect(
      () => api.register(
        phone: '+1555',
        email: 'x@example.edu',
        displayName: 'X',
        password: 'secret123',
        role: 'admin',
      ),
      throwsA(isA<ApiException>().having(
          (e) => e.message, 'message', 'Role must be student or teacher')),
    );
  });
}
