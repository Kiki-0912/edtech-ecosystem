import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/attachment.dart';
import 'package:edtech_app/screens/courses/course_detail_screen.dart'
    show assignmentStatus;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Assignment detail. Students submit work; staff see the class roster.
class AssignmentScreen extends StatefulWidget {
  const AssignmentScreen({
    super.key,
    required this.courseId,
    required this.assignmentId,
  });

  final String courseId;
  final String assignmentId;

  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen> {
  Assignment? _assignment;
  List<Map<String, dynamic>> _roster = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ApiService.instance;
    setState(() {
      _loading = _assignment == null;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.getAssignment(widget.assignmentId),
        api.getRoster(widget.assignmentId),
      ]);
      if (!mounted) return;
      setState(() {
        _assignment = results[0] as Assignment;
        _roster = results[1] as List<Map<String, dynamic>>;
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
    final user = context.watch<AuthProvider>().user;
    final a = _assignment;

    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.go('/courses/${widget.courseId}'),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text('Back to course'),
      ),
    );

    if (a == null) {
      return AppPage(title: 'Assignment', children: [
        back,
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: false,
          builder: (_) => const SizedBox.shrink(),
        ),
      ]);
    }

    final (statusLabel, statusTone) = assignmentStatus(a);
    final mine = _roster.where((r) => r['studentId'] == user?.id).firstOrNull;

    return AppPage(
      title: a.title,
      subtitle: 'Due ${shortDate(a.dueAt)} at ${clockTime(a.dueAt)}',
      onRefresh: _load,
      actions: [StatusBadge(label: statusLabel, tone: statusTone)],
      children: [
        back,
        SectionCard(
          title: 'Brief',
          child: Text(a.brief.isEmpty ? 'No description provided.' : a.brief,
              style: context.text.bodyLarge),
        ),
        if (user?.isStudent == true)
          _SubmissionCard(
            assignment: a,
            studentId: user!.id,
            current: mine,
            onSubmitted: _load,
          )
        else
          _RosterCard(
            roster: _roster,
            assignmentId: a.id,
          ),
      ],
    );
  }
}

Tone submissionTone(String? status) => switch (status) {
      'submitted' => Tone.success,
      'late' => Tone.warning,
      'pending' => Tone.info,
      _ => Tone.danger,
    };

String submissionLabel(String? status) => switch (status) {
      'submitted' => 'Submitted',
      'late' => 'Submitted late',
      'pending' => 'In progress',
      _ => 'Missing',
    };

class _SubmissionCard extends StatefulWidget {
  const _SubmissionCard({
    required this.assignment,
    required this.studentId,
    required this.current,
    required this.onSubmitted,
  });

  final Assignment assignment;
  final String studentId;
  final Map<String, dynamic>? current;
  final Future<void> Function() onSubmitted;

  @override
  State<_SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<_SubmissionCard> {
  final _link = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _link.text.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      showToast(context, 'Paste a full link, e.g. https://docs.google.com/…',
          kind: ToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService.instance.submitAssignment(
        assignmentId: widget.assignment.id,
        studentId: widget.studentId,
        attachments: [
          Attachment(
            id: 'att-${DateTime.now().microsecondsSinceEpoch}',
            fileName:
                _label.text.trim().isEmpty ? uri.host : _label.text.trim(),
            mimeType: 'text/uri-list',
            sizeBytes: 0,
            url: url,
          ),
        ],
      );
      if (!mounted) return;
      _link.clear();
      _label.clear();
      showToast(context, 'Work submitted', kind: ToastKind.success);
      await widget.onSubmitted();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.current?['status']?.toString();
    final submittedAt =
        DateTime.tryParse(widget.current?['submittedAt']?.toString() ?? '');
    final hasSubmission = status == 'submitted' || status == 'late';
    final open = widget.assignment.isOpen;

    return SectionCard(
      title: 'Your submission',
      trailing: StatusBadge(
          label: submissionLabel(status), tone: submissionTone(status)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSubmission && submittedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Handed in ${shortDate(submittedAt.toLocal())} at ${clockTime(submittedAt.toLocal())}.'
                '${open ? ' You can resubmit until the assignment closes.' : ''}',
                style: context.text.bodyMedium,
              ),
            ),
          if (!open)
            Text('This assignment is closed for submissions.',
                style: context.text.bodyMedium)
          else ...[
            TextField(
              key: const Key('submission-link'),
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link to your work',
                hintText: 'https://…',
                prefixIcon: Icon(Icons.link_rounded, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('submission-label'),
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                prefixIcon: Icon(Icons.title_rounded, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: BusyButton(
                key: const Key('submission-submit'),
                label: hasSubmission ? 'Resubmit' : 'Submit work',
                icon: Icons.upload_rounded,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.roster, required this.assignmentId});

  final List<Map<String, dynamic>> roster;
  final String assignmentId;

  @override
  Widget build(BuildContext context) {
    final handedIn = roster
        .where((r) => r['status'] == 'submitted' || r['status'] == 'late')
        .length;
    return SectionCard(
      title: 'Submissions',
      subtitle: '$handedIn of ${roster.length} handed in',
      child: roster.isEmpty
          ? const EmptyState(
              icon: Icons.groups_outlined, title: 'No students enrolled')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProgressBar(
                    value: roster.isEmpty ? 0 : handedIn / roster.length,
                    tone: Tone.success),
                const SizedBox(height: AppSpacing.sm),
                for (final r in roster)
                  ListRow(
                    key: Key('roster-${r['studentId']}'),
                    leading: Avatar(
                        name: r['displayName']?.toString() ?? '?', size: 36),
                    title: r['displayName']?.toString() ?? 'Student',
                    subtitle: r['effortScore'] != null
                        ? 'Effort score ${r['effortScore']}'
                        : null,
                    trailing: StatusBadge(
                      label: submissionLabel(r['status']?.toString()),
                      tone: submissionTone(r['status']?.toString()),
                    ),
                    onTap: () => context.go(
                        '/integrity?assignment=$assignmentId&student=${r['studentId']}'),
                  ),
              ],
            ),
    );
  }
}
