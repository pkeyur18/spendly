import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Centered spinner for an `AsyncValue`'s loading branch — standardizes what
/// was previously ad-hoc/missing across several screens (Sprint 7).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Friendly error surface for an `AsyncValue`'s error branch, with an optional
/// retry action (e.g. `() => ref.invalidate(someProvider)`).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.textDim, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textDim, fontSize: 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly "nothing here yet" surface, reused wherever a screen's data is
/// empty rather than absent/errored.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: palette.textDim, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
