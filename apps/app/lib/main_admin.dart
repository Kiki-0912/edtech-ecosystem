import 'package:edtech_app/admin/admin_app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Admin console entry point:
/// `flutter build web -t lib/main_admin.dart` (see scripts/build_admin_web.sh).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Online only. The offline demo backend signs anyone in as an admin, so it
  // must never serve the admin console, whatever OFFLINE_MODE says.
  ApiService.instance.offlineMode = false;

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
      child: const AdminApp(),
    ),
  );
}
