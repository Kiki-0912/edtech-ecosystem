import 'dart:math' as math;

import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// One bar per label. Values are drawn relative to [maxValue] (or the largest
/// value). Each bar may carry its own colour.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.labels,
    required this.values,
    this.colors,
    this.maxValue,
    this.height = 160,
    this.valueFormatter,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color>? colors;
  final double? maxValue;
  final double height;
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = context.text.labelSmall ?? const TextStyle();
    return Semantics(
      label: [
        for (var i = 0; i < labels.length; i++)
          '${labels[i]}: ${valueFormatter?.call(values[i]) ?? values[i].round()}',
      ].join(', '),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            labels: labels,
            values: values,
            colors: colors ?? List.filled(values.length, c.accent),
            maxValue: maxValue,
            grid: c.border,
            labelStyle: label.copyWith(color: c.textMuted),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.labels,
    required this.values,
    required this.colors,
    required this.maxValue,
    required this.grid,
    required this.labelStyle,
  });

  final List<String> labels;
  final List<double> values;
  final List<Color> colors;
  final double? maxValue;
  final Color grid;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 20.0;
    final chartH = size.height - labelHeight;
    final top = math.max(maxValue ?? values.reduce(math.max), 1e-9);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slot = size.width / values.length;
    final barW = math.min(slot * 0.56, 36.0);
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / top).clamp(0.0, 1.0) * chartH;
      final x = slot * i + (slot - barW) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, chartH - h, barW, h),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = colors[i % colors.length]);

      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot);
      tp.paint(
          canvas,
          Offset(slot * i + (slot - tp.width) / 2,
              chartH + (labelHeight - tp.height) / 2 + 2));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.colors != colors || old.grid != grid;
}

/// Ring chart of proportions with a centred caption.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.colors,
    this.size = 140,
    this.centerTitle,
    this.centerSubtitle,
  });

  final List<double> values;
  final List<Color> colors;
  final double size;
  final String? centerTitle;
  final String? centerSubtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
                values: values, colors: colors, track: c.surfaceMuted),
          ),
          if (centerTitle != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerTitle!, style: context.text.headlineSmall),
                if (centerSubtitle != null)
                  Text(centerSubtitle!, style: context.text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(
      {required this.values, required this.colors, required this.track});

  final List<double> values;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    const gap = 0.04;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      final visible =
          values.where((v) => v > 0).length > 1 ? sweep - gap : sweep;
      canvas.drawArc(rect, start, math.max(visible, 0.001), false,
          base..color = colors[i % colors.length]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors || old.track != track;
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<MapEntry<String, Color>> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: item.value, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
              Text(item.key, style: context.text.labelMedium),
            ],
          ),
      ],
    );
  }
}
