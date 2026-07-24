import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/category_glyph.dart';
import 'category_repository.dart';

/// Curated emoji set for the icon picker (FR-10) — no emoji-keyboard dependency.
const _iconChoices = [
  '🍔',
  '🚕',
  '🛒',
  '🧾',
  '🎬',
  '💊',
  '🏠',
  '📦',
  '☕',
  '🍺',
  '🎁',
  '✈️',
  '⛽',
  '📱',
  '💡',
  '👕',
  '🏥',
  '🎓',
  '🐶',
  '💇',
  '🏋️',
  '🎮',
  '📚',
  '🚌',
  '💳',
  '💰',
  '🍎',
  '🌮',
  '🎧',
  '🛍️',
  '🏦',
  '🛡️',
  '📺',
  '🌐',
  '💧',
  '🅿️',
  '🚗',
  '📈',
  '💼',
  '🎗️',
  '👶',
  '🐾',
  '🧺',
  '🖥️',
  '🎂',
  '🧳',
  '🍕',
  '🧧',
  '🔧',
  '🧴',
];

/// Brand palette swatches for the color picker (FR-9).
const _colorChoices = [
  AppColors.primary,
  AppColors.primaryDeep,
  AppColors.primarySoft,
  AppColors.accent,
  AppColors.pink,
  AppColors.teal,
  AppColors.red,
  AppColors.lightTextDim,
];

/// Add/edit a category. [existing] null = create mode. Save/archive/unarchive
/// go through [CategoryRepository]; archive never deletes (FR-11).
class CategoryEditSheet extends ConsumerStatefulWidget {
  const CategoryEditSheet({super.key, this.existing});

  final CategoryRow? existing;

  @override
  ConsumerState<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String _icon = widget.existing?.icon ?? _iconChoices.first;
  late int _color =
      widget.existing?.colorValue ?? _colorChoices.first.toARGB32();

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit category' : 'New category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Icon',
              style: TextStyle(color: palette.textDim, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _iconChoices)
                  Semantics(
                    button: true,
                    selected: _icon == e,
                    label: 'Icon $e',
                    child: GestureDetector(
                      onTap: () => setState(() => _icon = e),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _icon == e
                                  ? Color(_color).withValues(alpha: 0.15)
                                  : palette.card,
                              borderRadius: BorderRadius.circular(
                                AppRadius.icon,
                              ),
                              border: Border.all(
                                color: _icon == e
                                    ? Color(_color)
                                    : palette.line,
                                width: _icon == e ? 1.6 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: CategoryGlyph(e, size: 18),
                          ),
                          // Selection isn't color-only: a checkmark badge too.
                          if (_icon == e)
                            Positioned(
                              top: -3,
                              right: -3,
                              child: Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Color(_color),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Color',
              style: TextStyle(color: palette.textDim, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, c) in _colorChoices.indexed)
                  Semantics(
                    button: true,
                    selected: _color == c.toARGB32(),
                    label: 'Color option ${i + 1}',
                    child: GestureDetector(
                      onTap: () => setState(() => _color = c.toARGB32()),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c.toARGB32()
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        // Selection isn't color-only: a checkmark on top too.
                        child: _color == c.toARGB32()
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: c.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _saveButton(),
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.sm),
              _archiveButton(palette),
              const SizedBox(height: AppSpacing.sm),
              _deleteButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _saveButton() {
    return Semantics(
      button: true,
      label: 'Save category',
      child: GestureDetector(
        onTap: _save,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Save',
            style: TextStyle(
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

  Widget _archiveButton(AppPalette palette) {
    final archived = widget.existing!.isArchived;
    return TextButton(
      onPressed: () async {
        final repo = ref.read(categoryRepositoryProvider);
        archived
            ? await repo.unarchive(widget.existing!.id)
            : await repo.archive(widget.existing!.id);
        if (mounted) Navigator.of(context).pop();
      },
      child: Text(
        archived ? 'Unarchive' : 'Archive (hide from Quick Add)',
        style: TextStyle(color: palette.textDim),
      ),
    );
  }

  Widget _deleteButton() {
    return TextButton(
      onPressed: _confirmDelete,
      child: const Text(
        'Delete category',
        style: TextStyle(color: AppColors.red),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final resolved = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteCategoryDialog(categoryId: widget.existing!.id),
    );
    if (resolved == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a name')));
      return;
    }
    final repo = ref.read(categoryRepositoryProvider);
    if (_isEdit) {
      final id = widget.existing!.id;
      await repo.rename(id, name);
      await repo.setIcon(id, _icon);
      await repo.recolor(id, _color);
    } else {
      await repo.create(name: name, icon: _icon, colorValue: _color);
    }
    if (mounted) Navigator.of(context).pop();
  }
}

enum _DeletePhase { confirm, deleting, blocked }

/// Confirm-then-delete, morphing in place into a "can't delete" state when
/// the category is still referenced by an expense — one continuous dialog
/// instead of a confirm dialog followed by a separate SnackBar.
class _DeleteCategoryDialog extends ConsumerStatefulWidget {
  const _DeleteCategoryDialog({required this.categoryId});

  final int categoryId;

  @override
  ConsumerState<_DeleteCategoryDialog> createState() =>
      _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends ConsumerState<_DeleteCategoryDialog> {
  _DeletePhase _phase = _DeletePhase.confirm;
  int _blockedCount = 0;

  Future<void> _attemptDelete() async {
    setState(() => _phase = _DeletePhase.deleting);
    final blockedCount = await ref
        .read(categoryRepositoryProvider)
        .tryDelete(widget.categoryId);
    if (!mounted) return;
    if (blockedCount == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _phase = _DeletePhase.blocked;
        _blockedCount = blockedCount;
      });
    }
  }

  Future<void> _archiveInstead() async {
    await ref.read(categoryRepositoryProvider).archive(widget.categoryId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _DeletePhase.blocked) {
      final word = _blockedCount == 1 ? 'expense' : 'expenses';
      return AlertDialog(
        title: const Text("Can't delete category"),
        content: Text(
          '$_blockedCount $word use this category. Archive it instead to '
          'hide it from Quick Add, or keep it as is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep category'),
          ),
          FilledButton(
            onPressed: _archiveInstead,
            child: const Text('Archive instead'),
          ),
        ],
      );
    }

    final deleting = _phase == _DeletePhase.deleting;
    return AlertDialog(
      title: const Text('Delete category?'),
      content: const Text('This can\'t be undone.'),
      actions: [
        TextButton(
          onPressed: deleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: deleting ? null : _attemptDelete,
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}

/// Open the add/edit sheet as a modal bottom sheet.
Future<void> showCategoryEditSheet(
  BuildContext context, {
  CategoryRow? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => CategoryEditSheet(existing: existing),
  );
}
