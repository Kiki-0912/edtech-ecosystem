import 'package:edtech_app/auth/auth_provider.dart';
import 'package:flutter/foundation.dart';

/// True when [auth] holds a signed-in admin: the only sessions the admin
/// console accepts.
bool isAdminSession(AuthProvider auth) =>
    auth.isAuthenticated && (auth.user?.isAdmin ?? false);

/// Keeps non-admins out of the console. Any session whose user is not an
/// admin (a fresh sign-in, a restored session, or one whose role changed) is
/// signed out at once, and [notice] tells the login screen why.
class AdminAccess extends ChangeNotifier {
  AdminAccess(this._auth) {
    _auth.addListener(_check);
    _check();
  }

  static const deniedMessage = 'Admin access only';

  final AuthProvider _auth;
  String? _notice;

  /// Why the last session was refused, or null.
  String? get notice => _notice;

  void _check() {
    if (_auth.isAuthenticated && !isAdminSession(_auth)) {
      _notice = deniedMessage;
      _auth.logout();
      notifyListeners();
    }
  }

  /// Signs out a session the API no longer accepts (any 401 on an admin
  /// call), keeping the reason for the login screen: a disabled account, a
  /// revoked session (password reset or role change) or an expired one.
  void sessionEnded(String reason) {
    if (!_auth.isAuthenticated) return;
    _notice = reason;
    _auth.logout();
    notifyListeners();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_check);
    super.dispose();
  }
}
