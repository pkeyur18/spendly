import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../budgets/budget_repository.dart';
import '../budgets/budget_setup_screen.dart';
import 'category_edit_sheet.dart';
import 'category_repository.dart';

/// Category Manager (FR-9,10,11) — prototype phone 5. Reorder via drag,
/// tap to edit (rename/icon/color/archive), archived rows dimmed at the bottom.
class CategoryManagerScreen extends ConsumerWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final budgets = ref.watch(perCategoryBudgetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'Budgets',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BudgetSetupScreen()),
            ),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: categoriesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Couldn\'t load categories.',
          onRetry: () => ref.invalidate(allCategoriesProvider),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyView(
              icon: Icons.sell_outlined,
              message: 'No categories yet — tap + to add one.',
            );
          }
          // Active first (kept in sortOrder), archived after.
          final active = categories.where((c) => !c.isArchived).toList();
          final archived = categories.where((c) => c.isArchived).toList();
          return ReorderableListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(ref, active, oldIndex, newIndex),
            footer: Column(
              children: [
                for (final c in archived)
                  _CategoryRow(
                    key: ValueKey('archived-${c.id}'),
                    category: c,
                    budget: budgets[c.id],
                    reorderIndex: null,
                  ),
              ],
            ),
            children: [
              for (var i = 0; i < active.length; i++)
                _CategoryRow(
                  key: ValueKey(active[i].id),
                  category: active[i],
                  budget: budgets[active[i].id],
                  reorderIndex: i,
                ),
            ],
          );
        },
      ),
    );
  }

  void _reorder(
    WidgetRef ref,
    List<CategoryRow> active,
    int oldIndex,
    int newIndex,
  ) {
    // onReorderItem already gives the post-removal index — no manual adjust.
    final ids = active.map((c) => c.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    ref.read(categoryRepositoryProvider).reorder(ids);
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.budget,
    required this.reorderIndex,
  });

  final CategoryRow category;
  final Money? budget;
  final int? reorderIndex; // null = archived (not draggable)

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final subtitle = category.isArchived
        ? 'Hidden from Quick Add'
        : (budget == null
              ? 'No budget set'
              : 'Budget: ${budget!.format(locale: 'en_IN')}/mo');

    return Opacity(
      opacity: category.isArchived ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: InkWell(
          onTap: () => showCategoryEditSheet(context, existing: category),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  alignment: Alignment.center,
                  child: CategoryGlyph(category.icon, size: 17),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                if (reorderIndex != null)
                  ReorderableDragStartListener(
                    index: reorderIndex!,
                    child: Icon(Icons.drag_handle, color: palette.textDim),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
