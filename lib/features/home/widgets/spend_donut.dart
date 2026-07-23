import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/row_extensions.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../dashboard_providers.dart';

/// "Where it went" — donut + legend (FR-13). Matches prototype `.chart-card`.
class SpendDonut extends ConsumerWidget {
  const SpendDonut({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final slices = ref.watch(categoryBreakdownProvider);
    final total = ref.watch(monthTotalProvider);
    final empty = slices.isEmpty;

    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      empty ? '₹0' : total.formatCompact(locale: 'en_IN'),
                      style: const TextStyle(
                          fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text('total',
                        style: TextStyle(fontSize: 10, color: palette.textDim)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: empty
                ? Text('No spending yet',
                    style: TextStyle(color: palette.textDim, fontSize: 13))
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
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.name, required this.pct, required this.dim});

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
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          Text('$pct%',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dim)),
        ],
      ),
    );
  }
}
