import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/shell/destinations.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Adaptive app chrome around the active branch:
/// phone → bottom NavigationBar (4 tabs + More), tablet → NavigationRail,
/// desktop → labelled sidebar. The top bar is shared.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(AppDestination d) {
    navigationShell.goBranch(
      d.branchIndex,
      // Re-tapping the active tab returns to its root.
      initialLocation: d.branchIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final nav = navForRole(user?.role);
    void open() => showCommandPalette(context, [
          for (final d in nav.all)
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
    final user = context.watch<AuthProvider>().user;
    final nav = navForRole(user?.role);
    final current = kDestinations[navigationShell.currentIndex];
    final size = context.windowSize;

    final topBar = _TopBar(
      title: current.label,
      showBrand: size == WindowSize.compact,
      onProfile: () => _go(profile),
      onSearch: onSearch,
    );

    if (size == WindowSize.compact) {
      final primaryIndex = nav.primary.indexOf(current);
      return Scaffold(
        appBar: topBar,
        body: SwitchFade(
            token: navigationShell.currentIndex, child: navigationShell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: primaryIndex >= 0 ? primaryIndex : nav.primary.length,
          onDestinationSelected: (i) {
            if (i < nav.primary.length) {
              _go(nav.primary[i]);
            } else {
              _showMoreSheet(context, nav.more, current);
            }
          },
          destinations: [
            for (final d in nav.primary)
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

    final all = nav.all;
    final selected = all.indexOf(current);
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
              selectedIndex: selected >= 0 ? selected : null,
              onDestinationSelected: (i) => _go(all[i]),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: BrandMark(showName: false),
              ),
              destinations: [
                for (final d in all)
                  NavigationRailDestination(
                    icon: Icon(d.icon, key: d.navKey),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ))
        : _Sidebar(
            nav: nav,
            current: current,
            onSelect: _go,
          );

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

  void _showMoreSheet(BuildContext context, List<AppDestination> items,
      AppDestination current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('More', style: ctx.text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              for (final d in items)
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
  const _Sidebar({
    required this.nav,
    required this.current,
    required this.onSelect,
  });

  final RoleNav nav;
  final AppDestination current;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final all = [...nav.primary, ...nav.more];
    SidebarItem item(AppDestination d) => SidebarItem(
          label: d.label,
          icon: d.icon,
          selectedIcon: d.selectedIcon,
          itemKey: d.navKey,
        );
    return InkSidebar(
      groups: [
        SidebarGroup(items: [for (final d in nav.primary) item(d)]),
        if (nav.more.isNotEmpty)
          SidebarGroup(
              title: 'More', items: [for (final d in nav.more) item(d)]),
      ],
      selected: all.indexOf(current),
      onSelect: (i) => onSelect(all[i]),
      userName: user?.displayName,
      userRole: user == null ? null : roleLabel(user.role),
      onProfile: () => onSelect(profile),
    );
  }
}

String roleLabel(String role) =>
    role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)}';

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.title,
    required this.showBrand,
    required this.onProfile,
    required this.onSearch,
  });

  final String title;
  final bool showBrand;
  final VoidCallback onProfile;
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
        _BellButton(
          userId: user?.id,
          onPressed: () => _showUpcoming(context, user?.id),
        ),
        PopupMenuButton<String>(
          key: const Key('appbar-account'),
          tooltip: 'Account',
          offset: const Offset(0, 48),
          onSelected: (value) {
            switch (value) {
              case 'profile':
                onProfile();
              case 'light':
                theme.setMode(ThemeMode.light);
              case 'dark':
                theme.setMode(ThemeMode.dark);
              case 'system':
                theme.setMode(ThemeMode.system);
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
                  subtitle: roleLabel(user.role),
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'profile',
              child: _MenuRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile & settings'),
            ),
            PopupMenuItem(
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
              key: Key('menu-logout'),
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

  void _showUpcoming(BuildContext context, String? userId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.6,
        child: _UpcomingSheet(userId: userId),
      ),
    );
  }
}

/// The notifications bell. A small orange dot appears when something is due
/// within a day; it pulses a few times to catch the eye, then rests.
class _BellButton extends StatefulWidget {
  const _BellButton({required this.userId, required this.onPressed});

  final String? userId;
  final VoidCallback onPressed;

  @override
  State<_BellButton> createState() => _BellButtonState();
}

class _BellButtonState extends State<_BellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  bool _due = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final events = await ApiService.instance.getCalendar(widget.userId);
      final now = DateTime.now();
      final soon = events.any((e) =>
          !e.startsAt.isBefore(now) &&
          e.startsAt.isBefore(now.add(const Duration(hours: 24))));
      if (!mounted || !soon) return;
      setState(() => _due = true);
      if (!AppMotion.reduced(context)) _pulse.repeat(reverse: true, count: 6);
    } catch (_) {
      // The bell is decoration; the sheet reports errors itself.
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      key: const Key('appbar-notifications'),
      tooltip: 'Upcoming',
      onPressed: widget.onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (_due)
            Positioned(
              right: 0,
              top: 0,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: c.accentGlow,
                        blurRadius: 2 + 8 * _pulse.value,
                        spreadRadius: 3 * _pulse.value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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

/// Upcoming events for the signed-in user (the "notifications" bell).
class _UpcomingSheet extends StatefulWidget {
  const _UpcomingSheet({required this.userId});

  final String? userId;

  @override
  State<_UpcomingSheet> createState() => _UpcomingSheetState();
}

class _UpcomingSheetState extends State<_UpcomingSheet> {
  late final Future<List<CalendarEvent>> _future =
      ApiService.instance.getCalendar(widget.userId);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upcoming', style: context.text.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: FutureBuilder<List<CalendarEvent>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SkeletonList(count: 3, itemHeight: 56);
                }
                final now = DateTime.now();
                final events = (snap.data ?? const <CalendarEvent>[])
                    .where((e) => !e.startsAt
                        .isBefore(DateTime(now.year, now.month, now.day)))
                    .toList()
                  ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
                if (events.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    illustration: IllustrationKind.caughtUp,
                    title: 'You\'re all caught up',
                    message: 'No upcoming classes or deadlines.',
                  );
                }
                return ListView.separated(
                  itemCount: events.length.clamp(0, 20),
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    return ListRow(
                      leading: IconBadge(
                          icon: eventIcon(e.kind),
                          tone: eventTone(e.kind),
                          size: 36),
                      title: e.title,
                      subtitle: isSameDay(e.startsAt, now)
                          ? 'Today · ${clockTime(e.startsAt)}'
                          : '${shortDate(e.startsAt)} · ${clockTime(e.startsAt)}',
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData eventIcon(String kind) => switch (kind) {
      'assignment' => Icons.assignment_outlined,
      'quiz' => Icons.quiz_outlined,
      'institution' => Icons.account_balance_outlined,
      _ => Icons.class_outlined,
    };

Tone eventTone(String kind) => switch (kind) {
      'assignment' => Tone.warning,
      'quiz' => Tone.danger,
      'institution' => Tone.info,
      _ => Tone.accent,
    };
