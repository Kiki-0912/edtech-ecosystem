import 'package:material_ui/material_ui.dart';

/// One top-level section of the app. Its position in [kDestinations] is its
/// `StatefulShellRoute` branch index, so the order here must match `router.dart`.
class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  int get branchIndex => kDestinations.indexOf(this);

  Key get navKey => Key('nav-$id');
}

const home = AppDestination(
  id: 'home',
  label: 'Home',
  path: '/',
  icon: Icons.space_dashboard_outlined,
  selectedIcon: Icons.space_dashboard_rounded,
);
const courses = AppDestination(
  id: 'courses',
  label: 'Courses',
  path: '/courses',
  icon: Icons.menu_book_outlined,
  selectedIcon: Icons.menu_book_rounded,
);
const calendar = AppDestination(
  id: 'calendar',
  label: 'Calendar',
  path: '/calendar',
  icon: Icons.calendar_month_outlined,
  selectedIcon: Icons.calendar_month_rounded,
);
const chat = AppDestination(
  id: 'chat',
  label: 'Chat',
  path: '/chat',
  icon: Icons.chat_bubble_outline_rounded,
  selectedIcon: Icons.chat_bubble_rounded,
);
const integrity = AppDestination(
  id: 'integrity',
  label: 'Integrity',
  path: '/integrity',
  icon: Icons.verified_user_outlined,
  selectedIcon: Icons.verified_user_rounded,
);
const attendance = AppDestination(
  id: 'attendance',
  label: 'Attendance',
  path: '/attendance',
  icon: Icons.fact_check_outlined,
  selectedIcon: Icons.fact_check_rounded,
);
const students = AppDestination(
  id: 'students',
  label: 'Students',
  path: '/students',
  icon: Icons.groups_outlined,
  selectedIcon: Icons.groups_rounded,
);
const departments = AppDestination(
  id: 'departments',
  label: 'Departments',
  path: '/departments',
  icon: Icons.account_tree_outlined,
  selectedIcon: Icons.account_tree_rounded,
);
const notes = AppDestination(
  id: 'notes',
  label: 'Notes',
  path: '/notes',
  icon: Icons.sticky_note_2_outlined,
  selectedIcon: Icons.sticky_note_2_rounded,
);
const profile = AppDestination(
  id: 'profile',
  label: 'Profile',
  path: '/profile',
  icon: Icons.person_outline_rounded,
  selectedIcon: Icons.person_rounded,
);

/// Branch order for the shell route. Do not reorder without updating router.dart.
const List<AppDestination> kDestinations = [
  home,
  courses,
  calendar,
  chat,
  integrity,
  attendance,
  students,
  departments,
  notes,
  profile,
];

/// What a role sees: up to four primary tabs, the rest under "More".
class RoleNav {
  const RoleNav({required this.primary, required this.more});

  final List<AppDestination> primary;
  final List<AppDestination> more;

  List<AppDestination> get all => [...primary, ...more];
}

RoleNav navForRole(String? role) => switch (role) {
      'admin' => const RoleNav(
          primary: [home, students, departments, attendance],
          more: [courses, calendar, chat, notes, integrity, profile],
        ),
      'teacher' => const RoleNav(
          primary: [home, courses, attendance, chat],
          more: [calendar, integrity, students, notes, profile],
        ),
      _ => const RoleNav(
          primary: [home, courses, calendar, chat],
          more: [integrity, attendance, notes, profile],
        ),
    };

/// Path prefixes restricted to certain roles. Anything not listed is open to
/// every signed-in user.
const Map<String, Set<String>> kRoleGuards = {
  '/departments': {'admin'},
  '/students': {'admin', 'teacher'},
  '/attendance/mark': {'admin', 'teacher'},
};

bool canAccess(String? role, String location) {
  for (final entry in kRoleGuards.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return role != null && entry.value.contains(role);
    }
  }
  return true;
}
