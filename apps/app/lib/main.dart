import 'package:edtech_app/app.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
