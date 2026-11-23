import 'package:material_ui/material_ui.dart';

/// One section of the admin console. Its position in [kAdminDestinations] is
/// its `StatefulShellRoute` branch index, so the order must match
/// `admin_router.dart`.
class AdminDestination {
  const AdminDestination({
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

  int get branchIndex => kAdminDestinations.indexOf(this);

  Key get navKey => Key('nav-$id');
}

const adminOverview = AdminDestination(
  id: 'overview',
  label: 'Overview',
  path: '/',
  icon: Icons.space_dashboard_outlined,
  selectedIcon: Icons.space_dashboard_rounded,
);
const adminUsers = AdminDestination(
  id: 'users',
  label: 'Users',
  path: '/users',
  icon: Icons.manage_accounts_outlined,
  selectedIcon: Icons.manage_accounts_rounded,
);
const adminCourses = AdminDestination(
  id: 'courses',
  label: 'Courses',
  path: '/courses',
  icon: Icons.menu_book_outlined,
  selectedIcon: Icons.menu_book_rounded,
);
const adminDepartments = AdminDestination(
  id: 'departments',
  label: 'Departments',
  path: '/departments',
  icon: Icons.account_tree_outlined,
  selectedIcon: Icons.account_tree_rounded,
);
const adminCalendar = AdminDestination(
  id: 'calendar',
  label: 'Calendar',
  path: '/calendar',
  icon: Icons.calendar_month_outlined,
  selectedIcon: Icons.calendar_month_rounded,
);
const adminAttendance = AdminDestination(
  id: 'attendance',
  label: 'Attendance',
  path: '/attendance',
  icon: Icons.fact_check_outlined,
  selectedIcon: Icons.fact_check_rounded,
);
const adminNotes = AdminDestination(
  id: 'notes',
  label: 'Notes',
  path: '/notes',
  icon: Icons.sticky_note_2_outlined,
  selectedIcon: Icons.sticky_note_2_rounded,
);
const adminImportExport = AdminDestination(
  id: 'import-export',
  label: 'Import/Export',
  path: '/import-export',
  icon: Icons.import_export_rounded,
  selectedIcon: Icons.import_export_rounded,
);
const adminIntegrity = AdminDestination(
  id: 'integrity',
  label: 'Integrity',
  path: '/integrity',
  icon: Icons.verified_user_outlined,
  selectedIcon: Icons.verified_user_rounded,
);

/// Branch order for the admin shell route. Do not reorder without updating
/// admin_router.dart.
const List<AdminDestination> kAdminDestinations = [
  adminOverview,
  adminUsers,
  adminCourses,
  adminDepartments,
  adminCalendar,
  adminAttendance,
  adminNotes,
  adminImportExport,
  adminIntegrity,
];

/// Tabs in the phone bottom bar; the rest open from "More".
const int kAdminPrimaryCount = 4;

List<AdminDestination> get adminPrimary =>
    kAdminDestinations.take(kAdminPrimaryCount).toList();

List<AdminDestination> get adminMore =>
    kAdminDestinations.skip(kAdminPrimaryCount).toList();
