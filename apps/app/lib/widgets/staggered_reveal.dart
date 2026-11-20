import 'package:flutter/material.dart';

/// Wraps a list of children so each item wipes in one-by-one with a stagger.
///
/// [fromRight] = true  → slides from right  (Offset(0.08, 0) → Offset.zero)
/// [fromRight] = false → slides from bottom (Offset(0, 0.08) → Offset.zero)
///
/// Stagger: 60 ms per item. Curve: easeOutCubic.
class StaggeredReveal extends StatelessWidget {
  final int childCount;
  final IndexedWidgetBuilder itemBuilder;
  final Duration baseDelay;
  final bool fromRight;

  const StaggeredReveal({
    super.key,
    required this.childCount,
    required this.itemBuilder,
    this.baseDelay = const Duration(milliseconds: 60),
    this.fromRight = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(childCount, (index) {
        return _StaggeredItem(
          delay: baseDelay * index,
          fromRight: fromRight,
          child: itemBuilder(context, index),
        );
      }),
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  final Duration delay;
  final bool fromRight;
  final Widget child;

  const _StaggeredItem({
    required this.delay,
    required this.fromRight,
    required this.child,
  });

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _fade = Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.fromRight ? const Offset(0.08, 0) : const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
