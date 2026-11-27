import 'package:edtech_app/admin/admin_destinations.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/shell/app_shell.dart' show roleLabel;
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Adaptive chrome for the admin console, following the main `AppShell`:
/// phone → bottom NavigationBar (4 tabs + More), tablet → NavigationRail,
/// desktop → labelled sidebar. The top bar is shared.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(AdminDestination d) {
    navigationShell.goBranch(
      d.branchIndex,
      // Re-tapping the active tab returns to its root.
      initialLocation: d.branchIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    void open() => showCommandPalette(context, [
          for (final d in kAdminDestinations)
            PaletteItem(
              label: d.label,
              icon: d.icon,
              hint: 'Go to ${d.label}',
              onSelect: () => _go(d),
            ),
        ]);
    return PaletteShortcut(onOpen: open, child: _layout(context, open));
  }

  Widget _layout(BuildContext context, VoidCallback onSearch) {
    final current = kAdminDestinations[navigationShell.currentIndex];
    final size = context.windowSize;
    final topBar = _AdminTopBar(
      title: current.label,
      showBrand: size == WindowSize.compact,
      onSearch: onSearch,
    );

    if (size == WindowSize.compact) {
      final primary = adminPrimary;
      final primaryIndex = primary.indexOf(current);
      return Scaffold(
        appBar: topBar,
        body: SwitchFade(
            token: navigationShell.currentIndex, child: navigationShell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: primaryIndex >= 0 ? primaryIndex : primary.length,
          onDestinationSelected: (i) {
            if (i < primary.length) {
              _go(primary[i]);
            } else {
              _showMoreSheet(context, current);
            }
          },
          destinations: [
            for (final d in primary)
              NavigationDestination(
                key: d.navKey,
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            const NavigationDestination(
              key: Key('nav-more'),
              icon: Icon(Icons.apps_rounded),
              label: 'More',
            ),
          ],
        ),
      );
    }

    final c = context.colors;
    final sideNav = size == WindowSize.medium
        ? Theme(
            data: Theme.of(context).copyWith(
              navigationRailTheme: NavigationRailThemeData(
                backgroundColor: c.ink,
                indicatorColor: c.accent,
                indicatorShape: const StadiumBorder(),
                selectedIconTheme: IconThemeData(color: c.onAccent),
                unselectedIconTheme: IconThemeData(color: c.onInk),
                selectedLabelTextStyle: context.text.labelMedium
                    ?.copyWith(color: c.onInk, fontWeight: FontWeight.w700),
                unselectedLabelTextStyle: context.text.labelMedium
                    ?.copyWith(color: c.onInk.withValues(alpha: 0.7)),
              ),
            ),
            child: NavigationRail(
              selectedIndex: current.branchIndex,
              onDestinationSelected: (i) => _go(kAdminDestinations[i]),
              labelType: NavigationRailLabelType.all,
              // Nine sections do not fit a short window (landscape phone).
              scrollable: true,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: BrandMark(showName: false),
              ),
              destinations: [
                for (final d in kAdminDestinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon, key: d.navKey),
                    selectedIcon: Icon(d.selectedIcon, key: d.navKey),
                    label: Text(d.label),
                  ),
              ],
            ))
        : _Sidebar(current: current, onSelect: _go);

    return Scaffold(
      body: Row(
        children: [
          sideNav,
          Expanded(
            child: Scaffold(
              appBar: topBar,
              body: SwitchFade(
                  token: navigationShell.currentIndex, child: navigationShell),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreSheet(BuildContext context, AdminDestination current) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('More', style: ctx.text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              for (final d in adminMore)
                ListTile(
                  key: Key('more-${d.id}'),
                  leading: Icon(d == current ? d.selectedIcon : d.icon),
                  title: Text(d.label),
                  selected: d == current,
                  selectedColor: ctx.colors.accentText,
                  selectedTileColor: ctx.colors.accentSoft,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _go(d);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final AdminDestination current;
  final ValueChanged<AdminDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return InkSidebar(
      badge: const StatusBadge(label: 'Admin', tone: Tone.info),
      groups: [
        SidebarGroup(items: [
          for (final d in kAdminDestinations)
            SidebarItem(
              label: d.label,
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              itemKey: d.navKey,
            ),
        ]),
      ],
      selected: kAdminDestinations.indexOf(current),
      onSelect: (i) => onSelect(kAdminDestinations[i]),
      userName: user?.displayName,
      userRole: user == null ? null : roleLabel(user.role),
    );
  }
}

class _AdminTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _AdminTopBar({
    required this.title,
    required this.showBrand,
    required this.onSearch,
  });

  final String title;
  final bool showBrand;
  final VoidCallback onSearch;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final theme = context.watch<ThemeController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      toolbarHeight: 60,
      titleSpacing: AppSpacing.md,
      title: showBrand
          ? Row(
              children: [
                const BrandMark(showName: false, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
              ],
            )
          : Text(title),
      actions: [
        IconButton(
          key: const Key('appbar-search'),
          tooltip: 'Search (Ctrl+K)',
          icon: const Icon(Icons.search_rounded),
          onPressed: onSearch,
        ),
        PopupMenuButton<String>(
          key: const Key('admin-account'),
          tooltip: 'Account',
          offset: const Offset(0, 48),
          onSelected: (value) {
            switch (value) {
              case 'light':
                theme.setMode(ThemeMode.light);
              case 'dark':
                theme.setMode(ThemeMode.dark);
              case 'logout':
                auth.logout();
            }
          },
          itemBuilder: (_) => [
            if (user != null)
              PopupMenuItem<String>(
                enabled: false,
                child: ListRow(
                  dense: true,
                  leading: Avatar(name: user.displayName, size: 32),
                  title: user.displayName,
                  subtitle:
                      user.email.isNotEmpty ? user.email : roleLabel(user.role),
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              key: const Key('admin-theme'),
              value: isDark ? 'light' : 'dark',
              child: _MenuRow(
                icon: isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: isDark ? 'Light mode' : 'Dark mode',
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              key: Key('admin-logout'),
              value: 'logout',
              child: _MenuRow(icon: Icons.logout_rounded, label: 'Sign out'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Avatar(name: user?.displayName ?? '?', size: 34),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.colors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}
