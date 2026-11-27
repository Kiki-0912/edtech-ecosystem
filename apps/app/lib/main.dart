import 'package:edtech_app/app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/services/data_mode.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Online vs. on-device data: the saved choice must apply before the
  // restored session is checked against a backend.
  await DataModeController.instance.load();
  final auth = AuthProvider();
  await auth.init();

  // Restore the light/dark preference before the first frame so the app never
  // flashes the wrong theme.
  final theme = ThemeController.instance;
  await theme.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      child: const EdTechApp(),
    ),
  );
}
