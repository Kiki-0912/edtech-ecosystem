import 'package:edtech_app/config.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app talks to the live server or the on-device demo backend
/// ([OfflineClient]). Starts from the build's `OFFLINE_MODE`, then follows the
/// choice the user saved with the "Use online server" switch.
class DataModeController extends ChangeNotifier {
  DataModeController._();

  static final DataModeController instance = DataModeController._();

  static const prefsKey = 'data_mode_offline';

  /// Only native builds (the APK, desktop) offer the switch. The web app and
  /// the admin console are online-only.
  static bool get available => !kIsWeb;

  bool get isOffline => ApiService.instance.isOffline;

  /// Applies the saved choice. Call once before [AuthProvider.init].
  Future<void> load() async {
    if (!available) return;
    final prefs = await SharedPreferences.getInstance();
    ApiService.instance.offlineMode =
        prefs.getBool(prefsKey) ?? AppConfig.offlineMode;
    notifyListeners();
  }

  /// Switches the backend and remembers it. Returns false when nothing
  /// changed. Callers sign the user out: the two backends have different
  /// accounts and data.
  Future<bool> setOffline(bool offline) async {
    if (offline == isOffline) return false;
    ApiService.instance.offlineMode = offline;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, offline);
    notifyListeners();
    return true;
  }
}
