import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../categories/category_repository.dart';
import '../home/dashboard_providers.dart';
import 'expense_repository.dart';

/// Fast expense entry (FR-2, FR-5): keypad + category grid, ≤3-tap save.
/// Reused for editing (FR-6, FR-15) when [editing] is supplied.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.editing});

  final ExpenseRow? editing;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
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
    _categoryId = e?.categoryId;
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return Scaffold(
      body: SafeArea(
        child: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
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
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      _amountDisplay(context),
                      _subLine(context, selected, palette),
                      const SizedBox(height: AppSpacing.xl),
                      _categoryGrid(categories),
                      const SizedBox(height: AppSpacing.lg),
                      _keypad(palette),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(_isEdit ? 'Edit expense' : 'New expense',
              style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _amountDisplay(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 48,
            letterSpacing: -2,
          ),
          children: [
            TextSpan(text: '₹', style: TextStyle(color: palette.textDim, fontSize: 30)),
            TextSpan(
                text: _amount,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color)),
          ],
        ),
      ),
    );
  }

  Widget _subLine(BuildContext context, CategoryRow? selected, AppPalette palette) {
    final label = selected?.name ?? 'Select category';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Center(
        child: Text('$label · Today',
            style: TextStyle(color: palette.textDim, fontSize: 13)),
      ),
    );
  }

  Widget _categoryGrid(List<CategoryRow> categories) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
      ),
      itemBuilder: (context, i) {
        final c = categories[i];
        final sel = c.id == _categoryId;
        return GestureDetector(
          onTap: () => setState(() => _categoryId = c.id),
          child: _CategoryTile(category: c, selected: sel),
        );
      },
    );
  }

  Widget _keypad(AppPalette palette) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      childAspectRatio: 1.9,
      children: [
        for (final k in keys)
          GestureDetector(
            onTap: () => _tapKey(k),
            child: Container(
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.line),
              ),
              alignment: Alignment.center,
              child: k == 'del'
                  ? const Icon(Icons.backspace_outlined, size: 20)
                  : Text(k,
                      style: const TextStyle(
                          fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _saveButton(BuildContext context) {
    return GestureDetector(
      onTap: _save,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        alignment: Alignment.center,
        child: Text(_isEdit ? 'Save changes' : 'Save expense',
            style: const TextStyle(
                fontFamily: 'Sora',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _tapKey(String k) {
    setState(() {
      if (k == 'del') {
        _amount = _amount.length > 1 ? _amount.substring(0, _amount.length - 1) : '0';
      } else if (k == '.') {
        if (!_amount.contains('.')) _amount += '.';
      } else {
        // Block a 3rd decimal digit (money is 2 places).
        final dot = _amount.indexOf('.');
        if (dot >= 0 && _amount.length - dot > 2) return;
        _amount = _amount == '0' ? k : _amount + k;
      }
    });
  }

  Future<void> _save() async {
    final amount = Money.parse(_amount);
    if (amount.minor <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount and pick a category')),
      );
      return;
    }
    final repo = ref.read(expenseRepositoryProvider);
    if (_isEdit) {
      await repo.update(widget.editing!.id,
          amount: amount, categoryId: _categoryId);
    } else {
      await repo.add(amount: amount, categoryId: _categoryId!);
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected});

  final CategoryRow category;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.10) : palette.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(
          color: selected ? AppColors.primary : palette.line,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(category.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : palette.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
