import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/effort_report.dart';
import 'package:edtech_app/models/user.dart';
import 'package:edtech_app/screens/courses/assignment_screen.dart'
    show submissionLabel;
import 'package:edtech_app/screens/home/home_data.dart' show myCourses;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Process-based integrity insights.
///
/// Students see their own effort report per assignment. Teachers and admins
/// pick an assignment, see the class roster with effort scores, and drill
/// into a student's report. `?assignment=&student=` deep-link from rosters.
class IntegrityScreen extends StatefulWidget {
  const IntegrityScreen({super.key, this.assignmentId, this.studentId});

  final String? assignmentId;
  final String? studentId;

  @override
  State<IntegrityScreen> createState() => _IntegrityScreenState();
}

class _IntegrityScreenState extends State<IntegrityScreen> {
  List<(Assignment, Course)> _assignments = const [];
  String? _assignmentId;
  String? _studentId;

  bool _loading = true;
  Object? _error;

  // Detail state for the selected assignment.
  bool _detailLoading = false;
  IntegrityReport? _report;
  List<Map<String, dynamic>> _roster = const [];
  bool _sending = false;

  User? get _user => context.read<AuthProvider>().user;
  bool get _isStaff => _user != null && !_user!.isStudent;

  /// Whose report is shown: self for students, the chosen student for staff.
  String? get _subjectId => _isStaff ? _studentId : _user?.id;

  @override
  void initState() {
    super.initState();
    _assignmentId = widget.assignmentId;
    _studentId = widget.studentId;
    _load();
  }

  @override
  void didUpdateWidget(IntegrityScreen old) {
    super.didUpdateWidget(old);
    if (old.assignmentId != widget.assignmentId ||
        old.studentId != widget.studentId) {
      _assignmentId = widget.assignmentId ?? _assignmentId;
      _studentId = widget.studentId;
      _loadDetail();
    }
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) return;
    final api = ApiService.instance;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final courses = myCourses(user, await api.getCourses());
      final perCourse = await Future.wait(courses.map(
          (c) => api.getAssignments(c.id).catchError((_) => <Assignment>[])));
      final list = <(Assignment, Course)>[
        for (var i = 0; i < courses.length; i++)
          for (final a in perCourse[i])
            if (a.status != 'draft') (a, courses[i]),
      ]..sort((x, y) => x.$1.dueAt.compareTo(y.$1.dueAt));
      if (!mounted) return;
      setState(() {
        _assignments = list;
        _loading = false;
        if (_assignmentId == null ||
            !list.any((p) => p.$1.id == _assignmentId)) {
          _assignmentId = list.isEmpty ? null : list.first.$1.id;
        }
      });
      await _loadDetail();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadDetail() async {
    final assignmentId = _assignmentId;
    if (assignmentId == null) return;
    final api = ApiService.instance;
    setState(() {
      _detailLoading = true;
      _report = null;
    });
    try {
      final subject = _subjectId;
      final results = await Future.wait([
        subject == null
            ? Future<IntegrityReport?>.value(null)
            : api.getIntegrityReportOrNull(assignmentId, subject),
        _isStaff
            ? api.getRoster(assignmentId)
            : Future.value(const <Map<String, dynamic>>[]),
      ]);
      if (!mounted || assignmentId != _assignmentId) return;
      setState(() {
        _report = results[0] as IntegrityReport?;
        _roster = results[1] as List<Map<String, dynamic>>;
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailLoading = false;
        _error = e;
      });
    }
  }

  void _selectAssignment(String id) {
    setState(() {
      _assignmentId = id;
      _studentId = null;
    });
    _loadDetail();
  }

  void _selectStudent(String? id) {
    setState(() => _studentId = id);
    _loadDetail();
  }

  (Assignment, Course)? get _selected =>
      _assignments.where((p) => p.$1.id == _assignmentId).firstOrNull;

  Future<void> _askForReview() async {
    final sel = _selected;
    final user = _user;
    if (sel == null || user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final score = _report?.effortScore.score;
      final channel = await ApiService.instance.messageCourseChannel(
        courseId: sel.$2.id,
        authorId: user.id,
        body: 'Please review my integrity report for "${sel.$1.title}"'
            '${score != null ? ' (effort score $score/100)' : ''}.',
      );
      if (mounted) {
        showToast(context, 'Request sent to #$channel',
            kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Could not send: ${friendlyError(e)}',
            kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final staff = user != null && !user.isStudent;
    final sel = _selected;
    final studentName = _roster
        .where((r) => r['studentId'] == _studentId)
        .map((r) => r['displayName']?.toString())
        .firstOrNull;

    return AppPage(
      title: 'Integrity',
      subtitle: staff
          ? 'Effort insights for your classes'
          : 'How your writing process looks to your teachers',
      onRefresh: _load,
      children: [
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: _assignments.isEmpty,
          empty: const EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No assignments yet',
            message: 'Integrity reports appear once you have assignments.',
          ),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AssignmentPicker(
                items: _assignments,
                selectedId: _assignmentId,
                onChanged: _selectAssignment,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_detailLoading)
                const SkeletonList(count: 2, itemHeight: 140)
              else if (staff && _studentId == null)
                _RosterView(roster: _roster, onSelect: _selectStudent)
              else ...[
                if (staff)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('integrity-back-roster'),
                      onPressed: () => _selectStudent(null),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(studentName == null
                          ? 'Back to class'
                          : 'Back to class · $studentName'),
                    ),
                  ),
                if (_report == null)
                  _NoReport(staff: staff)
                else
                  _ReportView(report: _report!),
                if (!staff && sel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ReviewRequest(sending: _sending, onPressed: _askForReview),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              const _PrivacyNote(),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignmentPicker extends StatelessWidget {
  const _AssignmentPicker({
    required this.items,
    required this.selectedId,
    required this.onChanged,
  });

  final List<(Assignment, Course)> items;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('integrity-assignment'),
      initialValue: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assignment',
        prefixIcon: Icon(Icons.assignment_outlined, size: 20),
      ),
      items: [
        for (final (a, c) in items)
          DropdownMenuItem(
            value: a.id,
            child:
                Text('${c.code} · ${a.title}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _RosterView extends StatelessWidget {
  const _RosterView({required this.roster, required this.onSelect});

  final List<Map<String, dynamic>> roster;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (roster.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined, title: 'No students enrolled');
    }
    final scored = roster.where((r) => r['effortScore'] is num).toList();
    final avg = scored.isEmpty
        ? null
        : scored.fold<num>(0, (s, r) => s + (r['effortScore'] as num)) /
            scored.length;
    return SectionCard(
      title: 'Class overview',
      subtitle: avg == null
          ? 'No effort data yet'
          : 'Average effort ${avg.round()} across ${scored.length} reports',
      child: Column(
        children: [
          for (final (i, r) in roster.indexed)
            FadeSlideIn(
                delay: AppMotion.delayFor(i),
                offset: 8,
                child: ListRow(
                  key: Key('integrity-student-${r['studentId']}'),
                  leading: Avatar(name: r['displayName']?.toString() ?? '?'),
                  title: r['displayName']?.toString() ?? 'Student',
                  subtitle: submissionLabel(r['status']?.toString()),
                  trailing: r['effortScore'] is num
                      ? StatusBadge(
                          label: 'Effort ${r['effortScore']}',
                          tone: effortTone((r['effortScore'] as num).toInt()),
                        )
                      : const StatusBadge(label: 'No data'),
                  onTap: () => onSelect(r['studentId'].toString()),
                )),
        ],
      ),
    );
  }
}

Tone effortTone(int score) => score >= 75
    ? Tone.success
    : score >= 50
        ? Tone.warning
        : Tone.danger;

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final IntegrityReport report;

  bool get _flagged => report.flags.any((f) => f != 'none');

  @override
  Widget build(BuildContext context) {
    final e = report.effortScore;
    final tone = effortTone(e.score);

    final scoreCard = AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          ProgressRing(
            value: e.score / 100,
            label: '${e.score}',
            caption: 'of 100 · ${e.scoreLabel}',
            tone: tone,
            size: 150,
          ),
          const SizedBox(height: AppSpacing.md),
          StatusBadge(
            label: _flagged ? 'Flagged for review' : 'No concerns',
            icon: _flagged ? Icons.flag_rounded : Icons.verified_rounded,
            tone: _flagged ? Tone.warning : Tone.success,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Updated ${shortDate(report.generatedAt.toLocal())}',
              style: context.text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text('A signal to start a conversation, not a verdict.',
              textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
      ),
    );

    final metrics = SectionCard(
      title: 'Session',
      child: Column(
        children: [
          _Metric(
            icon: Icons.keyboard_rounded,
            tone: Tone.info,
            title:
                '${grouped(e.keystrokes)} keystrokes typed over ${durationLabel(e.activeSeconds)}',
            subtitle: 'Typing cadence only — never what was typed.',
          ),
          _Metric(
            icon: Icons.content_paste_rounded,
            tone: e.pastes > 0 && _flagged ? Tone.warning : Tone.neutral,
            title:
                '${grouped(e.pasteVolume)} characters pasted in ${e.pastes} ${e.pastes == 1 ? 'paste event' : 'paste events'}',
            badge: _flagged && e.pastes > 0 ? 'Flagged' : null,
          ),
          _Metric(
            icon: Icons.tab_rounded,
            tone: e.aiTabSwitches > 0 ? Tone.warning : Tone.neutral,
            title:
                '${e.aiTabSwitches} ${e.aiTabSwitches == 1 ? 'AI tab switch' : 'AI tab switches'}',
            subtitle: 'Visits to supported AI assistants while writing.',
          ),
        ],
      ),
    );

    final flags = SectionCard(
      title: 'Flags',
      child: _flagged
          ? Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final f in report.flags.where((f) => f != 'none'))
                  StatusBadge(
                    label: f.replaceAll('_', ' '),
                    tone: Tone.warning,
                    icon: Icons.flag_rounded,
                  ),
              ],
            )
          : Text('No integrity flags raised on this session.',
              style: context.text.bodyMedium),
    );

    return TwoPane(
      primaryFlex: 2,
      secondaryFlex: 3,
      primary: scoreCard,
      secondary: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [metrics, const SizedBox(height: AppSpacing.lg), flags],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.badge,
  });

  final IconData icon;
  final Tone tone;
  final String title;
  final String? subtitle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, tone: tone, size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                if (subtitle != null)
                  Text(subtitle!, style: context.text.bodySmall),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.xs),
            StatusBadge(label: badge!, tone: Tone.warning),
          ],
        ],
      ),
    );
  }
}

class _NoReport extends StatelessWidget {
  const _NoReport({required this.staff});

  final bool staff;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('integrity-empty'),
      child: EmptyState(
        icon: Icons.edit_note_rounded,
        title: 'No writing sessions yet',
        message: staff
            ? 'This student hasn\'t recorded a session for this assignment.'
            : 'Turn on Integrity Lens in your browser while you write and your '
                'effort report will appear here.',
      ),
    );
  }
}

class _ReviewRequest extends StatelessWidget {
  const _ReviewRequest({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Row(
      children: [
        const IconBadge(icon: Icons.forum_outlined, tone: Tone.info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Think something looks off?',
                  style: context.text.titleSmall),
              Text('Ask your teacher to review this report in class chat.',
                  style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
    final button = BusyButton(
      key: const Key('integrity-ask-review'),
      label: 'Ask teacher to review',
      busy: sending,
      onPressed: onPressed,
    );
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: AppSpacing.sm), button],
              )
            : Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: AppSpacing.sm),
                  button,
                ],
              ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.infoSoft,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: c.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Integrity Lens records only process signals — typing rhythm, paste '
              'counts and visits to AI sites — after you give consent. It never '
              'records what you type, passwords or hidden fields.',
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
