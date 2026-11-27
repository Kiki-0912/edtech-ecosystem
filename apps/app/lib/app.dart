import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/router.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class EdTechApp extends StatefulWidget {
  const EdTechApp({super.key});

  @override
  State<EdTechApp> createState() => _EdTechAppState();
}

class _EdTechAppState extends State<EdTechApp> {
  late final AuthProvider _auth;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _router = buildRouter(_auth);
    ApiService.instance.token = _auth.token;
    // A 401 from any request means the session is no longer valid.
    ApiService.instance.onUnauthorized = (_) {
      if (_auth.isAuthenticated) _auth.logout();
    };
    _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    ApiService.instance.token = _auth.token ?? '';
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    ApiService.instance.onUnauthorized = null;
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp.router(
      routerConfig: _router,
      title: 'Edu-tech Ecosystem',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: theme.mode,
    );
  }
}
