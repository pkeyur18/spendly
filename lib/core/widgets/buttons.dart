import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app's primary call-to-action button: brand-gradient pill, white Sora
/// label. Unifies what every add/edit sheet (Transfer, Income, Goal) used to
/// hand-roll individually, and what Account's sheet used a plain
/// [FilledButton] for instead (2026-08-24 redesign) — one shared widget now.
class PrimaryGradientButton extends StatelessWidget {
  const PrimaryGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Spoken label, if it should differ from the visible [label] (e.g. a
  /// "Saving…" visible label with a steady "Save transfer" spoken one).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
