import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart' show monthKeyFor;
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../budgets/budget_repository.dart';
import '../expenses/expense_repository.dart' show monthBounds;
import '../home/dashboard_providers.dart'
    show CategorySlice, categoriesByIdProvider, ignoredCategoryIds;
import '../ledger/cashflow_math.dart';
import '../ledger/ledger_repository.dart';
import '../profile/profile_provider.dart';
import '../reports/report_providers.dart';
import 'recap_summary.dart';

/// Monthly recap ("Hero Celebration Takeover") — auto-shown once on the first
/// app open of a new month (`recap_providers.dart`), and reachable any time
/// from Profile. [month] is the already-past month being recapped.
class MonthlyRecapScreen extends ConsumerWidget {
  const MonthlyRecapScreen({super.key, required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final (start, end) = monthBounds(month);
    final async = ref.watch(reportProvider((start, end)));
    final byId = ref.watch(categoriesByIdProvider);
    final budget = effectiveOverallBudget(
      ref.watch(overallBudgetForMonthProvider(monthKeyFor(month))).value,
      ref.watch(perCategoryBudgetsForMonthProvider(monthKeyFor(month))),
      ignoredCategoryIds(byId),
    );
    final profile = ref.watch(profileProvider).value;
    final monthLabel = DateFormat('MMMM').format(month);
    final incomeTotal =
        ref.watch(incomeTotalByRangeProvider((start, end))).value ?? Money.zero;

    return Scaffold(
      bottomNavigationBar: async.maybeWhen(
        data: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _ContinueButton(
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        orElse: () => null,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            message: 'Could not load your recap.',
            onRetry: () => ref.invalidate(reportProvider((start, end))),
          ),
          data: (report) {
            final summary = computeRecapSummary(
              total: report.total,
              budget: budget,
            );
            final hasBudget = summary.hasBudget;
            final isPositive = summary.isPositive;
            final top3 = report.breakdown.take(3).toList();
            final firstName = (profile?.name ?? '')
                .trim()
                .split(RegExp(r'\s+'))
                .first;

            return Stack(
              children: [
                if (hasBudget && isPositive) const _ConfettiOverlay(),
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs,
                        AppSpacing.sm,
                        AppSpacing.xs,
                        AppSpacing.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monthly recap · $monthLabel',
                            style: TextStyle(
                              color: palette.textDim,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasBudget && isPositive
                                ? 'Nice one${firstName.isEmpty ? '' : ', $firstName'} 🎉'
                                : "Here's your $monthLabel",
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    _RecapHero(
                      total: report.total,
                      summary: summary,
                      monthLabel: monthLabel,
                    ),
                    // Only shown once income has actually been logged for
                    // this month — most users never touch Income, and this
                    // stays silent for them rather than showing a 0% row.
                    if (incomeTotal.minor > 0)
                      _SavingsRateCard(
                        income: incomeTotal,
                        expense: report.total,
                      ),
                    const SectionTitle('Top categories'),
                    if (top3.isEmpty)
                      AppCard(
                        child: Text(
                          'No expenses recorded this month.',
                          style: TextStyle(color: palette.textDim),
                        ),
                      )
                    else
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < top3.length; i++) ...[
                              _TopCategoryRow(rank: i, slice: top3[i]),
                              if (i < top3.length - 1)
                                Divider(height: 1, color: palette.line),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Gradient hero card — brand gradient for the neutral/positive states, a
/// calm amber (never red) when over budget, matching the prototype's
/// "informative, not alarming" negative treatment.
class _RecapHero extends StatelessWidget {
  const _RecapHero({
    required this.total,
    required this.summary,
    required this.monthLabel,
  });

  final Money total;
  final RecapSummary summary;
  final String monthLabel;

  static const _overGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.accent, AppColors.amberDeeper],
  );

  @override
  Widget build(BuildContext context) {
    final hasBudget = summary.hasBudget;
    final isPositive = summary.isPositive;
    final gradient = hasBudget && !isPositive
        ? _overGradient
        : AppColors.heroGradient;
    final shadowColor = hasBudget && !isPositive
        ? AppColors.accent
        : AppColors.primary;

    String label;
    String amount;
    String sub;
    if (!hasBudget) {
      label = 'Total spent';
      amount = total.format(locale: 'en_IN');
      sub = 'No monthly budget was set for $monthLabel.';
    } else {
      final pct = summary.percentUsed;
      final savings = summary.savings!;
      if (isPositive) {
        label = 'You saved this month';
        amount = savings.format(locale: 'en_IN');
        sub =
            'You spent ${total.format(locale: 'en_IN')} of your '
            '${(total + savings).format(locale: 'en_IN')} budget — $pct% used.';
      } else {
        final over = Money.fromMinor(-savings.minor);
        label = 'You went over budget';
        amount = '${over.format(locale: 'en_IN')} over';
        sub =
            'You spent ${total.format(locale: 'en_IN')} against a '
            '${(total + savings).format(locale: 'en_IN')} budget — $pct% used.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            sub,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// "You kept 22% this month" — separate from [_RecapHero] deliberately: the
/// hero's budget-based headline is well-tested and stays untouched for the
/// (much more common, since income is optional) case where no income was
/// logged. This card only appears additively once it has.
class _SavingsRateCard extends StatelessWidget {
  const _SavingsRateCard({required this.income, required this.expense});

  final Money income;
  final Money expense;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final cashflow = computeCashflow(income: income, expense: expense);
    final kept = cashflow.savingsRatePercent!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kept >= 0 ? 'You kept $kept% this month' : 'You spent more than you earned',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${income.format(locale: 'en_IN')} in, '
                    '${expense.format(locale: 'en_IN')} out',
                    style: TextStyle(fontSize: 12, color: palette.textDim),
                  ),
                ],
              ),
            ),
            Text(
              cashflow.net.format(locale: 'en_IN'),
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cashflow.net.minor >= 0 ? AppColors.primary : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCategoryRow extends StatelessWidget {
  const _TopCategoryRow({required this.rank, required this.slice});

  final int rank;
  final CategorySlice slice;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final (category, total, _) = slice;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(_medals[rank], style: const TextStyle(fontSize: 16)),
          ),
          CategoryGlyph(category.icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              category.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            total.format(locale: 'en_IN'),
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand-gradient CTA — same recipe as Quick Add's save button
/// (`quick_add_screen.dart`'s `_saveButton`).
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Done',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.button),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            // No `alignment:` here — with a single Text child, Container
            // shrink-wraps tightly to it on every axis, bounded or not.
            // (`alignment` makes Container's Align expand to fill *bounded*
            // parent constraints, which is exactly what blew this button up
            // to full-screen once it moved into Scaffold.bottomNavigationBar.)
            child: const Text(
              'Done',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Sora',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight native-Flutter confetti burst (no package) — a handful of
/// emoji falling + fading on a loop, mirroring the prototype's CSS keyframe
/// version. Only shown when the month closed with positive savings.
class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _pieces = [
    ('🎉', 0.08, 0.0),
    ('✨', 0.22, 0.3),
    ('🎊', 0.38, 0.6),
    ('✨', 0.58, 0.15),
    ('🎉', 0.74, 0.5),
    ('🎊', 0.88, 0.8),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          children: [
            for (final (emoji, left, delay) in _pieces)
              _piece(size, emoji, left, delay),
          ],
        ),
      ),
    );
  }

  Widget _piece(Size size, String emoji, double left, double delay) {
    final t = (_controller.value + delay) % 1.0;
    return Positioned(
      left: size.width * left,
      top: -24 + t * (size.height * 0.45 + 24),
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: t * 6.28,
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
