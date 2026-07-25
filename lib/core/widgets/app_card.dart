import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Standard content card: card surface, hairline border, soft shadow, 22px
/// radius — the prototype's `.chart-card` / `.txn` container.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: card,
      ),
    );
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
        ],
      ),
    );
  }
}
