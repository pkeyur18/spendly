import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/async_state_views.dart';
import 'goal_repository.dart';

/// Savings goals (Phase 7) — a target amount the user is putting money
/// aside for, with a manually-adjusted running total. Reached from Profile,
/// same shape as Accounts/Income.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeGoalsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings goals'),
        actions: [
          IconButton(
            tooltip: 'Add goal',
            onPressed: () => showGoalEditSheet(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load goals.",
          onRetry: () => ref.invalidate(activeGoalsProvider),
        ),
        data: (goals) {
          if (goals.isEmpty) {
            return const EmptyView(
              icon: Icons.flag_outlined,
              message:
                  'No savings goals yet. Tap + to set your first target.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              for (final g in goals) _GoalTile(goal: g),
            ],
          );
        },
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});
  final SavingsGoalRow goal;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => GoalDetailScreen(goal: goal))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    goal.isComplete ? Icons.emoji_events_outlined : Icons.flag_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    goal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${goal.saved.format(locale: 'en_IN')} / '
                  '${goal.target.format(locale: 'en_IN')}',
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progressRatio,
                minHeight: 6,
                backgroundColor: palette.line,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goal});
  final SavingsGoalRow goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    // Re-reads the live row from the active-goals stream so the screen
    // reflects contributions made from here without a manual refresh; falls
    // back to the row passed in until the stream's first emission arrives.
    final live = ref
        .watch(activeGoalsProvider)
        .value
        ?.where((g) => g.id == goal.id)
        .cast<SavingsGoalRow?>()
        .firstOrNull ??
        goal;
    final remaining = Money.fromMinor(
      (live.targetMinor - live.savedMinor).clamp(0, 1 << 62),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(live.name),
        actions: [
          IconButton(
            tooltip: 'Edit goal',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGoalEditSheet(context, existing: live),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.isComplete ? 'Goal reached! 🎉' : 'Saved so far',
                  style: TextStyle(fontSize: 13, color: palette.textDim),
                ),
                const SizedBox(height: 4),
                Text(
                  live.saved.format(locale: 'en_IN'),
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: live.progressRatio,
                    minHeight: 8,
                    backgroundColor: palette.line,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  live.isComplete
                      ? 'Target ${live.target.format(locale: 'en_IN')}'
                      : '${remaining.format(locale: 'en_IN')} left of '
                          '${live.target.format(locale: 'en_IN')}',
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showAdjustDialog(context, ref, live, isAdd: true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add money'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: live.savedMinor <= 0
                      ? null
                      : () => _showAdjustDialog(context, ref, live, isAdd: false),
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Withdraw'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAdjustDialog(
    BuildContext context,
    WidgetRef ref,
    SavingsGoalRow goal, {
    required bool isAdd,
  }) async {
    final controller = TextEditingController();
    final amount = await showDialog<Money>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isAdd ? 'Add money' : 'Withdraw'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = Money.parse(controller.text);
              if (parsed.minor <= 0) return;
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    await ref
        .read(goalRepositoryProvider)
        .adjustSaved(goal.id, isAdd ? amount : Money.fromMinor(-amount.minor));
  }
}

/// Create (no [existing]) or edit a goal: name, target amount, archive.
Future<int?> showGoalEditSheet(BuildContext context, {SavingsGoalRow? existing}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _GoalEditSheet(existing: existing),
  );
}

class _GoalEditSheet extends ConsumerStatefulWidget {
  const _GoalEditSheet({this.existing});
  final SavingsGoalRow? existing;

  @override
  ConsumerState<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends ConsumerState<_GoalEditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _target = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.target.major.toStringAsFixed(2),
  );
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a goal name')));
      return;
    }
    final target = Money.parse(_target.text);
    if (target.minor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a target amount')));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(goalRepositoryProvider);
    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.update(id, name: name, target: target);
    } else {
      id = await repo.create(name: name, target: target);
    }
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _archive() async {
    await ref.read(goalRepositoryProvider).setArchived(widget.existing!.id, true);
    if (!mounted) return;
    Navigator.of(context)
      ..pop() // the edit sheet
      ..pop(); // the detail screen — nothing left to show for an archived goal
  }

  Widget _saveButton() {
    return Semantics(
      button: true,
      label: _saving ? 'Saving' : 'Save goal',
      child: GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          alignment: Alignment.center,
          child: Text(
            _saving ? 'Saving…' : 'Save',
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Edit goal' : 'New savings goal',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _name,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Goal name',
                  hintText: 'e.g. New laptop, Emergency fund',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Target amount',
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _saveButton(),
              if (_isEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _archive,
                    child: const Text('Archive this goal'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
