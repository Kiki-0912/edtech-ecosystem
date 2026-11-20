import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// A black card with an animated burning-perimeter border.
/// An orange segmented/dashed arc slowly traces around the card edge.
class LivelyCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const LivelyCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<LivelyCard> createState() => _LivelyCardState();
}

class _LivelyCardState extends State<LivelyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _BurningBorderPainter(
            progress: _controller.value,
            radius: widget.borderRadius,
          ),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}

class _BurningBorderPainter extends CustomPainter {
  final double progress; // 0..1
  final double radius;

  const _BurningBorderPainter({
    required this.progress,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Draw dim base border
    final basePaint = Paint()
      ..color = kOrange500.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, basePaint);

    // Perimeter of the rounded rect (approximation)
    // We'll use path metrics to position the glow arc.
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);

    // Segment = 20% of perimeter, rotating with progress.
    const segmentFraction = 0.22;
    final segmentLen = totalLength * segmentFraction;
    final startLen = (progress * totalLength) % totalLength;

    // Build the glowing arc path.
    final glowPath = Path();
    double remaining = segmentLen;
    double pos = startLen;
    bool first = true;

    for (final metric in metrics) {
      if (remaining <= 0) break;
      final metricStart = pos.clamp(0.0, metric.length);
      final metricEnd = (metricStart + remaining).clamp(0.0, metric.length);
      final sub = metric.extractPath(metricStart, metricEnd);
      if (first) {
        glowPath.addPath(sub, Offset.zero);
        first = false;
      } else {
        glowPath.addPath(sub, Offset.zero);
      }
      remaining -= (metricEnd - metricStart);
      pos = 0;
    }

    // Handle wrap-around
    if (remaining > 0) {
      for (final metric in metrics) {
        if (remaining <= 0) break;
        final metricEnd = remaining.clamp(0.0, metric.length);
        glowPath.addPath(metric.extractPath(0, metricEnd), Offset.zero);
        remaining -= metricEnd;
      }
    }

    // Outer glow
    final glowPaint = Paint()
      ..color = kOrange500.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(glowPath, glowPaint);

    // Core bright line
    final corePaint = Paint()
      ..color = kOrange500.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(glowPath, corePaint);

    // Leading spark — bright dot at head of arc
    final sparkProgress = (startLen + segmentLen) % totalLength;
    Offset? sparkPoint;
    double acc = 0;
    for (final metric in metrics) {
      if (sparkProgress >= acc && sparkProgress <= acc + metric.length) {
        final t = metric.getTangentForOffset(sparkProgress - acc);
        if (t != null) sparkPoint = t.position;
        break;
      }
      acc += metric.length;
    }
    if (sparkPoint != null) {
      final sparkPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(sparkPoint, 2.5, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurningBorderPainter old) =>
      old.progress != progress;
}
