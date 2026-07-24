import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/theme/tokens.dart';
import 'tag_repository.dart';

/// Add/edit a trip/tag. [existing] null = create mode. Save/archive/unarchive
/// go through [TagRepository]; archive never deletes, mirroring categories.
class TagEditSheet extends ConsumerStatefulWidget {
  const TagEditSheet({super.key, this.existing});

  final TagRow? existing;

  @override
  ConsumerState<TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends ConsumerState<TagEditSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late int _color =
      widget.existing?.colorValue ?? AppColors.swatchPalette.first.toARGB32();

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
              _isEdit ? 'Edit trip' : 'New trip',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Japan Trip 2026',
                border: OutlineInputBorder(),
              ),
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
                for (final c in AppColors.swatchPalette)
                  Semantics(
                    button: true,
                    selected: _color == c.toARGB32(),
                    label: 'Color option',
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _saveButton() {
    return Semantics(
      button: true,
      label: 'Save trip',
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
        final repo = ref.read(tagRepositoryProvider);
        archived
            ? await repo.unarchive(widget.existing!.id)
            : await repo.archive(widget.existing!.id);
        if (mounted) Navigator.of(context).pop();
      },
      child: Text(
        archived ? 'Unarchive' : 'Archive (hide from picker)',
        style: TextStyle(color: palette.textDim),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a name')));
      return;
    }
    final repo = ref.read(tagRepositoryProvider);
    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.rename(id, name);
      await repo.recolor(id, _color);
    } else {
      id = await repo.create(name: name, colorValue: _color);
    }
    if (mounted) Navigator.of(context).pop(id);
  }
}

/// Open the add/edit sheet as a modal bottom sheet. Resolves to the
/// created/edited tag's id, or null if dismissed without saving.
Future<int?> showTagEditSheet(BuildContext context, {TagRow? existing}) {
  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => TagEditSheet(existing: existing),
  );
}
