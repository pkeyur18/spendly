import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass.dart';

/// Standard content card: frosted glass surface (blurred translucent tint,
/// hairline border via [GlassSurface]), 26px radius — the prototype's
/// `.chart-card` / `.txn` container, redesigned to the glass treatment
/// (2026-08-24).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.onLongPress,
    this.longPressHint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Spoken label for [onLongPress]. A long-press is invisible to a screen
  /// reader unless it's named, so the action would otherwise not exist for
  /// VoiceOver/TalkBack users.
  final String? longPressHint;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    final paddedChild = Padding(padding: padding, child: child);

    // InkWell must sit inside GlassSurface's clip (not wrap it) so the
    // ripple stays within the rounded glass shape instead of spilling past
    // it.
    final interactive = (onTap == null && onLongPress == null)
        ? paddedChild
        : Semantics(
            button: true,
            onLongPressHint: longPressHint,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: radius,
              child: paddedChild,
            ),
          );

    return GlassSurface(borderRadius: radius, child: interactive);
  }
}

/// Section header row: Sora title on the left, optional tappable trailing link
/// on the right (the prototype's `.sec-title`).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxl,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (actionLabel != null)
            Semantics(
              button: true,
              label: actionLabel,
              child: GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
