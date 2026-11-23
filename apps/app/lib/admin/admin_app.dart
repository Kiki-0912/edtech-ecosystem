import 'package:edtech_app/admin/admin_access.dart';
import 'package:edtech_app/admin/admin_router.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The admin console: a separate web app (`lib/main_admin.dart`) that shares
/// the design system, models and services with the main app. It talks to the
/// live API only and admits admin accounts only.
class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final AuthProvider _auth;
  late final AdminAccess _access;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    // Signs out a restored non-admin session before the first frame.
    _access = AdminAccess(_auth);
    _router = buildAdminRouter(_auth);
    ApiService.instance
      ..token = _auth.token
      // Shared screens (calendar, attendance, notes) must show an error, not
      // the main app's demo courses and events, when a request fails.
      ..demoFallback = false
      // A 401 from any request means the session is no longer valid (expired,
      // revoked, deleted or deactivated account); the login screen says why.
      ..onUnauthorized =
          (error) => _access.sessionEnded(_sessionEndedReason(error));
    _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    ApiService.instance.token = _auth.token ?? '';
  }

  static String _sessionEndedReason(ApiException error) => switch (error.code) {
        'ACCOUNT_DISABLED' || 'SESSION_REVOKED' => error.message,
        _ => 'Your session has expired. Sign in again.',
      };

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    ApiService.instance
      ..onUnauthorized = null
      ..demoFallback = true;
    _access.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return ChangeNotifierProvider<AdminAccess>.value(
      value: _access,
      child: MaterialApp.router(
        routerConfig: _router,
        title: 'EdTech Admin',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: theme.mode,
      ),
    );
  }
}
