import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'category_glyph.dart';
import 'glass.dart';

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

/// Icon + color pickers with a shared "preview strip, tap to see more"
/// interaction — originally Categories' own, extracted so Accounts' custom
/// type can look and feel identical rather than growing a near-duplicate.
/// Purely presentational plus the picker-sheet/custom-color-dialog flows;
/// the actual selection lives in the parent, reported back via the
/// on*Changed callbacks (a controlled component, not internal state).
class IconColorPicker extends StatelessWidget {
  const IconColorPicker({
    super.key,
    required this.iconChoices,
    required this.selectedIcon,
    required this.onIconChanged,
    required this.colorChoices,
    required this.selectedColor,
    required this.onColorChanged,
    this.usedColors = const {},
  });

  final List<String> iconChoices;
  final String selectedIcon;
  final ValueChanged<String> onIconChanged;

  final List<Color> colorChoices;
  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  /// colorValue -> owner name, for the "already used by X" hint under the
  /// color strip. Empty (the default) shows no hint and flags no tile.
  final Map<int, String> usedColors;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final duplicateOwner = usedColors[selectedColor];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Icon', style: TextStyle(color: palette.textDim, fontSize: 13)),
        const SizedBox(height: AppSpacing.sm),
        _previewStrip<String>(
          all: iconChoices,
          selected: selectedIcon,
          tileBuilder: (icon) =>
              _iconTile(context, icon, onTap: () => onIconChanged(icon)),
          overflowTileBuilder: (count) => _overflowChip(
            context,
            count,
            circle: false,
            onTap: () => _openIconPicker(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Color', style: TextStyle(color: palette.textDim, fontSize: 13)),
        const SizedBox(height: AppSpacing.sm),
        _previewStrip<Color>(
          all: colorChoices,
          selected: Color(selectedColor),
          tileBuilder: (color) => _colorTile(
            context,
            color,
            onTap: () => onColorChanged(color.toARGB32()),
          ),
          overflowTileBuilder: (count) => _overflowChip(
            context,
            count,
            circle: true,
            onTap: () => _openColorPicker(context),
          ),
        ),
        if (duplicateOwner != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Already used by $duplicateOwner',
            style: const TextStyle(color: AppColors.red, fontSize: 12),
          ),
        ],
      ],
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

  Widget _iconTile(
    BuildContext context,
    String icon, {
    required VoidCallback onTap,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final selected = icon == selectedIcon;
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
                    ? Color(selectedColor).withValues(alpha: 0.15)
                    : palette.card,
                borderRadius: BorderRadius.circular(AppRadius.icon),
                border: Border.all(
                  color: selected ? Color(selectedColor) : palette.line,
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
                  color: Color(selectedColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _colorTile(
    BuildContext context,
    Color color, {
    required VoidCallback onTap,
  }) {
    final selected = selectedColor == color.toARGB32();
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color ${color.toARGB32().toRadixString(16)}',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
            if (usedColors.containsKey(color.toARGB32()))
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).extension<AppPalette>()!.textDim,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).extension<AppPalette>()!.card,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _customColorTile(BuildContext context, {required VoidCallback onTap}) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final isPreset = colorChoices.any((c) => c.toARGB32() == selectedColor);
    return Semantics(
      button: true,
      selected: !isPreset,
      label: 'Custom color',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isPreset ? palette.card : Color(selectedColor),
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
              ? Icon(Icons.palette_outlined, size: 16, color: palette.textDim)
              : Icon(
                  Icons.check,
                  size: 16,
                  color: Color(selectedColor).computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
        ),
      ),
    );
  }

  Widget _overflowChip(
    BuildContext context,
    int count, {
    required bool circle,
    required VoidCallback onTap,
  }) {
    final palette = Theme.of(context).extension<AppPalette>()!;
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

  Future<void> _openIconPicker(BuildContext context) async {
    await showGlassSheet<void>(
      context,
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
              for (final icon in iconChoices)
                _iconTile(
                  popupContext,
                  icon,
                  onTap: () {
                    onIconChanged(icon);
                    Navigator.of(popupContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openColorPicker(BuildContext context) async {
    await showGlassSheet<void>(
      context,
      builder: (popupContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg + MediaQuery.of(popupContext).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in colorChoices)
                _colorTile(
                  popupContext,
                  color,
                  onTap: () {
                    onColorChanged(color.toARGB32());
                    Navigator.of(popupContext).pop();
                  },
                ),
              _customColorTile(
                popupContext,
                onTap: () {
                  Navigator.of(popupContext).pop();
                  _showCustomColorPicker(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomColorPicker(BuildContext context) async {
    Color picked = Color(selectedColor);
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Custom color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: Color(selectedColor),
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
    if (result != null) onColorChanged(result.toARGB32());
  }
}
