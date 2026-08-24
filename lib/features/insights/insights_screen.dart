import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import 'insights_provider.dart';

/// Insight feed (Phase 7) — pure derived math over existing spend history,
/// no schema of its own. Sequenced last in the roadmap because it needs
/// real history (recurring data, several months of category spend) to be
/// worth reading; a fresh install would just see the empty state below.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendsAsync = ref.watch(categoryTrendsProvider);
    final subsAsync = ref.watch(subscriptionsTotalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: trendsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load insights.",
          onRetry: () => ref.invalidate(categoryTrendsProvider),
        ),
        data: (trends) {
          final subs = subsAsync.value;
          final hasSubs = subs != null && subs.minor > 0;
          if (trends.isEmpty && !hasSubs) {
            return const EmptyView(
              icon: Icons.insights_outlined,
              message:
                  'Nothing stands out yet — insights need a few months of '
                  'history to compare against.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (hasSubs)
                _InsightCard(
                  icon: Icons.repeat_rounded,
                  color: AppColors.primary,
                  text:
                      '${subs.format(locale: 'en_IN')}/month in recurring '
                      'expenses and subscriptions.',
                ),
              for (final t in trends)
                _InsightCard(
                  icon: t.percentChange! > 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: t.percentChange! > 0 ? AppColors.accent : AppColors.primary,
                  text:
                      '${t.categoryName} is ${t.percentChange! > 0 ? 'up' : 'down'} '
                      '${t.percentChange!.abs()}% vs your 3-month average '
                      '(${t.current.format(locale: 'en_IN')} this month, '
                      '${t.priorAverage.format(locale: 'en_IN')} average).',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
