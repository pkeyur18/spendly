import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import '../budgets/budget_repository.dart';
import 'category_manager_screen.dart';
import 'category_repository.dart';

/// Archived categories (FR-11) — hidden from Quick Add, recoverable via
/// Unarchive, or permanently removable via Delete, both in [CategoryEditSheet]
/// reached by tapping a row.
class ArchivedCategoriesScreen extends ConsumerWidget {
  const ArchivedCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final budgets = ref.watch(perCategoryBudgetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Archived categories')),
      body: categoriesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'Couldn\'t load categories.',
          onRetry: () => ref.invalidate(allCategoriesProvider),
        ),
        data: (categories) {
          final archived = categories.where((c) => c.isArchived).toList();
          if (archived.isEmpty) {
            return const EmptyView(
              icon: Icons.archive_outlined,
              message: 'No archived categories.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              for (final c in archived)
                CategoryListTile(
                  key: ValueKey(c.id),
                  category: c,
                  budget: budgets[c.id],
                  reorderIndex: null,
                ),
            ],
          );
        },
      ),
    );
  }
}
