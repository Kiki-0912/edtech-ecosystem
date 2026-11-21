import 'package:edtech_app/app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end journey through the real app shell: sign in, open every
/// destination the (offline demo admin) role has, then sign out.
void main() {
  testWidgets('app: login then every bottom-nav tab opens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final auth = AuthProvider();
    await auth.init();
    final theme = ThemeController.instance;
    await theme.load();

    // Several screens run looping animations (skeletons, floating shapes), so
    // pumpAndSettle would never quiesce; advance the clock explicitly.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
        ],
        child: const EdTechApp(),
      ),
    );
    await settle();

    // Login screen is showing.
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '+15550001005');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.byKey(const Key('login-submit')));
    await settle();

    // Dashboard is showing (offline sign-in is always the demo admin).
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(find.text('Attendance this week'), findsOneWidget);

    // Admin primary tabs, then everything under "More". The shell title shows
    // the destination label; the second string is a marker from the screen.
    const primary = <String, String>{
      'students': 'Search name, email, phone or roll number',
      'departments': 'Search departments',
      'attendance': 'By course',
    };
    for (final entry in primary.entries) {
      await tester.tap(find.byKey(Key('nav-${entry.key}')));
      await settle();
      expect(find.text(entry.value), findsWidgets,
          reason: 'tab ${entry.key} did not open');
      expect(tester.takeException(), isNull, reason: 'tab ${entry.key} threw');
    }

    const overflow = <String, String>{
      'courses': 'Search by course, code or teacher',
      'calendar': 'Calendar',
      'chat': '# General',
      'notes': 'Search title, book, course or content',
      'integrity': 'Integrity',
      'profile': 'Profile & settings',
    };
    for (final entry in overflow.entries) {
      await tester.tap(find.byKey(const Key('nav-more')));
      await settle();
      await tester.tap(find.byKey(Key('more-${entry.key}')));
      await settle();
      expect(find.text(entry.value), findsWidgets,
          reason: 'overflow tab ${entry.key} did not open');
      expect(tester.takeException(), isNull,
          reason: 'overflow tab ${entry.key} threw');
    }

    // Sign out from Profile returns to the login screen (router refresh).
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-logout')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('profile-logout')));
    await settle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });
}
