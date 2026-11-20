import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/login_screen.dart';
import 'package:edtech_app/auth/signup_screen.dart';
import 'package:edtech_app/auth/verify_sms_screen.dart';
import 'package:edtech_app/screens/attendance_screen.dart';
import 'package:edtech_app/screens/department_management_screen.dart';
import 'package:edtech_app/screens/notes_screen.dart';
import 'package:edtech_app/screens/student_management_screen.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/widgets/swipeable_tabs.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class EdTechApp extends StatefulWidget {
  const EdTechApp({super.key});

  @override
  State<EdTechApp> createState() => _EdTechAppState();
}

class _EdTechAppState extends State<EdTechApp> {
  /// Every route is wrapped in a [ThemedScope] so it re-runs `build` when the
  /// palette flips. The children are deliberately *not* `const`: an identical
  /// const instance would be short-circuited by the element tree and would keep
  /// rendering the old colours.
  late final GoRouter _router = GoRouter(
    refreshListenable: context.read<AuthProvider>(),
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/verify-sms';

      if (!auth.isAuthenticated && !loggingIn) {
        return '/login';
      }
      if (auth.isAuthenticated && loggingIn) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => SwipeableShell()),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => SignupScreen()),
      ),
      GoRoute(
        path: '/verify-sms',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => VerifySmsScreen()),
      ),
      GoRoute(
        path: '/students',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => StudentManagementScreen()),
      ),
      GoRoute(
        path: '/departments',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => DepartmentManagementScreen()),
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => AttendanceScreen()),
      ),
      GoRoute(
        path: '/notes',
        builder: (context, state) =>
            ThemedScope(buildChild: (_) => NotesScreen()),
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    ApiService.instance.token = auth.token;
    auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    ApiService.instance.token = context.read<AuthProvider>().token;
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follow the OS light/dark setting. `syncPalette` does not notify (we are
    // mid-build), so schedule the repaint for after this frame.
    final controller = context.read<ThemeController>();
    if (controller.syncPalette(
      platformBrightness: MediaQuery.platformBrightnessOf(context),
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.notifyPaletteChanged();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp.router(
      routerConfig: _router,
      title: 'EdTech Ecosystem',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      darkTheme: darkAppTheme,
      themeMode: theme.mode,
    );
  }
}
