import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the user's light / dark / system preference and persists it.
///
/// Colours come from `Theme.of(context)` (see `lib/ui/`), so switching modes
/// only needs `MaterialApp.themeMode` to change — no manual rebuild plumbing.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static const _prefsKey = 'theme_mode';

  static final ThemeController instance = ThemeController._();

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Restores the saved preference. Call once before the first frame so the
  /// app never flashes the wrong theme.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = switch (prefs.getString(_prefsKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // The preference is a nicety; the in-memory mode already applied.
    }
  }
}
