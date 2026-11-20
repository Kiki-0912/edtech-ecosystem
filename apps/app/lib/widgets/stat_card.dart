import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'animated_number.dart';

/// NOIR FLAME stat card.
///
/// Pure black body with a 3 px orange left border. Number in giant orange bold
/// type. Title in small spaced-caps. Icon in a top-right outlined circle.
/// Tap triggers a spring scale animation.
class StatCard extends StatefulWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard>
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
        0.93,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOutCubic,
      );

  void _release() => _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 560),
        curve: Curves.elasticOut,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final subtitleColor = isDark ? const Color(0xFF9A9A9A) : const Color(0xFF666666);

    return GestureDetector(
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: ScaleTransition(
        scale: _controller,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardBg,
            // No left-side radius — sharp left edge for the border stripe.
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            border: Border(
              left: BorderSide(color: kOrange500, width: 3),
              top: BorderSide(
                color: isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8),
              ),
              right: BorderSide(
                color: isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8),
              ),
              bottom: BorderSide(
                color: isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8),
              ),
            ),
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
          child: Stack(
            children: [
              // ── Top-right icon circle ──────────────────────────────────
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kOrange500.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(widget.icon, size: 16, color: kOrange500),
                  ),
                ),
              ),

              // ── Main content ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 50, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Giant orange number
                    AnimatedNumber(
                      value: widget.value,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: kOrange500,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Spaced-caps title
                    Text(
                      widget.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: subtitleColor,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
