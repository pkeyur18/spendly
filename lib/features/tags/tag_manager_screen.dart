import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_state_views.dart';
import 'tag_edit_sheet.dart';
import 'tag_repository.dart';

/// Trip/Tag Manager — create, rename, recolor, archive trips. Archived trips
/// stay visible here (dimmed) so they can be unarchived; they're just hidden
/// from the expense-entry picker. Mirrors [CategoryManagerScreen] without
/// reordering (tags have no sort order).
class TagManagerScreen extends ConsumerWidget {
  const TagManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTagEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add trip'),
      ),
      body: tagsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: "Couldn't load trips.",
          onRetry: () => ref.invalidate(allTagsProvider),
        ),
        data: (tags) {
          if (tags.isEmpty) {
            return const EmptyView(
              icon: Icons.card_travel_outlined,
              message: 'No trips yet — tap + to track a vacation separately.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            children: [
              for (final tag in tags)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: TagListTile(tag: tag),
                ),
            ],
          );
        },
      ),
    );
  }
}

class TagListTile extends StatelessWidget {
  const TagListTile({super.key, required this.tag});

  final TagRow tag;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final color = Color(tag.colorValue);
    return Opacity(
      opacity: tag.isArchived ? 0.5 : 1,
      child: InkWell(
        onTap: () => showTagEditSheet(context, existing: tag),
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
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.card_travel_outlined, size: 18, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tag.isArchived ? 'Archived' : 'Active',
                      style: TextStyle(fontSize: 12, color: palette.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
