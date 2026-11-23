import 'package:edtech_app/admin/screens/users_screen.dart'
    show adminUsersLocation;
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// System overview: record counts and storage / database status.
class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  AdminOverview? _overview;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _overview == null;
      _error = null;
    });
    try {
      final overview = await ApiService.instance.adminOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Overview',
      subtitle: 'Accounts, courses and system health',
      onRefresh: _load,
      actions: [
        OutlinedButton.icon(
          key: const Key('overview-refresh'),
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      children: [
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: _overview == null,
          builder: (_) => _OverviewBody(overview: _overview!),
        ),
      ],
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final n = overview.counts;
    String v(int value) => grouped(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'People'),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              key: const Key('overview-students'),
              label: 'Students',
              value: v(n.students),
              icon: Icons.school_outlined,
              tone: Tone.info,
              onTap: () => context.go(adminUsersLocation(role: 'student')),
            ),
            StatTile(
              key: const Key('overview-teachers'),
              label: 'Teachers',
              value: v(n.teachers),
              icon: Icons.co_present_outlined,
              tone: Tone.info,
              onTap: () => context.go(adminUsersLocation(role: 'teacher')),
            ),
            StatTile(
              key: const Key('overview-admins'),
              label: 'Admins',
              value: v(n.admins),
              icon: Icons.admin_panel_settings_outlined,
              tone: Tone.neutral,
              onTap: () => context.go(adminUsersLocation(role: 'admin')),
            ),
            StatTile(
              key: const Key('overview-inactive'),
              label: 'Inactive accounts',
              value: v(n.inactiveUsers),
              icon: Icons.person_off_outlined,
              tone: n.inactiveUsers > 0 ? Tone.warning : Tone.neutral,
              onTap: () => context.go(adminUsersLocation(status: 'inactive')),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Teaching'),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              key: const Key('overview-courses'),
              label: 'Courses',
              value: v(n.courses),
              icon: Icons.menu_book_outlined,
              tone: Tone.success,
              onTap: () => context.go('/courses'),
            ),
            StatTile(
              key: const Key('overview-departments'),
              label: 'Departments',
              value: v(n.departments),
              icon: Icons.account_tree_outlined,
              tone: Tone.success,
              onTap: () => context.go('/departments'),
            ),
            StatTile(
              key: const Key('overview-assignments'),
              label: 'Assignments',
              value: v(n.assignments),
              icon: Icons.assignment_outlined,
              tone: Tone.neutral,
            ),
            StatTile(
              key: const Key('overview-submissions'),
              label: 'Submissions',
              value: v(n.submissions),
              icon: Icons.task_alt_rounded,
              tone: Tone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Integrity'),
        ResponsiveGrid(
          minItemWidth: 200,
          children: [
            StatTile(
              key: const Key('overview-telemetry'),
              label: 'Telemetry batches',
              value: v(n.telemetryBatches),
              icon: Icons.sensors_rounded,
              tone: Tone.neutral,
            ),
            StatTile(
              key: const Key('overview-flagged'),
              label: 'Flagged reports',
              value: v(n.flaggedReports),
              icon: Icons.flag_outlined,
              tone: n.flaggedReports > 0 ? Tone.danger : Tone.success,
              onTap: () => context.go('/integrity'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SystemCard(overview: overview),
      ],
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final postgres = overview.storage == 'postgres';
    final local = overview.serverTime.toLocal();
    return SectionCard(
      key: const Key('overview-system'),
      title: 'System',
      subtitle: 'Where the API keeps its data',
      child: Column(
        children: [
          _StatusRow(
            label: 'Storage',
            value: postgres ? 'PostgreSQL' : 'In-memory',
            badge: StatusBadge(
              key: const Key('overview-storage'),
              label: postgres ? 'Persistent' : 'Resets on restart',
              tone: postgres ? Tone.success : Tone.warning,
            ),
          ),
          const Divider(),
          _StatusRow(
            label: 'Database',
            value: overview.databaseOk ? 'Reachable' : 'Unreachable',
            badge: StatusBadge(
              key: const Key('overview-database'),
              label: overview.databaseOk ? 'OK' : 'Down',
              tone: overview.databaseOk ? Tone.success : Tone.danger,
              icon: overview.databaseOk
                  ? Icons.check_rounded
                  : Icons.error_outline_rounded,
            ),
          ),
          const Divider(),
          _StatusRow(
            label: 'Schema version',
            value: overview.schemaVersion?.toString() ?? 'n/a',
          ),
          const Divider(),
          _StatusRow(
            label: 'API version',
            value: overview.version.isEmpty ? 'unknown' : overview.version,
          ),
          const Divider(),
          _StatusRow(
            label: 'Server time',
            value: '${shortDate(local)} · ${clockTime(local)}',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.badge});

  final String label;
  final String value;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              style: context.text.titleSmall,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: badge!),
          ],
        ],
      ),
    );
  }
}
