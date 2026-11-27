import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/config.dart';
import 'package:edtech_app/services/data_mode.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// "Use online server" switch: live API (real accounts) vs. the demo data
/// stored on this device. Switching signs the user out, because the two
/// backends have different accounts.
class DataModeSwitch extends StatelessWidget {
  const DataModeSwitch({
    super.key,
    required this.switchKey,
    this.confirm = false,
  });

  /// Stable key for the switch itself (tests find it by key).
  final Key switchKey;

  /// Ask before switching (used when someone is signed in).
  final bool confirm;

  Future<void> _change(BuildContext context, bool online) async {
    final auth = context.read<AuthProvider>();
    if (confirm) {
      final ok = await confirmDialog(
        context,
        title: online ? 'Switch to the online server?' : 'Switch to offline?',
        message: online
            ? 'You will be signed out. Sign in again with your real account. '
                'This needs an internet connection.'
            : 'You will be signed out. Offline mode uses demo data stored on '
                'this device and works without internet.',
        confirmLabel: 'Switch',
      );
      if (!ok) return;
    }
    final changed = await DataModeController.instance.setOffline(!online);
    if (changed && auth.isAuthenticated) await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataModeController.instance,
      builder: (context, _) {
        final offline = DataModeController.instance.isOffline;
        return SwitchListTile(
          key: switchKey,
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            color: context.colors.textMuted,
          ),
          title: Text('Use online server', style: context.text.titleSmall),
          subtitle: Text(
            offline
                ? 'Off: demo data on this device, no internet needed'
                : 'On: ${Uri.parse(AppConfig.apiBaseUrl).host}, real accounts',
            style: context.text.bodySmall,
          ),
          value: !offline,
          onChanged: (online) => _change(context, online),
        );
      },
    );
  }
}
