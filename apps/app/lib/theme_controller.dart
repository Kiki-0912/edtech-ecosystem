import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app's light/dark preference.
///
/// The neutral colour tokens in `theme.dart` are palette-backed getters rather
/// than `Theme.of(context)` lookups, so flipping the mode has to do two things:
///
///  1. swap [currentPalette] (done silently, in [syncPalette]);
///  2. notify listeners so every screen re-runs `build` and re-reads them.
///
/// Listeners are wired up by [ThemedScope], which wraps every route.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static const _prefsKey = 'theme_mode';

  static final ThemeController instance = ThemeController._();

  ThemeMode _mode = ThemeMode.system;
  Brightness _platformBrightness = Brightness.light;

  ThemeMode get mode => _mode;

  /// The palette the UI should currently be rendering with.
  Brightness get effectiveBrightness {
    switch (_mode) {
      case ThemeMode.system:
        return _platformBrightness;
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
    }
  }

  bool get isDark => effectiveBrightness == Brightness.dark;

  /// Restores the saved preference. Call once at startup, before the first
  /// frame, so the app never flashes the wrong theme.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      _mode = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      _mode = ThemeMode.system;
    }
    syncPalette();
    notifyListeners();
  }

  /// Swaps the active palette. Returns `true` when it actually changed, so the
  /// caller can schedule a rebuild — notifying listeners directly from
  /// `didChangeDependencies` would throw.
  bool syncPalette({Brightness? platformBrightness}) {
    if (platformBrightness != null) {
      _platformBrightness = platformBrightness;
    }
    final target = isDark ? kDarkPalette : kLightPalette;
    if (identical(currentPalette, target)) return false;
    setAppPalette(target);
    return true;
  }

  /// Re-reads the palette everywhere. Safe to call after the current frame.
  void notifyPaletteChanged() => notifyListeners();

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    syncPalette();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {
      // Preference is a nicety; the in-memory mode already applied.
    }
  }

  /// Convenience for the drawer switch: off → system, on → dark.
  Future<void> setDark(bool enabled) =>
      setMode(enabled ? ThemeMode.dark : ThemeMode.system);
}

/// Wraps every route so it re-runs `build` when the palette flips.
///
/// The child is produced by [buildChild] on each rebuild rather than held as a
/// field: an identical child instance would be short-circuited by the element
/// tree and would never pick up the new colours.
class ThemedScope extends StatelessWidget {
  const ThemedScope({super.key, required this.buildChild});

  final Widget Function(BuildContext context) buildChild;

  @override
  Widget build(BuildContext context) {
    // Registers the dependency that makes this scope rebuild on a mode change.
    context.watch<ThemeController>();
    return buildChild(context);
  }
}
