import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One jump target in the command palette.
class PaletteItem {
  const PaletteItem({
    required this.label,
    required this.icon,
    required this.onSelect,
    this.hint,
  });

  final String label;
  final IconData icon;
  final String? hint;
  final VoidCallback onSelect;
}

/// Wraps [child] so Ctrl+K / Cmd+K calls [onOpen].
class PaletteShortcut extends StatelessWidget {
  const PaletteShortcut({super.key, required this.onOpen, required this.child});

  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): onOpen,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onOpen,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// Opens the palette: type to filter, Enter picks the top match, Esc closes.
Future<void> showCommandPalette(BuildContext context, List<PaletteItem> items) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close search',
    barrierColor: context.colors.overlay,
    transitionDuration: AppMotion.of(context, AppMotion.base),
    pageBuilder: (ctx, _, __) => _Palette(items: items),
    transitionBuilder: (ctx, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: AppMotion.standard);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.items});

  final List<PaletteItem> items;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  List<PaletteItem> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where((i) =>
            i.label.toLowerCase().contains(q) ||
            (i.hint ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _pick(PaletteItem item) {
    Navigator.of(context).pop();
    item.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final matches = _matches;
    return Align(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Material(
            color: c.surface,
            elevation: 8,
            shadowColor: c.overlay,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.xlAll,
              side: BorderSide(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: TextField(
                    key: const Key('palette-input'),
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (_) {
                      if (matches.isNotEmpty) _pick(matches.first);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Jump to…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                Flexible(
                  child: matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text('Nothing matches "$_query".',
                              textAlign: TextAlign.center,
                              style: context.text.bodyMedium),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          children: [
                            for (final (i, item) in matches.indexed)
                              FadeSlideIn(
                                delay: AppMotion.delayFor(i),
                                offset: 6,
                                child: ListTile(
                                  key: Key('palette-${item.label}'),
                                  dense: true,
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: AppRadius.mdAll),
                                  selected: i == 0,
                                  selectedTileColor: c.accentSoft,
                                  selectedColor: c.accentText,
                                  leading: Icon(item.icon, size: 20),
                                  title: Text(item.label),
                                  subtitle: item.hint == null
                                      ? null
                                      : Text(item.hint!),
                                  onTap: () => _pick(item),
                                ),
                              ),
                          ],
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
