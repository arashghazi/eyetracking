import 'package:flutter/material.dart';

/// Scrollable page body that centres content and caps its width so lines stay
/// readable on wide screens and nothing overflows on narrow ones.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.children,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(16),
    this.banner,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;

  /// Optional widget pinned above the scrolling content (e.g. an error banner).
  final Widget? banner;

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
              child: ListView(padding: padding, children: children),
            ),
          ],
        ),
      ),
    );
  }
}
