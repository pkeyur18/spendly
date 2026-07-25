import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/row_extensions.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../dashboard_providers.dart';

/// "Where it went" — donut + legend (FR-13), bound to the current month.
/// Presentation lives in [DonutChart] so reports can reuse it for any range.
class SpendDonut extends ConsumerWidget {
  const SpendDonut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DonutChart(
      slices: ref.watch(categoryBreakdownProvider),
      total: ref.watch(monthTotalProvider),
    );
  }
}

/// Screen-reader summary for the donut, since fl_chart's canvas slices expose
/// nothing to VoiceOver/TalkBack on their own. Pure + unit-tested.
String donutSemanticsLabel(List<CategorySlice> slices, Money total) {
  if (slices.isEmpty) return 'Category breakdown, no spending yet.';
  final parts = slices
      .take(5)
      .map((s) => '${s.$1.name} ${(s.$3 * 100).round()} percent')
      .join(', ');
  return 'Category breakdown, total ${total.format(locale: 'en_IN')}: $parts.';
}

/// Provider-free donut + legend over given [slices] (desc) and [total].
/// Matches the prototype `.chart-card`. Reused by Home and Reports.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, required this.total});

  final List<CategorySlice> slices;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final empty = slices.isEmpty;

    return AppCard(
      child: Semantics(
        label: donutSemanticsLabel(slices, total),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              // The chart's fixed size can't reflow with Dynamic Type, so its
              // centered label is capped at 1.3x rather than left uncapped —
              // a documented, bounded ceiling; everything else in the app
              // scales fully.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ExcludeSemantics(
                      child: PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          sectionsSpace: empty ? 0 : 2,
                          centerSpaceRadius: 32,
                          sections: empty
                              ? [
                                  PieChartSectionData(
                                    value: 1,
                                    color: palette.line,
                                    radius: 23,
                                    showTitle: false,
                                  ),
                                ]
                              : [
                                  for (final s in slices)
                                    PieChartSectionData(
                                      value: s.$2.minor.toDouble(),
                                      color: s.$1.color,
                                      radius: 23,
                                      showTitle: false,
                                    ),
                                ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          empty ? '₹0' : total.formatCompact(locale: 'en_IN'),
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'total',
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.textDim,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: empty
                  ? Text(
                      'No spending yet',
                      style: TextStyle(color: palette.textDim, fontSize: 13),
                    )
                  : Column(
                      children: [
                        for (final s in slices.take(5))
                          _LegendRow(
                            color: s.$1.color,
                            name: s.$1.name,
                            pct: (s.$3 * 100).round(),
                            dim: palette.textDim,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.name,
    required this.pct,
    required this.dim,
  });

  final Color color;
  final String name;
  final int pct;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: dim,
            ),
          ),
        ],
      ),
    );
  }
}
