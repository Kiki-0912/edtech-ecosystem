import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Effort scores across every course: one row per student and assignment,
/// newest first, optionally only the flagged ones.
class AdminIntegrityScreen extends StatefulWidget {
  const AdminIntegrityScreen({super.key});

  @override
  State<AdminIntegrityScreen> createState() => _AdminIntegrityScreenState();
}

class _AdminIntegrityScreenState extends State<AdminIntegrityScreen> {
  List<IntegrityRow> _rows = const [];
  bool _flaggedOnly = false;
  bool _loading = true;
  bool _loaded = false;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = !_loaded;
      _error = null;
    });
    try {
      final rows =
          await ApiService.instance.adminIntegrity(flaggedOnly: _flaggedOnly);
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows..sort((a, b) => b.computedAt.compareTo(a.computedAt));
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flagged = _rows.where((r) => r.isFlagged).length;
    return AppPage(
      title: 'Integrity',
      subtitle: _loaded
          ? '${_rows.length} ${_rows.length == 1 ? 'report' : 'reports'} · '
              '$flagged flagged'
          : 'Effort scores and flags across every course',
      onRefresh: _load,
      children: [
        FilterChips<bool>(
          key: const Key('integrity-filter'),
          options: const [
            FilterOption(false, 'All reports'),
            FilterOption(true, 'Flagged only'),
          ],
          selected: _flaggedOnly,
          onSelected: (v) {
            setState(() => _flaggedOnly = v);
            _load();
          },
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: _rows.isEmpty,
          empty: EmptyState(
            icon: Icons.verified_user_outlined,
            title: _flaggedOnly ? 'Nothing flagged' : 'No reports yet',
            message: _flaggedOnly
                ? 'No effort report has an integrity flag.'
                : 'Reports appear once students submit with the extension.',
          ),
          builder: (_) => AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) ...[
                  if (i > 0) const Divider(),
                  _IntegrityRowTile(row: _rows[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Tone scoreTone(num score) {
  if (score >= 75) return Tone.success;
  if (score >= 50) return Tone.warning;
  return Tone.danger;
}

class _IntegrityRowTile extends StatelessWidget {
  const _IntegrityRowTile({required this.row});

  final IntegrityRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = scoreTone(row.score);
    final when = row.computedAt.toLocal();
    return Padding(
      key: Key('integrity-row-${row.studentId}-${row.assignmentId}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: c.bg(tone), borderRadius: AppRadius.mdAll),
            child: Text(
              row.score.round().toString(),
              style: context.text.titleMedium?.copyWith(color: c.fg(tone)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.studentName,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  [row.assignmentTitle, row.courseTitle]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: context.text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (row.isFlagged)
                      for (final f in row.flags.where((f) => f != 'none'))
                        StatusBadge(
                          label: f.replaceAll('_', ' '),
                          tone: Tone.warning,
                          icon: Icons.flag_rounded,
                        )
                    else
                      const StatusBadge(
                        label: 'No flags',
                        tone: Tone.success,
                        icon: Icons.verified_rounded,
                      ),
                    Text('${shortDate(when)} · ${clockTime(when)}',
                        style: context.text.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
