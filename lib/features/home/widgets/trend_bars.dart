import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../dashboard_providers.dart';

/// "Last 6 months" trend (FR-14), bound to the dashboard. Presentation lives in
/// [TrendBarsView] so reports can reuse it for weekly buckets.
class TrendBars extends ConsumerWidget {
  const TrendBars({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrendBarsView(bars: ref.watch(trendProvider));
  }
}

/// Provider-free bar chart over given [bars]. Current bar highlighted accent,
/// per the prototype's `.bar.active`. Reused by Home and Reports.
class TrendBarsView extends StatelessWidget {
  const TrendBarsView({super.key, required this.bars});

  final List<TrendBar> bars;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final maxMinor =
        bars.fold<int>(0, (m, b) => b.$2.minor > m ? b.$2.minor : m);
    final maxY = maxMinor == 0 ? 1.0 : maxMinor * 1.25 / 100;

    return AppCard(
      child: SizedBox(
        height: 120,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(enabled: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(bars[i].$1,
                          style: TextStyle(fontSize: 11, color: palette.textDim)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < bars.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].$2.major.toDouble(),
                      width: 22,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: bars[i].$3
                            ? const [Color(0xFFEA580C), AppColors.accent]
                            : const [AppColors.primary, AppColors.primarySoft],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
