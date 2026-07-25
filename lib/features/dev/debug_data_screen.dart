import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';

/// ponytail: throwaway data-layer harness for Sprint 1 verification. Replaced by
/// real Quick Add (Sprint 2) + Category Manager (Sprint 3). kDebugMode-gated.
class DebugDataScreen extends ConsumerWidget {
  const DebugDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(allCategoriesProvider);
    final expenses = ref.watch(currentMonthExpensesProvider);
    final total = ref.watch(currentMonthTotalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Debug · data layer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          total.when(
            data: (m) => Text(
              'This month total: ${m.format(locale: 'en_IN')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            loading: () => const Text('…'),
            error: (e, _) => Text('err: $e'),
          ),
          const Divider(height: 32),
          Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          categories.when(
            data: (rows) => Column(
              children: [
                for (final c in rows)
                  ListTile(
                    dense: true,
                    leading: Text(c.icon, style: const TextStyle(fontSize: 20)),
                    title: Text(c.name),
                    subtitle: Text(c.isArchived ? 'archived' : 'active'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_card, size: 20),
                          tooltip: 'Add ₹100 expense here',
                          onPressed: () => ref
                              .read(expenseRepositoryProvider)
                              .add(
                                amount: Money.parse('100'),
                                categoryId: c.id,
                              ),
                        ),
                        IconButton(
                          icon: Icon(
                            c.isArchived ? Icons.unarchive : Icons.archive,
                            size: 20,
                          ),
                          onPressed: () {
                            final repo = ref.read(categoryRepositoryProvider);
                            c.isArchived
                                ? repo.unarchive(c.id)
                                : repo.archive(c.id);
                          },
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add "Test" category'),
                  onPressed: () => ref
                      .read(categoryRepositoryProvider)
                      .create(name: 'Test', icon: '⭐', colorValue: 0xFF6366F1),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text('err: $e'),
          ),
          const Divider(height: 32),
          Text(
            'This month expenses',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          expenses.when(
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('none yet'),
                  )
                : Column(
                    children: [for (final e in rows) _expenseTile(ref, e)],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text('err: $e'),
          ),
        ],
      ),
    );
  }

  Widget _expenseTile(WidgetRef ref, ExpenseRow e) {
    return ListTile(
      dense: true,
      title: Text(e.amount.format(locale: 'en_IN')),
      subtitle: Text('cat ${e.categoryId} · ${e.date.toIso8601String()}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: '+₹50 (edit)',
            onPressed: () => ref
                .read(expenseRepositoryProvider)
                .update(e.id, amount: e.amount + Money.parse('50')),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => ref.read(expenseRepositoryProvider).delete(e.id),
          ),
        ],
      ),
    );
  }
}
