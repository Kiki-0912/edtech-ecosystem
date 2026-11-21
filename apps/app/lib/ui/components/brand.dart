import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Logo: orange rounded square with a cap icon, optionally with the name.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showName = true, this.size = 36});

  final bool showName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.accent, borderRadius: AppRadius.mdAll),
      child: Icon(Icons.school_rounded, color: c.onAccent, size: size * 0.56),
    );
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: AppSpacing.sm),
        Text('EdTech', style: context.text.titleLarge),
      ],
    );
  }
}
