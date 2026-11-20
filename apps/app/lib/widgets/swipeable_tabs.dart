import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/theme_controller.dart';
import 'package:edtech_app/screens/dashboard_screen.dart';
import 'package:edtech_app/screens/courses_screen.dart';
import 'package:edtech_app/screens/calendar_screen.dart';
import 'package:edtech_app/screens/chat_screen.dart';
import 'package:edtech_app/screens/integrity_screen.dart';
import 'package:edtech_app/screens/student_management_screen.dart';
import 'package:edtech_app/screens/department_management_screen.dart';
import 'package:edtech_app/screens/attendance_screen.dart';
import 'package:edtech_app/screens/notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A swipeable bottom navigation shell. On phones, users can swipe left/right
/// between the main tabs instead of only tapping the bottom bar.
class SwipeableShell extends StatefulWidget {
  const SwipeableShell({super.key});

  @override
  State<SwipeableShell> createState() => _SwipeableShellState();
}

class _SwipeableShellState extends State<SwipeableShell> {
  int _index = 0;
  final PageController _pageController = PageController();

  /// Built fresh on every [build] on purpose: a `const DashboardScreen()` is
  /// canonicalised to the same instance each time, so the element tree would
  /// short-circuit on `identical` and the tab would keep rendering whichever
  /// palette was active when it was first mounted.
  List<Widget> _buildScreens() => <Widget>[
        DashboardScreen(),
        CoursesScreen(),
        CalendarScreen(),
        ChatScreen(),
        IntegrityScreen(),
        StudentManagementScreen(),
        DepartmentManagementScreen(),
        AttendanceScreen(),
        NotesScreen(),
      ];

  static const List<String> _titles = <String>[
    'Dashboard',
    'Courses',
    'Calendar',
    'Chat',
    'Integrity',
    'Students',
    'Departments',
    'Attendance',
    'Notes',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.dashboard_rounded,
    Icons.school_rounded,
    Icons.calendar_month_rounded,
    Icons.chat_bubble_rounded,
    Icons.verified_rounded,
    Icons.people_rounded,
    Icons.business_rounded,
    Icons.check_circle_rounded,
    Icons.note_rounded,
  ];

  void _selectTab(int index) {
    setState(() => _index = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-runs `build` when the light/dark palette flips (the shell is also
    // wrapped in a ThemedScope; this keeps it correct however it is mounted).
    context.watch<ThemeController>();
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Scaffold(
      key: _scaffoldKey,
      appBar: isMobile
          ? AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: candyGradient,
                      borderRadius: BorderRadius.circular(kRadiusSm),
                    ),
                    child: const Center(
                      child: Icon(Icons.school_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: kSpaceSm),
                  Text(
                    _titles[_index],
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(
                  tooltip: 'Menu',
                  icon: Icon(Icons.menu_rounded, color: kTextPrimary),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ],
            )
          : null,
      drawer: isMobile
          ? AppDrawer(
              selectedIndex: _index,
              onSelect: _selectTab,
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _index = index),
              children: _buildScreens(),
            ),
          ),
          if (isMobile)
            Container(
              color: kSurface,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(height: 1, color: kDivider),
                    SizedBox(
                      height: 72,
                      child: Row(
                        children: List.generate(
                          _titles.length,
                          (index) => _NavItem(
                            icon: _icons[index],
                            title: _titles[index],
                            color: kTabColors[index % kTabColors.length],
                            selected: _index == index,
                            onTap: () => _selectTab(index),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.title,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? tintOf(color, 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
              child: Icon(
                icon,
                color: selected ? color : kTextSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? color : kTextSecondary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const AppDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _items = [
    _DrawerItemData(Icons.dashboard_rounded, 'Dashboard', 'Overview of your week'),
    _DrawerItemData(Icons.school_rounded, 'Courses', 'Enrolled classes & assignments'),
    _DrawerItemData(Icons.calendar_month_rounded, 'Calendar', 'Deadlines & events'),
    _DrawerItemData(Icons.chat_bubble_rounded, 'Chat', 'Classroom discussion'),
    _DrawerItemData(Icons.verified_rounded, 'Integrity', 'Effort & authenticity score'),
    _DrawerItemData(Icons.people_rounded, 'Students', 'Manage student roster'),
    _DrawerItemData(Icons.business_rounded, 'Departments', 'Programme drag-drop'),
    _DrawerItemData(Icons.check_circle_rounded, 'Attendance', 'Mark present / absent'),
    _DrawerItemData(Icons.note_rounded, 'Notes', 'Teacher notes & books'),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    return Drawer(
      child: Container(
        color: kSurface,
        child: Column(
          children: [
            _DrawerHeader(
              name: user?.displayName ?? 'Student',
              subtitle: user == null
                  ? 'Not signed in'
                  : '${user.role[0].toUpperCase()}${user.role.substring(1)}'
                      '${user.courseIds.isNotEmpty ? ' · ${user.courseIds.length} courses' : ''}',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var index = 0; index < _items.length; index++)
                    _DrawerItem(
                      icon: _items[index].icon,
                      title: _items[index].title,
                      subtitle: _items[index].subtitle,
                      color: kTabColors[index % kTabColors.length],
                      selected: selectedIndex == index,
                      onTap: () {
                        onSelect(index);
                        Navigator.of(context).pop();
                      },
                    ),
                  const Divider(height: 32),
                  _ThemeToggle(),
                  _DrawerItem(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    subtitle: 'Leave the session',
                    color: kError,
                    onTap: () {
                      Navigator.of(context).pop();
                      Provider.of<AuthProvider>(context, listen: false).logout();
                    },
                  ),
                ],
              ),
            ),
            const _DrawerFooter(),
          ],
        ),
      ),
    );
  }
}

class _DrawerItemData {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DrawerItemData(this.icon, this.title, this.subtitle);
}

/// Light / dark switch that mirrors the rest of the drawer's list rows.
class _ThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final subtitle = switch (theme.mode) {
      ThemeMode.system => 'Following system',
      ThemeMode.dark => 'On',
      ThemeMode.light => 'Off',
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpaceMd, vertical: kSpaceXs),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: tintOf(kTextSecondary, 0.10),
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        child: Icon(
          theme.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: kTextSecondary,
          size: 22,
        ),
      ),
      title: Text(
        'Dark mode',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: kTextPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: kTextSecondary, fontSize: 12),
      ),
      trailing: Switch(
        value: theme.isDark,
        // Off goes to *light* rather than `system`: on a device whose OS is
        // already dark, `system` would be a no-op and the switch would spring
        // straight back on.
        onChanged: (enabled) =>
            theme.setMode(enabled ? ThemeMode.dark : ThemeMode.light),
      ),
      dense: true,
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final String name;
  final String subtitle;

  const _DrawerHeader({required this.name, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: const BoxDecoration(gradient: candyGradient),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white,
              child: Icon(Icons.school_rounded, color: kPrimary),
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: kSpaceXs),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? tintOf(color, 0.08) : Colors.transparent,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: kSpaceMd, vertical: kSpaceXs),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? color : tintOf(color, 0.10),
            borderRadius: BorderRadius.circular(kRadiusSm),
          ),
          child: Icon(icon, color: selected ? Colors.white : color, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: kTextSecondary,
            fontSize: 12,
          ),
        ),
        trailing: selected
            ? Icon(Icons.chevron_right_rounded, color: color, size: 18)
            : null,
        dense: true,
        onTap: onTap,
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kDivider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.build_rounded, color: kTextSecondary, size: 20),
            title: Text(
              'App version',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
            subtitle: Text(
              '0.3.0+1',
              style: TextStyle(color: kTextSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
