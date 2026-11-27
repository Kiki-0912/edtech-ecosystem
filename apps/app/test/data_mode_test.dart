import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/login_screen.dart';
import 'package:edtech_app/screens/profile/profile_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/data_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_matrix_test.dart' show pumpScreen, signedIn;

/// The "Use online server" switch: a runtime choice between the live API and
/// the on-device demo backend, saved across restarts.
void main() {
  const phone = Size(390, 844);

  tearDown(() => ApiService.instance.offlineMode = true);

  Future<bool?> savedChoice() async => (await SharedPreferences.getInstance())
      .getBool(DataModeController.prefsKey);

  group('DataModeController', () {
    test('starts from the build default (offline) when nothing is saved',
        () async {
      SharedPreferences.setMockInitialValues({});
      ApiService.instance.offlineMode = null;
      await DataModeController.instance.load();
      expect(DataModeController.instance.isOffline, isTrue);
    });

    test('restores a saved online choice', () async {
      SharedPreferences.setMockInitialValues(
          {DataModeController.prefsKey: false});
      await DataModeController.instance.load();
      expect(DataModeController.instance.isOffline, isFalse);
      expect(ApiService.instance.isOffline, isFalse);
    });

    test('setOffline saves the choice and reports whether it changed',
        () async {
      SharedPreferences.setMockInitialValues({});
      ApiService.instance.offlineMode = true;
      expect(await DataModeController.instance.setOffline(true), isFalse);
      expect(await DataModeController.instance.setOffline(false), isTrue);
      expect(await savedChoice(), isFalse);
      expect(ApiService.instance.isOffline, isFalse);
    });
  });

  testWidgets('login screen switch goes online and hides offline-only SMS',
      (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    ApiService.instance.offlineMode = true;
    final auth = AuthProvider();
    await auth.init();
    await pumpScreen(tester,
        screen: const LoginScreen(), auth: auth, size: phone, dark: false);

    expect(find.byKey(const Key('login-sms')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login-mode-toggle')));
    await tester.tap(find.byKey(const Key('login-mode-toggle')));
    await tester.pumpAndSettle();

    expect(ApiService.instance.isOffline, isFalse);
    expect(await savedChoice(), isFalse);
    // Online without an SMS provider, the code sign-in can't finish.
    expect(find.byKey(const Key('login-sms')), findsNothing);
  });

  testWidgets('profile switch asks first, then switches and signs out',
      (tester) async {
    addTearDown(tester.view.reset);
    final auth = await signedIn('student');
    ApiService.instance.offlineMode = true;
    await pumpScreen(tester,
        screen: const ProfileScreen(), auth: auth, size: phone, dark: false);

    final toggle = find.byKey(const Key('profile-mode-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Cancel keeps everything as it was.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ApiService.instance.isOffline, isTrue);
    expect(auth.isAuthenticated, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-ok')));
    await tester.pumpAndSettle();
    expect(ApiService.instance.isOffline, isFalse);
    expect(await savedChoice(), isFalse);
    expect(auth.isAuthenticated, isFalse);
  });
}
