import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/config.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/shell/app_shell.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

const String kAppVersion = '0.3.0';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeController>();
    final user = auth.user;
    final c = context.colors;

    return AppPage(
      title: 'Profile & settings',
      subtitle: 'Your account and app preferences',
      children: [
        if (user != null)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Avatar(name: user.displayName, size: 64),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName, style: context.text.titleLarge),
                      const SizedBox(height: AppSpacing.xxs),
                      StatusBadge(
                        label: roleLabel(user.role),
                        tone: Tone.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (user != null)
          SectionCard(
            title: 'Account',
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: user.phone,
                ),
                _InfoRow(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  value: user.email.isEmpty ? '—' : user.email,
                ),
                _InfoRow(
                  icon: Icons.menu_book_outlined,
                  label: 'Courses',
                  value: '${user.courseIds.length}',
                ),
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Member since',
                  value: shortDate(user.createdAt),
                ),
              ],
            ),
          ),
        SectionCard(
          title: 'Appearance',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ThemeMode>(
              key: const Key('theme-mode'),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => theme.setMode(s.first),
            ),
          ),
        ),
        const SectionCard(
          title: 'About',
          child: Column(
            children: [
              _InfoRow(
                icon: AppConfig.offlineMode
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                label: 'Data source',
                value: AppConfig.offlineMode
                    ? 'Offline (on this device)'
                    : AppConfig.apiBaseUrl,
              ),
              _InfoRow(
                icon: Icons.info_outline_rounded,
                label: 'Version',
                value: kAppVersion,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('profile-logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger.withValues(alpha: 0.4)),
            ),
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 120,
            child: Text(label, style: context.text.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: context.text.titleSmall,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
