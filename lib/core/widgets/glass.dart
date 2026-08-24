import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Frosted glass surface: blurred translucent tint + hairline border. The
/// shared primitive behind [AppCard] (`app_card.dart`) and [showGlassSheet]
/// below — anything drawn behind this widget is blurred by
/// [AppRadius.glassBlurSigma] before the tint/border paint on top.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.card),
    ),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppRadius.glassBlurSigma,
          sigmaY: AppRadius.glassBlurSigma,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: palette.glassCard,
            borderRadius: borderRadius,
            border: Border.all(color: palette.glassBorder),
            boxShadow: [
              // Dark glass needs a deeper, softer shadow to read as
              // elevated — a light-mode-strength shadow disappears against
              // a dark ground.
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.05),
                blurRadius: isDark ? 24 : 10,
                offset: Offset(0, isDark ? 8 : 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bottom sheet with a glass surface instead of a flat opaque one — the
/// shared shell for every add/edit sheet (Transfer, Account, Income, Goal,
/// Category, Tag, ...). Drop-in replacement for the repeated
/// `showModalBottomSheet(context: ..., isScrollControlled: true,
/// backgroundColor: scaffoldBackgroundColor, shape: RoundedRectangleBorder(
/// borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))))`
/// boilerplate every one of those screens used to hand-roll — this owns
/// `backgroundColor`/`shape` so call sites don't repeat them.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (context) => GlassSurface(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.card),
      ),
      child: builder(context),
    ),
  );
}
