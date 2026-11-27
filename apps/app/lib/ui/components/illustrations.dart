import 'dart:ui' as ui;

import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Which single-line drawing to show.
enum IllustrationKind { courses, caughtUp, nothing, error, offline }

/// A small single-line illustration in ink with one orange accent. The lines
/// draw themselves once (600 ms), then it rests. Reduced motion shows it
/// finished.
class LineIllustration extends StatelessWidget {
  const LineIllustration({super.key, required this.kind, this.size = 96});

  final IllustrationKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, const Duration(milliseconds: 600)),
        curve: Curves.easeInOutCubic,
        builder: (context, t, _) => CustomPaint(
          size: Size.square(size),
          painter: _IllustrationPainter(
            kind: kind,
            t: t,
            ink: c.textPrimary,
            accent: c.accent,
            wash: c.accentSoft,
          ),
        ),
      ),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter({
    required this.kind,
    required this.t,
    required this.ink,
    required this.accent,
    required this.wash,
  });

  final IllustrationKind kind;
  final double t;
  final Color ink;
  final Color accent;
  final Color wash;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    Offset p(double x, double y) => Offset(x * s, y * s);

    // Soft orange blob behind the drawing.
    canvas.drawCircle(
      p(48, 50),
      38 * s * Curves.easeOutBack.transform(t.clamp(0.0, 1.0)),
      Paint()..color = wash,
    );

    Paint stroke(Color color, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    void draw(Path path, Paint paint) {
      for (final ui.PathMetric m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), paint);
      }
    }

    final line = stroke(ink, 2.4);
    final spark = stroke(accent, 3);

    switch (kind) {
      case IllustrationKind.courses:
        // An open book with a bookmark.
        draw(
          Path()
            ..moveTo(p(48, 34).dx, p(48, 34).dy)
            ..quadraticBezierTo(
                p(34, 26).dx, p(34, 26).dy, p(20, 30).dx, p(20, 30).dy)
            ..lineTo(p(20, 68).dx, p(20, 68).dy)
            ..quadraticBezierTo(
                p(34, 64).dx, p(34, 64).dy, p(48, 72).dx, p(48, 72).dy)
            ..quadraticBezierTo(
                p(62, 64).dx, p(62, 64).dy, p(76, 68).dx, p(76, 68).dy)
            ..lineTo(p(76, 30).dx, p(76, 30).dy)
            ..quadraticBezierTo(
                p(62, 26).dx, p(62, 26).dy, p(48, 34).dx, p(48, 34).dy)
            ..moveTo(p(48, 34).dx, p(48, 34).dy)
            ..lineTo(p(48, 72).dx, p(48, 72).dy),
          line,
        );
        draw(
          Path()
            ..moveTo(p(60, 28).dx, p(60, 28).dy)
            ..lineTo(p(60, 44).dx, p(60, 44).dy)
            ..lineTo(p(65, 40).dx, p(65, 40).dy)
            ..lineTo(p(70, 44).dx, p(70, 44).dy)
            ..lineTo(p(70, 27).dx, p(70, 27).dy),
          spark,
        );
      case IllustrationKind.caughtUp:
        // A circle and a tick.
        draw(
            Path()..addOval(Rect.fromCircle(center: p(48, 50), radius: 24 * s)),
            line);
        draw(
          Path()
            ..moveTo(p(37, 51).dx, p(37, 51).dy)
            ..lineTo(p(45, 59).dx, p(45, 59).dy)
            ..lineTo(p(60, 42).dx, p(60, 42).dy),
          spark,
        );
      case IllustrationKind.nothing:
        // An open tray with a spark above it.
        draw(
          Path()
            ..moveTo(p(22, 52).dx, p(22, 52).dy)
            ..lineTo(p(32, 38).dx, p(32, 38).dy)
            ..lineTo(p(64, 38).dx, p(64, 38).dy)
            ..lineTo(p(74, 52).dx, p(74, 52).dy)
            ..lineTo(p(74, 66).dx, p(74, 66).dy)
            ..lineTo(p(22, 66).dx, p(22, 66).dy)
            ..close()
            ..moveTo(p(22, 52).dx, p(22, 52).dy)
            ..lineTo(p(40, 52).dx, p(40, 52).dy)
            ..lineTo(p(44, 58).dx, p(44, 58).dy)
            ..lineTo(p(52, 58).dx, p(52, 58).dy)
            ..lineTo(p(56, 52).dx, p(56, 52).dy)
            ..lineTo(p(74, 52).dx, p(74, 52).dy),
          line,
        );
        draw(
          Path()
            ..moveTo(p(48, 18).dx, p(48, 18).dy)
            ..lineTo(p(48, 28).dx, p(48, 28).dy),
          spark,
        );
      case IllustrationKind.error:
        // A triangle with an exclamation mark.
        draw(
          Path()
            ..moveTo(p(48, 26).dx, p(48, 26).dy)
            ..lineTo(p(74, 70).dx, p(74, 70).dy)
            ..lineTo(p(22, 70).dx, p(22, 70).dy)
            ..close(),
          line,
        );
        draw(
          Path()
            ..moveTo(p(48, 40).dx, p(48, 40).dy)
            ..lineTo(p(48, 56).dx, p(48, 56).dy),
          spark,
        );
        if (t > 0.9) {
          canvas.drawCircle(p(48, 63), 2 * s, Paint()..color = accent);
        }
      case IllustrationKind.offline:
        // A cloud with a slash.
        draw(
          Path()
            ..moveTo(p(32, 64).dx, p(32, 64).dy)
            ..quadraticBezierTo(
                p(18, 64).dx, p(18, 64).dy, p(20, 52).dx, p(20, 52).dy)
            ..quadraticBezierTo(
                p(22, 42).dx, p(22, 42).dy, p(32, 42).dx, p(32, 42).dy)
            ..quadraticBezierTo(
                p(36, 28).dx, p(36, 28).dy, p(50, 30).dx, p(50, 30).dy)
            ..quadraticBezierTo(
                p(62, 30).dx, p(62, 30).dy, p(64, 42).dx, p(64, 42).dy)
            ..quadraticBezierTo(
                p(76, 44).dx, p(76, 44).dy, p(74, 54).dx, p(74, 54).dy)
            ..quadraticBezierTo(
                p(72, 64).dx, p(72, 64).dy, p(62, 64).dx, p(62, 64).dy)
            ..close(),
          line,
        );
        draw(
          Path()
            ..moveTo(p(26, 72).dx, p(26, 72).dy)
            ..lineTo(p(70, 24).dx, p(70, 24).dy),
          spark,
        );
    }
  }

  @override
  bool shouldRepaint(_IllustrationPainter old) =>
      old.t != t || old.kind != kind || old.ink != ink || old.accent != accent;
}
