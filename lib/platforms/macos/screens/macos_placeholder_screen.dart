import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../macos_tab.dart';

/// Stand-in for every desktop screen not yet built (sprints 2–4 fill these
/// in one at a time). Only [MacosTab.sync] has a real screen this sprint.
class MacosPlaceholderScreen extends StatelessWidget {
  const MacosPlaceholderScreen({super.key, required this.tab});
  final MacosTab tab;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 28, color: palette.textDim),
              const SizedBox(height: 12),
              Text(
                '${tab.label} — coming soon',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Import your data from the Sync tab first — this screen fills in during a later sprint.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: palette.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
