import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/notify/notifications.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../budgets/budget_repository.dart';
import '../categories/category_repository.dart';
import '../home/dashboard_providers.dart';
import '../widgets/widget_refresh.dart';
import 'expense_repository.dart';

/// Fast expense entry (FR-2, FR-5): keypad + category grid, ≤3-tap save.
/// Reused for editing (FR-6, FR-15) when [editing] is supplied.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.editing, this.initialCategoryId});

  final ExpenseRow? editing;

  /// Preselected category for a fresh entry (widget deep-link, FR-3). Ignored
  /// when [editing] is set (the edited expense's own category wins).
  final int? initialCategoryId;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

/// Categories shown in the quick-add grid before it switches to a
/// truncated view with a "More" tile.
const _gridCap = 8;
const _visibleWhenCapped = 7;

/// First [visibleCount] categories, with [selectedId] swapped into the last
/// slot if it would otherwise be cut off.
List<CategoryRow> visibleCategoryTiles(
  List<CategoryRow> categories,
  int? selectedId, {
  int visibleCount = _visibleWhenCapped,
}) {
  final visible = categories.take(visibleCount).toList();
  if (selectedId != null && !visible.any((c) => c.id == selectedId)) {
    final selected = categories
        .where((c) => c.id == selectedId)
        .cast<CategoryRow?>()
        .firstOrNull;
    if (selected != null) visible[visible.length - 1] = selected;
  }
  return visible;
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  late String _amount;
  int? _categoryId;
  bool _defaulted = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    // Prefill from the expense being edited; strip trailing ".00".
    _amount = e == null
        ? '0'
        : (e.amount.minor % 100 == 0
              ? (e.amount.minor ~/ 100).toString()
              : e.amount.major.toStringAsFixed(2));
    _categoryId = e?.categoryId ?? widget.initialCategoryId;
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return Scaffold(
      body: SafeArea(
        child: categoriesAsync.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            message: 'Couldn\'t load categories.',
            onRetry: () => ref.invalidate(activeCategoriesProvider),
          ),
          data: (categories) {
            _applyDefaultCategory(categories);
            final selected = categories
                .where((c) => c.id == _categoryId)
                .cast<CategoryRow?>()
                .firstOrNull;

            return Column(
              children: [
                _titleBar(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      AmountDisplay(_amount),
                      _subLine(context, selected, palette),
                      const SizedBox(height: AppSpacing.xl),
                      _categoryGrid(categories),
                      const SizedBox(height: AppSpacing.lg),
                      AmountKeypad(
                        onKey: (k) => setState(
                          () => _amount = applyAmountKey(_amount, k),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _saveButton(context),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _applyDefaultCategory(List<CategoryRow> categories) {
    if (_defaulted || _categoryId != null || categories.isEmpty) return;
    final lastUsed = ref.read(lastUsedCategoryIdProvider);
    final exists = categories.any((c) => c.id == lastUsed);
    _categoryId = exists ? lastUsed : categories.first.id;
    _defaulted = true;
  }

  Widget _titleBar(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close',
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: palette.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.close, size: 16),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEdit ? 'Edit expense' : 'New expense',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  Widget _subLine(
    BuildContext context,
    CategoryRow? selected,
    AppPalette palette,
  ) {
    final label = selected?.name ?? 'Select category';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Center(
        child: Text(
          '$label · Today',
          style: TextStyle(color: palette.textDim, fontSize: 13),
        ),
      ),
    );
  }

  Widget _categoryGrid(List<CategoryRow> categories) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final showMore = categories.length > _gridCap;
    final visible = showMore
        ? visibleCategoryTiles(categories, _categoryId)
        : categories;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visible.length + (showMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
      ),
      itemBuilder: (context, i) {
        if (showMore && i == visible.length) {
          return Semantics(
            button: true,
            label: 'More categories',
            child: GestureDetector(
              onTap: () => _openCategoryPicker(categories),
              child: _CategoryTile(
                glyph: Icon(
                  Icons.grid_view_rounded,
                  size: 22,
                  color: palette.textDim,
                ),
                name: 'More',
                selected: false,
              ),
            ),
          );
        }
        final c = visible[i];
        final sel = c.id == _categoryId;
        return Semantics(
          button: true,
          selected: sel,
          label: c.name,
          child: GestureDetector(
            onTap: () => setState(() => _categoryId = c.id),
            child: _CategoryTile(
              glyph: CategoryGlyph(c.icon, size: 22),
              name: c.name,
              selected: sel,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCategoryPicker(List<CategoryRow> categories) async {
    final chosen = await showModalBottomSheet<CategoryRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('All categories'),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    return ListTile(
                      leading: CategoryGlyph(c.icon, size: 20),
                      title: Text(c.name),
                      trailing: c.id == _categoryId
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _categoryId = chosen.id);
  }

  Widget _saveButton(BuildContext context) {
    final label = _isEdit ? 'Save changes' : 'Save expense';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: _save,
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

  Future<void> _save() async {
    final amount = Money.parse(_amount);
    if (amount.minor <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount and pick a category')),
      );
      return;
    }
    final categoryId = _categoryId!;
    final oldAmount = widget.editing?.amount ?? Money.zero;
    final repo = ref.read(expenseRepositoryProvider);
    if (_isEdit) {
      await repo.update(
        widget.editing!.id,
        amount: amount,
        categoryId: categoryId,
      );
    } else {
      await repo.add(amount: amount, categoryId: categoryId);
    }
    // Fire budget-threshold alerts for the affected category + overall (FR-25).
    // Only the delta counts toward the "before → after" crossing so an edit
    // that keeps the same category alerts on its net change.
    final sameCategory = _isEdit && widget.editing!.categoryId == categoryId;
    final delta = sameCategory ? amount - oldAmount : amount;
    await _checkBudgetAlerts(categoryId, delta);
    await refreshWidgets(
      ref,
    ); // FR-29: keep the home/lock-screen widgets current
    if (mounted) Navigator.of(context).pop();
  }

  /// After a write, compare category + overall month totals against their
  /// budgets and notify on each newly crossed 80% / 100% line.
  Future<void> _checkBudgetAlerts(int categoryId, Money delta) async {
    if (delta.minor <= 0) return; // only rising spend can cross a threshold
    final expenses = ref.read(expenseRepositoryProvider);
    final (start, end) = monthBounds(DateTime.now());
    final byCategory = await expenses.totalsByCategory(start, end);
    final notifier = ref.read(notificationServiceProvider);

    // Per-category budget.
    final catBudget = ref.read(perCategoryBudgetsProvider)[categoryId];
    if (catBudget != null) {
      final after = byCategory[categoryId] ?? Money.zero;
      final name =
          ref.read(categoriesByIdProvider)[categoryId]?.name ?? 'Category';
      for (final pct in crossedThresholds(after - delta, after, catBudget)) {
        await notifier.showBudgetAlert(name, pct);
      }
    }

    // Overall budget.
    final overall = ref.read(overallBudgetProvider).value;
    if (overall != null) {
      final after = byCategory.values.fold(Money.zero, (a, m) => a + m);
      for (final pct in crossedThresholds(after - delta, after, overall)) {
        await notifier.showBudgetAlert('Overall', pct);
      }
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.glyph,
    required this.name,
    required this.selected,
  });

  final Widget glyph;
  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.10)
                : palette.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: selected ? AppColors.primary : palette.line,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph,
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : palette.textDim,
                ),
              ),
            ],
          ),
        ),
        // Selection isn't color-only: a checkmark badge marks the selected
        // tile too.
        if (selected)
          const Positioned(
            top: 3,
            right: 3,
            child: Icon(Icons.check_circle, size: 14, color: AppColors.primary),
          ),
      ],
    );
  }
}
