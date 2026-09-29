import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Scrollable page body that centres content and caps its width so lines stay
/// readable on wide screens and nothing overflows on narrow ones.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.children,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16),
    this.banner,
    this.buildAll = false,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;

  /// Optional widget pinned above the scrolling content (e.g. an error banner).
  final Widget? banner;

  /// Build every child at once instead of only those near the viewport.
  /// Forms use it so a field keeps its state while it is scrolled out of view.
  final bool buildAll;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          children: [
            if (banner != null)
              Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 0),
                child: banner,
              ),
            Expanded(
              child: ListView(
                padding: padding,
                scrollCacheExtent: buildAll ? const ScrollCacheExtent.pixels(100000) : null,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
