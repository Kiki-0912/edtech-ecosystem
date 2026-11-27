import 'dart:math' as math;

import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Bordered surface card. Tappable when [onTap] is set.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Card with a [SectionHeader]-style title row and content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: context.text.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// KPI tile: icon, big value, label, optional caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.accent,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon: icon, tone: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: context.text.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(label,
                    style: context.text.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (caption != null)
                  Text(caption!,
                      style:
                          context.text.bodySmall?.copyWith(color: c.fg(tone)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded-square icon on a tinted background.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.tone = Tone.accent,
    this.size = 40,
  });

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.bg(tone),
        borderRadius: AppRadius.mdAll,
      ),
      child: Icon(icon, size: size * 0.5, color: c.fg(tone)),
    );
  }
}

/// Small pill label with semantic colour.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
  });

  final String label;
  final Tone tone;
  final IconData? icon;

  /// Maps attendance statuses (present/absent/late/excused) to tones.
  factory StatusBadge.attendance(String status, {Key? key}) {
    final s = status.toLowerCase();
    return StatusBadge(
      key: key,
      label: s.isEmpty ? 'Unmarked' : '${s[0].toUpperCase()}${s.substring(1)}',
      tone: attendanceTone(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs / 2),
      decoration: BoxDecoration(
        color: c.bg(tone),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c.fg(tone)),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: c.fg(tone))),
          ),
        ],
      ),
    );
  }
}

Tone attendanceTone(String status) => switch (status.toLowerCase()) {
      'present' => Tone.success,
      'absent' => Tone.danger,
      'late' => Tone.warning,
      'excused' => Tone.info,
      _ => Tone.neutral,
    };

/// List row with leading widget, title, subtitle and trailing widget.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: dense ? AppSpacing.xs : AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        style: context.text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Initials avatar with a deterministic tint.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const tones = [Tone.accent, Tone.info, Tone.success, Tone.warning];
    final tone = tones[name.hashCode.abs() % tones.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.bg(tone), shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: context.text.labelMedium?.copyWith(
          color: c.fg(tone),
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Circular progress ring with a centred label (0..1 value).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.label,
    this.caption,
    this.size = 120,
    this.tone = Tone.accent,
    this.stroke = 10,
  });

  final double value;
  final String label;
  final String? caption;
  final double size;
  final Tone tone;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = tone == Tone.accent ? c.accent : c.fg(tone);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
              value: v, color: color, track: c.surfaceMuted, stroke: stroke),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: size >= 100
                        ? context.text.headlineMedium
                        : context.text.titleMedium),
                if (caption != null)
                  Text(caption!, style: context.text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inner, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(
          inner, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Thin horizontal progress bar with semantic tone.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.tone = Tone.accent});

  final double value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: AppRadius.pillAll,
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: c.surfaceMuted,
        color: tone == Tone.accent ? c.accent : c.fg(tone),
      ),
    );
  }
}
