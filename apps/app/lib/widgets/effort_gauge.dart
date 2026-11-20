import 'dart:math' as math;
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// NOIR FLAME effort gauge.
///
/// A 270° arc (starting at 7 o'clock, ending at 5 o'clock) rendered with
/// [CustomPainter]. The filled arc has an orange gradient and a flame-glow at
/// its tip. A pulsing dot rides the tip. Score animates with a spring overshoot
/// using [Curves.elasticOut].
class EffortGauge extends StatefulWidget {
  final int score;

  const EffortGauge({super.key, required this.score});

  @override
  State<EffortGauge> createState() => _EffortGaugeState();
}

class _EffortGaugeState extends State<EffortGauge>
    with SingleTickerProviderStateMixin {
  // Pulsing dot controller.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Returns the two gradient colours based on score band.
  (Color, Color) _arcColors() {
    if (widget.score >= 75) return (kOrange400, kOrange500);
    if (widget.score >= 50) return (kOrange500, kOrange700);
    return (kOrange700, kOrange900);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8);
    final textColor = isDark ? Colors.white : const Color(0xFF0A0A0A);
    final (colorStart, colorEnd) = _arcColors();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: widget.score / 100),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.elasticOut,
      builder: (context, progress, _) {
        final clamped = progress.clamp(0.0, 1.0);

        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Arc painter ─────────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(200, 200),
                    painter: _ArcPainter(
                      progress: clamped,
                      trackColor: trackColor,
                      colorStart: colorStart,
                      colorEnd: colorEnd,
                      pulseScale: _pulse.value,
                    ),
                  );
                },
              ),

              // ── Centre content ───────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Count-up number (uses outer TweenAnimationBuilder value).
                  Text(
                    '${(clamped * widget.score).round()}',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'EFFORT SCORE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: kOrange500,
                      letterSpacing: 2.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Custom painter ─────────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color colorStart;
  final Color colorEnd;
  final double pulseScale; // 0..1 for dot pulse

  const _ArcPainter({
    required this.progress,
    required this.trackColor,
    required this.colorStart,
    required this.colorEnd,
    required this.pulseScale,
  });

  // Arc geometry: 270° sweep starting at 7 o'clock (225° from positive x-axis
  // in Flutter's coordinate system where 0° is 3 o'clock).
  static const double _startAngle = math.pi * 0.75;  // 135° → 7 o'clock
  static const double _sweepTotal = math.pi * 1.5;   // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;
    final strokeWidth = 14.0;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // ── Background track ────────────────────────────────────────────────
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);

    if (progress <= 0) return;

    final sweepAngle = _sweepTotal * progress;

    // ── Gradient fill ────────────────────────────────────────────────────
    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + sweepAngle,
      colors: [colorStart, colorEnd],
      tileMode: TileMode.clamp,
    );

    final fillPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _startAngle, sweepAngle, false, fillPaint);

    // ── Flame glow at arc tip ────────────────────────────────────────────
    final tipAngle = _startAngle + sweepAngle;
    final tipX = center.dx + radius * math.cos(tipAngle);
    final tipY = center.dy + radius * math.sin(tipAngle);
    final tipOffset = Offset(tipX, tipY);

    // Glow halo (BlurMaskFilter path)
    final glowPaint = Paint()
      ..color = colorEnd.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(tipOffset, strokeWidth / 2 + 2, glowPaint);

    // ── Pulsing indicator dot ────────────────────────────────────────────
    final dotRadius = (strokeWidth / 2 - 1) + pulseScale * 3.0;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(tipOffset, dotRadius * 0.55, dotPaint);

    final dotRingPaint = Paint()
      ..color = colorEnd
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(tipOffset, dotRadius * 0.55 + 1.5, dotRingPaint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.colorStart != colorStart ||
      old.colorEnd != colorEnd ||
      old.pulseScale != pulseScale;
}
