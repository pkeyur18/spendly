import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/theme/app_theme.dart';
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

/// Curated swatches for the color picker (FR-9) — see [AppColors.swatchPalette].
const _colorChoices = AppColors.swatchPalette;

const _stripPreviewCount = 6;

/// Preview strip contents for [selected] out of [all]: the selected item
/// pinned first, then the next items from [all] in their existing order
/// (skipping a duplicate of the selected item), capped at [max].
/// [overflowCount] is how many more items exist beyond what's shown.
({List<T> items, int overflowCount}) previewStripItems<T>(
  List<T> all,
  T selected, {
  int max = _stripPreviewCount,
}) {
  final items = <T>[selected];
  for (final item in all) {
    if (items.length >= max) break;
    if (item == selected) continue;
    items.add(item);
  }
  final totalDistinct = all.contains(selected) ? all.length : all.length + 1;
  return (items: items, overflowCount: totalDistinct - items.length);
}

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
    final otherCategories = ref
        .watch(allCategoriesProvider)
        .value
        ?.where((c) => c.id != widget.existing?.id);
    final usedColors = <int, String>{
      for (final c in otherCategories ?? const <CategoryRow>[])
        c.colorValue: c.name,
    };
    final isPreset = _colorChoices.any((c) => c.toARGB32() == _color);
    final duplicateOwner = usedColors[_color];
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
            _previewStrip<String>(
              all: _iconChoices,
              selected: _icon,
              tileBuilder: (icon) => _iconTile(
                icon,
                palette,
                onTap: () => setState(() => _icon = icon),
              ),
              overflowTileBuilder: (count) =>
                  _overflowChip(count, palette, circle: false, onTap: _openIconPicker),
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
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
                          // Already-in-use marker, separate from selection.
                          if (usedColors.containsKey(c.toARGB32()))
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: palette.textDim,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: palette.card,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  selected: !isPreset,
                  label: 'Custom color',
                  child: GestureDetector(
                    onTap: _showCustomColorPicker,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isPreset ? palette.card : Color(_color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: !isPreset
                              ? Theme.of(context).colorScheme.onSurface
                              : palette.line,
                          width: !isPreset ? 2.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isPreset
                          ? Icon(
                              Icons.palette_outlined,
                              size: 16,
                              color: palette.textDim,
                            )
                          : Icon(
                              Icons.check,
                              size: 16,
                              color: Color(_color).computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            ),
                    ),
                  ),
                ),
              ],
            ),
            if (duplicateOwner != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Already used by $duplicateOwner',
                style: const TextStyle(color: AppColors.red, fontSize: 12),
              ),
            ],
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

  Widget _iconTile(
    String icon,
    AppPalette palette, {
    required VoidCallback onTap,
  }) {
    final selected = icon == _icon;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Icon $icon',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? Color(_color).withValues(alpha: 0.15)
                    : palette.card,
                borderRadius: BorderRadius.circular(AppRadius.icon),
                border: Border.all(
                  color: selected ? Color(_color) : palette.line,
                  width: selected ? 1.6 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: CategoryGlyph(icon, size: 18),
            ),
            if (selected)
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
    );
  }

  Widget _previewStrip<T>({
    required List<T> all,
    required T selected,
    required Widget Function(T item) tileBuilder,
    required Widget Function(int overflowCount) overflowTileBuilder,
  }) {
    final strip = previewStripItems(all, selected);
    return Row(
      children: [
        for (final item in strip.items) ...[
          tileBuilder(item),
          const SizedBox(width: 8),
        ],
        if (strip.overflowCount > 0) overflowTileBuilder(strip.overflowCount),
      ],
    );
  }

  Widget _overflowChip(
    int count,
    AppPalette palette, {
    required bool circle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: 'Show all, $count more',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: circle ? 34 : 42,
          height: circle ? 34 : 42,
          decoration: BoxDecoration(
            color: palette.card,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(AppRadius.icon),
            border: Border.all(color: palette.line),
          ),
          alignment: Alignment.center,
          child: Text(
            '+$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.textDim,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openIconPicker() async {
    final palette = Theme.of(context).extension<AppPalette>()!;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (popupContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg + MediaQuery.of(popupContext).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in _iconChoices)
                _iconTile(
                  icon,
                  palette,
                  onTap: () {
                    setState(() => _icon = icon);
                    Navigator.of(popupContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomColorPicker() async {
    Color picked = Color(_color);
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Custom color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: Color(_color),
              onColorChanged: (c) => picked = c,
              enableAlpha: false,
              labelTypes: const [ColorLabelType.hex],
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(picked),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _color = result.toARGB32());
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
      return Theme(
        data: AppTheme.boldDialogActions(context),
        child: AlertDialog(
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
        ),
      );
    }

    final deleting = _phase == _DeletePhase.deleting;
    return Theme(
      data: AppTheme.boldDialogActions(context),
      child: AlertDialog(
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
      ),
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
