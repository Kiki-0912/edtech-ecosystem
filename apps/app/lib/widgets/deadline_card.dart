import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// NOIR FLAME deadline card.
///
/// Left edge = 4 px solid orange line.
/// Card body is `Color(0xFF1A1A1A)` (dark) or white (light).
/// Event kind chip floats in the top-right as an orange pill with white text.
/// Date displayed in large bold orange. Title in white/black.
/// Spring press animation on tap.
class DeadlineCard extends StatefulWidget {
  final CalendarEvent event;
  final VoidCallback? onTap;

  const DeadlineCard({super.key, required this.event, this.onTap});

  @override
  State<DeadlineCard> createState() => _DeadlineCardState();
}

class _DeadlineCardState extends State<DeadlineCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1.0,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() => _controller.animateTo(
        0.95,
        duration: const Duration(milliseconds: 75),
        curve: Curves.easeOutCubic,
      );

  void _release() => _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 560),
        curve: Curves.elasticOut,
      );

  String _relative(DateTime start) {
    final days = start.difference(DateTime.now()).inDays;
    if (days < -1) return '${-days}d ago';
    if (days < 0) return 'yesterday';
    if (days == 0) return 'today!';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0A0A0A);
    final subtitleColor = isDark ? const Color(0xFF9A9A9A) : const Color(0xFF666666);
    final borderColor = isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8);

    final relative = _relative(widget.event.startsAt);
    final dateStr =
        '${widget.event.startsAt.day} / ${widget.event.startsAt.month}';

    // Capitalise the kind label
    final kindLabel = widget.event.kind[0].toUpperCase() +
        widget.event.kind.substring(1).toLowerCase();

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: ScaleTransition(
        scale: _controller,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: kOrange500.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 4 px orange left edge ─────────────────────────────────
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: kOrange500,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),

                // ── Card body ─────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: date + kind chip
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date — large bold orange
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: kOrange500,
                                letterSpacing: -0.5,
                                height: 1,
                              ),
                            ),
                            const Spacer(),
                            // Kind pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: kOrange500,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: kOrange500.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                kindLabel,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Title
                        Text(
                          widget.event.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            height: 1.3,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Source / relative timing
                        Row(
                          children: [
                            Text(
                              widget.event.courseId ?? 'Institution',
                              style: TextStyle(
                                fontSize: 11,
                                color: subtitleColor,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '·',
                                style: TextStyle(color: subtitleColor),
                              ),
                            ),
                            Text(
                              relative,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kOrange500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
