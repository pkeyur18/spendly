import 'package:flutter/material.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../profile/profile_provider.dart';
import 'report_export.dart';
import 'report_model.dart';

/// Gradient hero: label + big total + comparison line. Matches `.report-hero`.
class ReportHero extends StatelessWidget {
  const ReportHero({super.key, required this.label, required this.data});

  final String label;
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final compare = data.changePct == null
        ? 'No prior-period spend to compare'
        : '${data.changeUp ? '↑' : '↓'} ${data.changePct!.abs().toStringAsFixed(0)}% '
              'vs previous period (${data.previousTotal.format(locale: 'en_IN')})';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            data.total.format(locale: 'en_IN'),
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            compare,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 2xN grid of small labelled stat boxes (daily avg, txns, top category, …).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.stats});

  /// (label, value) pairs.
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 2.6,
      children: [
        for (final (label, value) in stats)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: palette.textDim),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ranked list of the biggest single expenses (FR-20). Matches `.top-list`.
class TopExpensesCard extends StatelessWidget {
  const TopExpensesCard({super.key, required this.data, required this.byId});

  final ReportData data;
  final Map<int, CategoryRow> byId;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < data.top5.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      data.top5[i].note?.isNotEmpty == true
                          ? data.top5[i].note!
                          : (byId[data.top5[i].categoryId]?.name ?? 'Expense'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    data.top5[i].amount.format(locale: 'en_IN'),
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 14),
                  ),
                ],
              ),
            ),
          if (data.top5.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'No expenses in this period',
                style: TextStyle(color: palette.textDim),
              ),
            ),
        ],
      ),
    );
  }
}

/// Export CSV / Export PDF buttons that generate then hand off to the OS share
/// sheet (FR-21, FR-22). Email is one of the share targets.
class ExportRow extends StatefulWidget {
  const ExportRow({
    super.key,
    required this.data,
    required this.byId,
    required this.title,
    this.profile,
  });

  final ReportData data;
  final Map<int, CategoryRow> byId;
  final String title;
  final Profile? profile;

  @override
  State<ExportRow> createState() => _ExportRowState();
}

class _ExportRowState extends State<ExportRow> {
  bool _busy = false;

  Future<void> _export({required bool pdf}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final safe = widget.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      if (pdf) {
        final bytes = await buildPdf(
          widget.data,
          widget.byId,
          title: widget.title,
          profile: widget.profile,
        );
        await shareReportFile(bytes: bytes, filename: '$safe.pdf');
      } else {
        final csv = buildCsv(
          widget.data.expenses,
          widget.byId,
          profile: widget.profile,
        );
        await shareReportFile(bytes: csv.codeUnits, filename: '$safe.csv');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => _export(pdf: false),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.line),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child: const Text('Export CSV'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : () => _export(pdf: true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Export PDF'),
          ),
        ),
      ],
    );
  }
}
