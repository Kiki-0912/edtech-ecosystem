import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/effort_report.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Integrity — the effort score for the first open assignment, the three
/// telemetry metrics behind it, and a session strip. Layout follows the Sleek
/// design; every number is read from the real `IntegrityReport`.
class IntegrityScreen extends StatefulWidget {
  const IntegrityScreen({super.key});

  @override
  State<IntegrityScreen> createState() => _IntegrityScreenState();
}

class _IntegrityScreenState extends State<IntegrityScreen> {
  IntegrityReport? _report;
  Assignment? _assignment;
  String? _courseTitle;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final userId = context.read<AuthProvider>().user?.id ?? 'u-student-1';

    try {
      final courses = await ApiService.instance.getCourses();
      if (courses.isEmpty) {
        throw Exception('No courses available for your account');
      }

      final assignments =
          await ApiService.instance.getAssignments(courses.first.id);
      final openAssignments =
          assignments.where((item) => item.status != 'draft').toList();
      if (openAssignments.isEmpty) {
        throw Exception('No open assignments to review');
      }

      final assignment = openAssignments.first;
      final report =
          await ApiService.instance.getIntegrityReportOrNull(assignment.id, userId);

      if (!mounted) return;
      setState(() {
        _assignment = assignment;
        _courseTitle = _titleFor(courses, assignment.courseId);
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String? _titleFor(List<Course> courses, String courseId) {
    for (final course in courses) {
      if (course.id == courseId) return course.title;
    }
    return null;
  }

  /// Posts the review request to the assignment's course channel.
  Future<void> _askForReview() async {
    if (_assignment == null || _sending) return;
    setState(() => _sending = true);
    try {
      final userId = context.read<AuthProvider>().user?.id ?? 'u-student-1';
      final score = _report?.effortScore.score;
      final channel = await ApiService.instance.messageCourseChannel(
        courseId: _assignment!.courseId,
        authorId: userId,
        body: 'Please review my integrity report for "${_assignment!.title}"'
            '${score != null ? ' (effort score $score/100)' : ''}.',
      );
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Request sent to $channel', kPrimary),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Could not send: $e', kTextPrimary),
      );
    }
  }

  SnackBar _snack(String text, Color color) => SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(kSpaceMd),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
      );

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      backgroundColor: kBackground,
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: kPrimary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceLg,
                  vertical: kSpaceMd,
                ),
                children: [
                  _Header(
                    eyebrow: _assignment == null
                        ? 'Effort & authenticity'
                        : '${_assignment!.title}'
                            '${_courseTitle != null ? ' · $_courseTitle' : ''}',
                    onRefresh: _load,
                  ),
                  const SizedBox(height: kSpaceLg),
                  if (_loading)
                    const _ReportSkeleton()
                  else if (_error != null)
                    _ErrorState(error: _error!, onRetry: _load)
                  else if (report == null)
                    _EmptyState(
                      assignmentTitle: _assignment?.title ?? 'this assignment',
                    )
                  else ...[
                    Center(
                      child: _ScoreRing(
                        score: report.effortScore.score,
                        caption: 'of 100 · ${report.effortScore.scoreLabel}',
                      ),
                    ),
                    const SizedBox(height: kSpaceLg),
                    _MetricList(report: report),
                    const SizedBox(height: kSpaceXl),
                    _SessionSection(report: report),
                    const SizedBox(height: kSpaceLg),
                    _FlagLine(flags: report.flags),
                  ],
                  const SizedBox(height: kSpaceXl),
                ],
              ),
            ),
          ),
          if (!_loading && _error == null && report != null)
            _ReviewBar(sending: _sending, onAsk: _askForReview),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String eyebrow;
  final VoidCallback onRefresh;

  const _Header({required this.eyebrow, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.overline.copyWith(letterSpacing: 1.1),
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                'Integrity',
                style: TextStyle(
                  fontSize: 44,
                  height: 1.05,
                  letterSpacing: -1.2,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: kSpaceSm),
        Tooltip(
          message: 'Refresh report',
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kCard,
              shape: BoxShape.circle,
              border: Border.all(color: kBorder),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: kTextPrimary,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRefresh,
            ),
          ),
        ),
      ],
    );
  }
}

/// Big score ring: orange progress on a light track with the score set in the
/// app's near-black display type.
class _ScoreRing extends StatelessWidget {
  final int score;
  final String caption;

  const _ScoreRing({required this.score, required this.caption});

  static const double _size = 224;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: score / 100),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => SizedBox(
              width: _size,
              height: _size,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 14,
                backgroundColor: kDivider,
                strokeCap: StrokeCap.round,
                color: kPrimary,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 64,
                  height: 1,
                  letterSpacing: -2.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                caption,
                style: context.body2.copyWith(color: kTextSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The three telemetry rows from the design, each fed by the real effort score.
class _MetricList extends StatelessWidget {
  final IntegrityReport report;
  const _MetricList({required this.report});

  /// Any real flag means the session is flagged; `none` is the API's explicit
  /// "nothing to see here" value and must not raise the chip.
  bool get _isFlagged =>
      report.flags.isNotEmpty && report.flags.any((flag) => flag != 'none');

  @override
  Widget build(BuildContext context) {
    final effort = report.effortScore;
    final flagged = _isFlagged;

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _MetricRow(
            bubble: tintOf(kPrimary, 0.10),
            body: TextSpan(children: [
              _bold(grouped(effort.keystrokes)),
              const TextSpan(text: ' keystrokes typed over '),
              _bold(durationLabel(effort.activeSeconds)),
            ]),
            child: const Icon(Icons.keyboard_rounded, color: kPrimary, size: 20),
          ),
          Divider(height: 1, color: kDivider),
          _MetricRow(
            bubble: tintOf(kAccent, 0.28),
            chip: flagged ? 'Flagged' : null,
            body: TextSpan(children: [
              _bold(grouped(effort.pasteVolume)),
              const TextSpan(text: ' characters pasted in '),
              _bold('${effort.pastes}'),
              TextSpan(text: effort.pastes == 1 ? ' paste event' : ' paste events'),
            ]),
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
            ),
          ),
          Divider(height: 1, color: kDivider),
          _MetricRow(
            bubble: tintOf(kPrimary, 0.10),
            body: TextSpan(children: [
              _bold('${effort.aiTabSwitches}'),
              TextSpan(
                text: effort.aiTabSwitches == 1
                    ? ' AI tab switch'
                    : ' AI tab switches',
              ),
            ]),
            child: const Icon(Icons.tab_rounded, color: kPrimary, size: 20),
          ),
        ],
      ),
    );
  }

  static TextSpan _bold(String text) => TextSpan(
        text: text,
        style: TextStyle(fontWeight: FontWeight.w800, color: kTextPrimary),
      );
}

class _MetricRow extends StatelessWidget {
  final Color bubble;
  final Widget child;
  final TextSpan body;
  final String? chip;

  const _MetricRow({
    required this.bubble,
    required this.child,
    required this.body,
    this.chip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bubble, shape: BoxShape.circle),
            child: Center(child: child),
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: context.body2.copyWith(color: kTextBody),
                    children: [body],
                  ),
                ),
                if (chip != null) ...[
                  const SizedBox(height: kSpaceSm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: tintOf(kAccent, 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded, size: 14, color: kTextPrimary),
                        const SizedBox(width: 6),
                        Text(
                          chip!,
                          style: context.body2.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSection extends StatelessWidget {
  final IntegrityReport report;
  const _SessionSection({required this.report});

  @override
  Widget build(BuildContext context) {
    final effort = report.effortScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Session',
              style: context.h2.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: kTextPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${durationLabel(effort.activeSeconds)} active',
              style: context.body2.copyWith(
                color: kTextSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: kSpaceMd),
        const _SessionWave(),
        const SizedBox(height: kSpaceMd),
        Container(
          padding: const EdgeInsets.all(kSpaceMd),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session totals'.toUpperCase(),
                style: context.overline.copyWith(letterSpacing: 1.1),
              ),
              const SizedBox(height: 4),
              Text(
                '${grouped(effort.keystrokes)} keystrokes · '
                '${grouped(effort.pastes)} pastes · '
                '${effort.aiTabSwitches} AI switches',
                style: context.h5.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                'Per-event timing is not stored yet, so the design\'s '
                'individual markers have nothing real to plot.',
                style: context.body2.copyWith(
                  color: kTextSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Decorative wave texture standing in for the mockup's writing timeline.
class _SessionWave extends StatelessWidget {
  const _SessionWave();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tintOf(kPrimary, 0.05),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _WavePainter(tintOf(kPrimary, 0.35)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  const _WavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < 5; i++) {
      final y = 8.0 + i * 12;
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(size.width * 0.2, y - 5, size.width * 0.35, y + 5, size.width * 0.5, y)
        ..cubicTo(size.width * 0.65, y - 5, size.width * 0.8, y + 5, size.width, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FlagLine extends StatelessWidget {
  final List<String> flags;
  const _FlagLine({required this.flags});

  @override
  Widget build(BuildContext context) {
    final flagged = flags.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          flagged ? Icons.flag_rounded : Icons.verified_outlined,
          size: 20,
          color: flagged ? kTextSecondary : kPrimary,
        ),
        const SizedBox(width: kSpaceSm),
        Expanded(
          child: Text(
            flagged
                ? 'Flagged for review: '
                    '${flags.join(', ').replaceAll('_', ' ')}.'
                : 'No integrity flags raised on this session.',
            style: context.body2.copyWith(color: kTextPrimary),
          ),
        ),
      ],
    );
  }
}

/// Pinned bar: the privacy promise plus the review request action.
class _ReviewBar extends StatelessWidget {
  final bool sending;
  final VoidCallback onAsk;

  const _ReviewBar({required this.sending, required this.onAsk});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBackground,
        border: Border(top: BorderSide(color: kDivider)),
      ),
      padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceMd, kSpaceLg, kSpaceMd),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: kTextSecondary),
                const SizedBox(width: kSpaceSm),
                Expanded(
                  child: Text(
                    'Captured on this device, data stays local',
                    style: context.body2.copyWith(
                      fontSize: 13,
                      color: kTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpaceSm),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: sending ? null : onAsk,
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Ask teacher to review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Center(
          child: SkeletonBox(
            width: 224,
            height: 224,
            borderRadius: BorderRadius.all(Radius.circular(112)),
          ),
        ),
        SizedBox(height: kSpaceLg),
        SkeletonBox(height: 200, borderRadius: BorderRadius.all(Radius.circular(20))),
        SizedBox(height: kSpaceLg),
        SkeletonBox(height: 64, borderRadius: BorderRadius.all(Radius.circular(12))),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String assignmentTitle;
  const _EmptyState({required this.assignmentTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXxl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('✍️', style: TextStyle(fontSize: 52)),
          const SizedBox(height: kSpaceMd),
          Text(
            'No writing sessions yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: kSpaceSm),
          Text(
            'Your effort score for "$assignmentTitle" will appear once '
            'you draft with the Integrity Lens browser extension enabled.',
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, height: 1.7, fontSize: 14),
          ),
          const SizedBox(height: kSpaceLg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: tintOf(kPrimary, 0.1),
              borderRadius: BorderRadius.circular(kRadiusMd),
            ),
            child: const Text(
              'Only typing cadence, paste volume and tab activity are recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('😵', style: TextStyle(fontSize: 44)),
          const SizedBox(height: kSpaceMd),
          Text(
            error,
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: kSpaceLg),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(foregroundColor: kPrimary),
          ),
        ],
      ),
    );
  }
}
