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
import 'archived_categories_screen.dart';
import 'category_edit_sheet.dart';
import 'category_repository.dart';

/// Category Manager (FR-9,10,11) — prototype phone 5. Reorder via drag,
/// tap to edit (rename/icon/color/archive). Archived categories live on
/// their own screen (see [ArchivedCategoriesScreen]).
class CategoryManagerScreen extends ConsumerWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final budgets = ref.watch(perCategoryBudgetsProvider);
    final archivedCount =
        categoriesAsync.value?.where((c) => c.isArchived).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'Archived categories',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ArchivedCategoriesScreen(),
              ),
            ),
            icon: Badge(
              isLabelVisible: archivedCount > 0,
              label: Text('$archivedCount'),
              child: const Icon(Icons.archive_outlined),
            ),
          ),
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
          final active = categories.where((c) => !c.isArchived).toList();
          if (active.isEmpty) {
            return const EmptyView(
              icon: Icons.sell_outlined,
              message:
                  'No active categories — tap + to add one, or check Archived.',
            );
          }
          return ReorderableListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(ref, active, oldIndex, newIndex),
            children: [
              for (var i = 0; i < active.length; i++)
                CategoryListTile(
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

class CategoryListTile extends StatelessWidget {
  const CategoryListTile({
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

    return Padding(
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
    );
  }
}
