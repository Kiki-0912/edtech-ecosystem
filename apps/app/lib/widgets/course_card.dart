import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// NOIR FLAME course card.
///
/// Dramatic black body with an orange diagonal stripe painted in the top-right
/// corner via [CustomPaint]. 2-letter monogram in orange replaces the emoji.
/// Stats as tiny white-on-orange pills. Full spring press animation.
class CourseCard extends StatefulWidget {
  final String code;
  final String title;
  final String teacher;
  final int students;
  final int assignments;

  const CourseCard({
    super.key,
    required this.code,
    required this.title,
    required this.teacher,
    required this.students,
    required this.assignments,
  });

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1.0,
    duration: const Duration(milliseconds: 280),
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
        duration: const Duration(milliseconds: 540),
        curve: Curves.elasticOut,
      );

  /// First 2 letters of the course code (or initials of the title).
  String get _monogram {
    final parts = widget.code.trim().split(RegExp(r'[\s\-_]+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final code = widget.code.replaceAll(RegExp(r'[0-9]'), '').trim();
    return code.length >= 2
        ? code.substring(0, 2).toUpperCase()
        : code.toUpperCase().padRight(2, '•');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0A0A0A);
    final subtitleColor = isDark ? const Color(0xFF9A9A9A) : const Color(0xFF666666);
    final borderColor = isDark ? const Color(0xFF282828) : const Color(0xFFE8E8E8);

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
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: kOrange500.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Orange diagonal stripe (top-right corner) ───────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: _DiagonalStripePainter(),
                ),
              ),

              // ── Card content ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: code chip + monogram badge
                    Row(
                      children: [
                        // Code chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: kOrange500.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kOrange500.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            widget.code,
                            style: TextStyle(
                              color: kOrange500,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 2-letter monogram
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: kOrange500.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kOrange500.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _monogram,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: kOrange500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Title
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Teacher
                    Row(
                      children: [
                        Icon(Icons.person_rounded,
                            size: 14, color: subtitleColor),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.teacher,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Stat pills
                    Row(
                      children: [
                        _Pill(
                          icon: Icons.people_rounded,
                          label: '${widget.students} Students',
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          icon: Icons.assignment_rounded,
                          label: '${widget.assignments} Tasks',
                        ),
                      ],
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

// ── Diagonal stripe painter ────────────────────────────────────────────────

class _DiagonalStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stripeSize = 60.0;
    final paint = Paint()
      ..color = const Color(0xFFFF6B00) // kOrange500
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width - stripeSize, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, stripeSize)
      ..close();

    canvas.drawPath(path, paint);

    // A second, slightly transparent stripe for depth
    final paint2 = Paint()
      ..color = const Color(0x33FF6B00)
      ..style = PaintingStyle.fill;

    final path2 = Path()
      ..moveTo(size.width - stripeSize - 16, 0)
      ..lineTo(size.width - stripeSize, 0)
      ..lineTo(size.width, stripeSize)
      ..lineTo(size.width, stripeSize + 16)
      ..close();

    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(_DiagonalStripePainter _) => false;
}

// ── Stat pill ──────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B00), // kOrange500
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
