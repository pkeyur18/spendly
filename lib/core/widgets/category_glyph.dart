import 'package:flutter/material.dart';

/// Renders a category emoji with a forced strut height so its line box
/// stays pinned to [size] regardless of which font actually paints the
/// glyph — without this, the ambient theme's non-emoji font metrics push
/// the emoji visibly off-center inside its icon box.
class CategoryGlyph extends StatelessWidget {
  const CategoryGlyph(this.emoji, {required this.size, super.key});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      emoji,
      style: TextStyle(fontSize: size, height: 1),
      strutStyle: StrutStyle(fontSize: size, height: 1, forceStrutHeight: true),
    );
  }
}
