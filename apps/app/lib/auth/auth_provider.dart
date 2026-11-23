import 'dart:convert';

import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null && _token != null;
  bool get isInitialized => _initialized;
  String? get error => _error;

  final ApiService _api = ApiService();

  /// Load persisted auth state from local storage. Call once before runApp.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (token != null && userJson != null) {
      try {
        _token = token;
        _user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        // Corrupted persisted state: clear it.
        _token = null;
        _user = null;
        await clearPersisted();
      }
    }
    await _revalidate();
    _initialized = true;
    notifyListeners();
  }

  /// Against the real API, confirm a restored session is still valid and
  /// refresh the cached user. Only a definite 401 signs the user out; network
  /// failures keep the session so the app still opens without connectivity.
  Future<void> _revalidate() async {
    final token = _token;
    if (token == null || _api.isOffline) return;
    try {
      final data =
          await _api.getMe(token: token).timeout(const Duration(seconds: 5));
      final userJson = data['user'];
      if (userJson is Map<String, dynamic>) {
        _user = User.fromJson(userJson);
        await _persist();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _token = null;
        _user = null;
        await clearPersisted();
      }
    } catch (_) {
      // Offline / timeout: keep the cached session.
    }
  }

  Future<void> _persist() async {
    if (_token == null || _user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
  }

  Future<void> clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// Signs in with [phone] or [email] plus [password].
  Future<bool> login({
    String? phone,
    String? email,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final data =
          await _api.login(phone: phone, email: email, password: password);
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _token = data['token'] as String;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Public sign-up always creates a student account; teachers and admins are
  /// added by an admin.
  Future<bool> register({
    required String phone,
    required String email,
    required String displayName,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _api.register(
        phone: phone,
        email: email,
        displayName: displayName,
        password: password,
      );
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _token = data['token'] as String;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> sendSmsCode({
    required String phone,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      await _api.sendSmsCode(phone: phone);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> verifySmsCode({
    required String phone,
    required String code,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _api.verifySmsCode(phone: phone, code: code);
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _token = data['token'] as String;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> getMe({
    required String token,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final data = await _api.getMe(token: token);
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _token = token;
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    _error = null;
    await clearPersisted();
    notifyListeners();
  }

  void clearError() {
    _error = null;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
