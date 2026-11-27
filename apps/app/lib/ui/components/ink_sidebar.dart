import 'package:edtech_app/ui/components/brand.dart';
import 'package:edtech_app/ui/components/content.dart';
import 'package:edtech_app/ui/motion.dart';
import 'package:edtech_app/ui/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// One destination in an [InkSidebar].
class SidebarItem {
  const SidebarItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.itemKey,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Key? itemKey;
}

/// A titled run of items. A null [title] draws no heading.
class SidebarGroup {
  const SidebarGroup({this.title, required this.items});

  final String? title;
  final List<SidebarItem> items;
}

/// Ink-black navigation sidebar shared by the app and the admin console. One
/// orange pill glides to the selected item; the whole bar collapses to an icon
/// rail (with tooltips) and expands again.
class InkSidebar extends StatefulWidget {
  const InkSidebar({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelect,
    this.badge,
    this.userName,
    this.userRole,
    this.onProfile,
  });

  final List<SidebarGroup> groups;

  /// Index into the flattened list of every group's items.
  final int selected;
  final ValueChanged<int> onSelect;

  /// Small extra tag beside the brand (e.g. "Admin").
  final Widget? badge;
  final String? userName;
  final String? userRole;
  final VoidCallback? onProfile;

  static const double expandedWidth = 256;
  static const double collapsedWidth = 80;
  static const double _itemHeight = 44;
  static const double _itemGap = 4;
  static const double _headingHeight = 40;

  @override
  State<InkSidebar> createState() => _InkSidebarState();
}

class _InkSidebarState extends State<InkSidebar> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      width: _collapsed ? InkSidebar.collapsedWidth : InkSidebar.expandedWidth,
      color: c.ink,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Labels show only once there is room, so the row never overflows
          // while the width animates.
          final wide = constraints.maxWidth > 180;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, wide),
                Expanded(child: _items(context, wide)),
                if (widget.userName != null) _profile(context, wide),
                _toggle(context, wide),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Align(
        alignment: wide ? Alignment.centerLeft : Alignment.center,
        child: wide
            ? Row(
                children: [
                  BrandMark(nameColor: c.onInk),
                  if (widget.badge != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(child: widget.badge!),
                  ],
                ],
              )
            : const BrandMark(showName: false),
      ),
    );
  }

  Widget _items(BuildContext context, bool wide) {
    final c = context.colors;
    var flat = 0;
    var y = 0.0;
    double? pillTop;
    final children = <Widget>[];

    for (final group in widget.groups) {
      if (group.title != null) {
        children.add(SizedBox(
          height: InkSidebar._headingHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(AppSpacing.md, 0, 0, AppSpacing.xs),
              child: wide
                  ? Text(
                      group.title!.toUpperCase(),
                      style: context.text.labelSmall
                          ?.copyWith(color: c.onInk.withValues(alpha: 0.5)),
                    )
                  : null,
            ),
          ),
        ));
        y += InkSidebar._headingHeight;
      }
      for (final item in group.items) {
        final index = flat++;
        if (index == widget.selected) pillTop = y;
        children
            .add(_item(context, item, index == widget.selected, index, wide));
        y += InkSidebar._itemHeight + InkSidebar._itemGap;
      }
    }

    return ListView(
      children: [
        Stack(
          children: [
            if (pillTop != null)
              AnimatedPositioned(
                key: const Key('nav-pill'),
                duration: AppMotion.of(context, AppMotion.base),
                curve: AppMotion.standard,
                top: pillTop,
                left: 0,
                right: 0,
                height: InkSidebar._itemHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: AppRadius.pillAll,
                    boxShadow: [
                      BoxShadow(
                        color: c.accentGlow,
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ],
        ),
      ],
    );
  }

  Widget _item(BuildContext context, SidebarItem item, bool selected, int index,
      bool wide) {
    final c = context.colors;
    final fg = selected ? c.onAccent : c.onInk.withValues(alpha: 0.78);
    final icon = AnimatedScale(
      scale: selected ? 1.12 : 1,
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.pop,
      child:
          Icon(selected ? item.selectedIcon : item.icon, size: 20, color: fg),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: InkSidebar._itemGap),
      child: SizedBox(
        height: InkSidebar._itemHeight,
        child: Tooltip(
          message: wide ? '' : item.label,
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.pillAll,
            child: InkWell(
              key: item.itemKey,
              borderRadius: AppRadius.pillAll,
              hoverColor: c.onInk.withValues(alpha: 0.08),
              onTap: () => widget.onSelect(index),
              child: wide
                  ? Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Row(
                        children: [
                          icon,
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelLarge?.copyWith(
                                color: fg,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profile(BuildContext context, bool wide) {
    final c = context.colors;
    final name = widget.userName!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: c.onInk.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          key: const Key('sidebar-profile'),
          borderRadius: AppRadius.lgAll,
          onTap: widget.onProfile,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: wide
                ? Row(
                    children: [
                      Avatar(name: name, size: 36),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelLarge
                                    ?.copyWith(color: c.onInk)),
                            if (widget.userRole != null)
                              Text(widget.userRole!,
                                  style: context.text.bodySmall?.copyWith(
                                      color: c.onInk.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(child: Avatar(name: name, size: 36)),
          ),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, bool wide) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Tooltip(
        message: _collapsed ? 'Expand sidebar' : 'Collapse sidebar',
        child: InkWell(
          key: const Key('sidebar-toggle'),
          borderRadius: AppRadius.pillAll,
          hoverColor: c.onInk.withValues(alpha: 0.08),
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisAlignment:
                  wide ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                if (wide) const SizedBox(width: AppSpacing.md),
                AnimatedRotation(
                  turns: _collapsed ? 0.5 : 0,
                  duration: AppMotion.of(context, AppMotion.base),
                  curve: AppMotion.standard,
                  child: Icon(Icons.keyboard_double_arrow_left_rounded,
                      size: 20, color: c.onInk.withValues(alpha: 0.6)),
                ),
                if (wide) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text('Collapse',
                      style: context.text.labelMedium
                          ?.copyWith(color: c.onInk.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
