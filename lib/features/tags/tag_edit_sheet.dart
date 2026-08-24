import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/money/currencies.dart';
import '../../core/money/fx.dart';
import '../../core/money/fx_rate_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass.dart';
import 'currency_picker_screen.dart';
import 'tag_repository.dart';

/// Add/edit a trip/tag. [existing] null = create mode. Archive hides it from
/// the picker; Delete removes the trip and silently untags its expenses
/// (never deletes them) — see [TagRepository.delete].
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

  /// Travel state. [_fxCurrency] null = an ordinary tag. The rate lives in a
  /// controller because it is a plain editable field — a fetched rate is only
  /// ever a prefill.
  late String? _fxCurrency = widget.existing?.fxCurrency;
  late final TextEditingController _rate = TextEditingController(
    text: widget.existing?.fxRateMicros == null
        ? ''
        : rateToString(widget.existing!.fxRateMicros!),
  );
  bool _fetching = false;

  /// True once a fetch came back empty, so the caption can say "type it"
  /// instead of pretending a rate is on the way.
  bool _fetchFailed = false;

  /// Trip date range for auto-tagging — independent of the currency switch,
  /// so a domestic trip can use this without ever touching [_fxCurrency].
  late DateTime? _tripStart = widget.existing?.tripStartDate;
  late DateTime? _tripEnd = widget.existing?.tripEndDate;

  bool get _isEdit => widget.existing != null;
  bool get _isTravel => _fxCurrency != null;
  bool get _hasTripDates => _tripStart != null && _tripEnd != null;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// Picking a currency kicks off one fetch. Offline or a failed call leaves
  /// the field empty and the save path still works — being offline abroad is
  /// the normal case, not an error.
  Future<void> _pickCurrency(String code) async {
    setState(() {
      _fxCurrency = code;
      _rate.clear();
      _fetching = true;
      _fetchFailed = false;
    });
    final micros = await ref.read(fxRateServiceProvider).fetchRateMicros(code);
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _fetchFailed = micros == null;
      if (micros != null) _rate.text = rateToString(micros);
    });
  }

  /// Blocks changing the currency once expenses exist — a trip mixing two
  /// currencies makes its own total meaningless. Changing the RATE is always
  /// allowed (that is the documented mid-trip behavior).
  Future<bool> _canChangeCurrency() async {
    if (!_isEdit || widget.existing!.fxCurrency == null) return true;
    final hasExpenses = await ref
        .read(tagRepositoryProvider)
        .hasExpenses(widget.existing!.id);
    if (!hasExpenses) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Currency is locked'),
        content: Text(
          'This trip already has expenses in ${widget.existing!.fxCurrency}. '
          'Create a new trip for a different currency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
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
            const SizedBox(height: AppSpacing.lg),
            _travelSection(palette),
            const SizedBox(height: AppSpacing.lg),
            _tripDatesSection(palette),
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

  /// The travel switch and, when on, the currency picker + rate field.
  /// Everything above this in the sheet behaves identically whether or not a
  /// tag is a trip abroad.
  Widget _travelSection(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isTravel,
          title: const Text(
            'Spending in another currency',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'For trips abroad',
            style: TextStyle(color: palette.textDim, fontSize: 12),
          ),
          onChanged: (on) async {
            if (!on) {
              if (!await _canChangeCurrency()) return;
              setState(() {
                _fxCurrency = null;
                _rate.clear();
                _fetchFailed = false;
              });
              return;
            }
            if (!await _canChangeCurrency()) return;
            if (mounted) await _showCurrencyPicker();
          },
        ),
        if (_isTravel) ...[
          const SizedBox(height: AppSpacing.sm),
          _currencyRow(palette),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '1 $_fxCurrency equals',
              suffixText: homeCurrencyCode,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _rateCaption(palette),
        ],
      ],
    );
  }

  Widget _currencyRow(AppPalette palette) {
    final option = currencyFor(_fxCurrency);
    return InkWell(
      onTap: () async {
        if (!await _canChangeCurrency()) return;
        if (mounted) await _showCurrencyPicker();
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Currency',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Text(option?.flag ?? '🌐', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(option?.name ?? _fxCurrency!)),
            Text(
              _fxCurrency!,
              style: TextStyle(
                color: palette.textDim,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Icon(Icons.expand_more, color: palette.textDim, size: 20),
          ],
        ),
      ),
    );
  }

  /// Says what the rate field currently is: fetching, fetched, or yours to
  /// type. A failed fetch is stated plainly, not raised as an error.
  Widget _rateCaption(AppPalette palette) {
    final (text, color) = switch ((_fetching, _fetchFailed)) {
      (true, _) => ('Fetching today\'s rate…', palette.textDim),
      (_, true) => ('Couldn\'t fetch a rate — enter today\'s rate', palette.textDim),
      _ => ('Today\'s rate — tap to change', AppColors.teal),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 11.5));
  }

  Future<void> _showCurrencyPicker() async {
    final picked = await showCurrencyPickerScreen(
      context,
      selected: _fxCurrency,
    );
    if (picked != null) await _pickCurrency(picked);
  }

  /// Trip dates: expenses logged on a day inside this range auto-attach to
  /// the trip in Quick Add, without picking it manually. Optional, and
  /// independent of the currency switch — a domestic weekend trip can use
  /// this too.
  Widget _tripDatesSection(AppPalette palette) {
    final df = DateFormat('MMM d, yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trip dates',
          style: TextStyle(color: palette.textDim, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          'Expenses logged on these days auto-attach to this trip',
          style: TextStyle(color: palette.textDim, fontSize: 11.5),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _dateField(
                label: 'Start date',
                text: _tripStart == null ? null : df.format(_tripStart!),
                onTap: () => _pickTripDate(isStart: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _dateField(
                label: 'End date',
                text: _tripEnd == null ? null : df.format(_tripEnd!),
                onTap: () => _pickTripDate(isStart: false),
              ),
            ),
          ],
        ),
        if (_tripStart != null || _tripEnd != null) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () =>
                setState(() {
                  _tripStart = null;
                  _tripEnd = null;
                }),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              'Clear dates',
              style: TextStyle(color: palette.textDim, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateField({
    required String label,
    required String? text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(text ?? 'Not set'),
      ),
    );
  }

  Future<void> _pickTripDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _tripStart : _tripEnd) ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _tripStart = picked;
      } else {
        _tripEnd = picked;
      }
    });
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

  Widget _deleteButton() {
    return TextButton(
      onPressed: _confirmDelete,
      child: const Text('Delete trip', style: TextStyle(color: AppColors.red)),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Delete trip?'),
          content: const Text(
            "Expenses tagged to this trip aren't deleted — they just lose "
            'this trip tag.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(tagRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a name')));
      return;
    }
    // A travel tag with no usable rate can't convert anything, so it isn't
    // saveable. Everything else about the tag stays optional.
    final rateMicros = _isTravel ? parseRateMicros(_rate.text) : null;
    if (_isTravel && rateMicros == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter how much 1 $_fxCurrency is worth')),
      );
      return;
    }

    if (_tripStart != null && _tripEnd != null && _tripEnd!.isBefore(_tripStart!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date is before the start date')),
      );
      return;
    }

    final repo = ref.read(tagRepositoryProvider);
    if (_hasTripDates) {
      final overlapsAnother = await repo.hasOverlappingDateRange(
        widget.existing?.id,
        _tripStart!,
        _tripEnd!,
      );
      if (overlapsAnother) {
        if (mounted) await _showOverlapDialog();
        return;
      }
    }

    final int id;
    if (_isEdit) {
      id = widget.existing!.id;
      await repo.rename(id, name);
      await repo.recolor(id, _color);
      await repo.setCurrency(id, _fxCurrency, rateMicros);
      await repo.setTripDates(id, _tripStart, _tripEnd);
    } else {
      id = await repo.create(
        name: name,
        colorValue: _color,
        fxCurrency: _fxCurrency,
        fxRateMicros: rateMicros,
        tripStartDate: _tripStart,
        tripEndDate: _tripEnd,
      );
    }
    if (mounted) Navigator.of(context).pop(id);
  }

  Future<void> _showOverlapDialog() async {
    final df = DateFormat('MMM d');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dates overlap another trip'),
        content: Text(
          '${df.format(_tripStart!)}–${df.format(_tripEnd!)} overlaps '
          'another active trip\'s dates. Two trips can\'t auto-tag the same '
          'day — adjust the range.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Open the add/edit sheet as a modal bottom sheet. Resolves to the
/// created/edited tag's id, or null if dismissed without saving.
Future<int?> showTagEditSheet(BuildContext context, {TagRow? existing}) {
  return showGlassSheet<int?>(
    context,
    builder: (_) => TagEditSheet(existing: existing),
  );
}
