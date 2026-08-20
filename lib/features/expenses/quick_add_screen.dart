import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/row_extensions.dart';
import '../../core/money/fx.dart';
import '../../core/money/fx_rate_service.dart' show homeCurrencyCode;
import '../../core/money/money.dart';
import '../../core/notify/notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/async_state_views.dart';
import '../../core/widgets/category_glyph.dart';
import '../budgets/budget_repository.dart';
import '../categories/category_repository.dart';
import '../home/dashboard_providers.dart';
import '../tags/tag_edit_sheet.dart';
import '../tags/tag_repository.dart';
import 'expense_repository.dart';
import 'widgets/expense_tile.dart' show relativeDayLabel;

/// Fast expense entry (FR-2, FR-5): keypad + category grid, ≤3-tap save.
/// Reused for editing (FR-6, FR-15) when [editing] is supplied.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.editing, this.initialCategoryId});

  final ExpenseRow? editing;

  /// Preselected category for a fresh entry (widget deep-link, FR-3). Ignored
  /// when [editing] is set (the edited expense's own category wins).
  final int? initialCategoryId;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

/// Categories shown in the quick-add grid before it switches to a
/// truncated view with a "More" tile.
const _gridCap = 8;
const _visibleWhenCapped = 7;

/// How far back an expense can be backdated.
const _backdateWindowDays = 90;

/// [firstDate, lastDate] bounds for the backdate picker: up to
/// [_backdateWindowDays] days before [now], never a future date.
(DateTime, DateTime) backdatePickerBounds(DateTime now) {
  return (
    now.subtract(const Duration(days: _backdateWindowDays)),
    DateTime(now.year, now.month, now.day),
  );
}

/// The active trip whose date range covers [date] (inclusive, date-only), or
/// null. Pure matching rule behind Quick Add's auto-tagging — pulled out as a
/// free function, same as [backdatePickerBounds] and [visibleCategoryTiles],
/// so it's unit-testable without a widget harness.
TagRow? tripForDate(List<TagRow> tags, DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  for (final t in tags) {
    if (t.tripStartDate == null || t.tripEndDate == null) continue;
    final start = DateTime(
      t.tripStartDate!.year,
      t.tripStartDate!.month,
      t.tripStartDate!.day,
    );
    final end = DateTime(
      t.tripEndDate!.year,
      t.tripEndDate!.month,
      t.tripEndDate!.day,
    );
    if (!d.isBefore(start) && !d.isAfter(end)) return t;
  }
  return null;
}

/// First [visibleCount] categories, with [selectedId] swapped into the last
/// slot if it would otherwise be cut off.
List<CategoryRow> visibleCategoryTiles(
  List<CategoryRow> categories,
  int? selectedId, {
  int visibleCount = _visibleWhenCapped,
}) {
  final visible = categories.take(visibleCount).toList();
  if (selectedId != null && !visible.any((c) => c.id == selectedId)) {
    final selected = categories
        .where((c) => c.id == selectedId)
        .cast<CategoryRow?>()
        .firstOrNull;
    if (selected != null) visible[visible.length - 1] = selected;
  }
  return visible;
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  late String _amount;

  /// What [_amount] was when the screen opened. Only used to tell a retyped
  /// amount from an untouched one — see [_resolveAmounts].
  late String _initialAmount;
  int? _categoryId;
  int? _tagId;
  late DateTime _selectedDate;
  bool _defaulted = false;

  /// Latest categories from the last build — read (not watched) in [_save]
  /// for the post-save confirmation's category name, since a fresh
  /// `ref.read` of the stream provider there could race a just-committed
  /// write (docs/architecture.md §8.1).
  List<CategoryRow> _categories = const [];

  /// True once the trip has been decided by the user rather than by
  /// auto-tagging — set on any explicit tag-picker action, including picking
  /// "No trip". [_applyAutoTag] never overrides it, so a manual removal
  /// stays removed even if the date still falls inside a trip's range.
  late bool _tagManuallySet = widget.editing?.tagId != null;
  final _noteController = TextEditingController();
  final _noteFocusNode = FocusNode();

  /// The note text when the screen opened — compared against the live
  /// controller text in [_isDirty], since note changes don't route through
  /// setState the way the other fields do.
  late String _initialNote;

  /// Set by any explicit user edit (keypad, category/date/trip pick). Auto
  /// defaults ([_applyDefaultCategory], [_applyAutoTag]) never set this, so
  /// closing an untouched form never prompts.
  bool _touched = false;

  bool get _isEdit => widget.editing != null;

  bool get _isDirty => _touched || _noteController.text.trim() != _initialNote;

  @override
  void initState() {
    super.initState();
    _noteFocusNode.addListener(() => setState(() {}));
    final e = widget.editing;
    // Prefill from the expense being edited; strip trailing ".00".
    _amount = e == null
        ? '0'
        : (e.amount.minor % 100 == 0
              ? (e.amount.minor ~/ 100).toString()
              : e.amount.major.toStringAsFixed(2));
    // The freeze rule (see _resolveAmounts) needs to know whether the user
    // actually retyped the amount, so remember what it started as.
    _initialAmount = _amount;
    _categoryId = e?.categoryId ?? widget.initialCategoryId;
    _tagId = e?.tagId;
    _selectedDate = e?.date ?? DateTime.now();
    _noteController.text = e?.note ?? '';
    _initialNote = _noteController.text;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return PopScope<void>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeOrConfirm(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: categoriesAsync.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              message: 'Couldn\'t load categories.',
              onRetry: () => ref.invalidate(activeCategoriesProvider),
            ),
            data: (categories) {
              _categories = categories;
              _applyDefaultCategory(categories);
              _applyAutoTag(
                ref.watch(activeTagsProvider).value ?? const <TagRow>[],
              );
              final selected = categories
                  .where((c) => c.id == _categoryId)
                  .cast<CategoryRow?>()
                  .firstOrNull;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Column(
                  children: [
                    _titleBar(context),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          AmountDisplay(_amount, symbol: _amountSymbol),
                          _conversionLine(palette),
                          _subLine(context, selected, palette),
                          const SizedBox(height: AppSpacing.sm),
                          Center(
                            child: Wrap(
                              spacing: AppSpacing.sm,
                              alignment: WrapAlignment.center,
                              children: [
                                _dateChip(context, palette),
                                _tripChip(context, palette),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _noteField(context, palette),
                          const SizedBox(height: AppSpacing.lg),
                          _categoryGrid(categories),
                        ],
                      ),
                    ),
                    // Keypad + save pinned to the bottom (not in the scroll view)
                    // so both stay reachable with one thumb regardless of how
                    // many categories are above.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.topCenter,
                            child: _noteFocusNode.hasFocus
                                ? const SizedBox.shrink()
                                : Column(
                                    children: [
                                      AmountKeypad(
                                        onKey: (k) => setState(() {
                                          _amount = applyAmountKey(_amount, k);
                                          _touched = true;
                                        }),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                  ),
                          ),
                          _saveButton(context),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _closeOrConfirm(BuildContext context) async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.boldDialogActions(dialogContext),
        child: AlertDialog(
          title: const Text('Discard this expense?'),
          content: const Text(
            'The amount, category, and other details you entered will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) Navigator.of(context).pop();
  }

  void _applyDefaultCategory(List<CategoryRow> categories) {
    if (_defaulted || _categoryId != null || categories.isEmpty) return;
    final lastUsed = ref.watch(lastUsedCategoryIdProvider);
    final exists = categories.any((c) => c.id == lastUsed);
    _categoryId = exists ? lastUsed : categories.first.id;
    _defaulted = true;
  }

  /// Re-evaluated on every build (unlike [_applyDefaultCategory]'s one-shot
  /// [_defaulted] flag) because [_selectedDate] can change repeatedly via
  /// [_pickDate], and each change must re-check for a trip covering the new
  /// date. Never runs once [_tagManuallySet] is true.
  void _applyAutoTag(List<TagRow> tags) {
    if (_tagManuallySet) return;
    _tagId = tripForDate(tags, _selectedDate)?.id;
  }

  Widget _titleBar(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close',
            child: GestureDetector(
              onTap: () => _closeOrConfirm(context),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.card,
                      border: Border.all(color: palette.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEdit ? 'Edit expense' : 'New expense',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }

  /// Symbol on the big amount: the trip's currency when it's abroad, else ₹.
  String get _amountSymbol {
    final tag = _selectedTag;
    if (tag == null || !tag.isTravel) return '₹';
    return NumberFormat.simpleCurrency(name: tag.fxCurrency!).currencySymbol;
  }

  /// "≈ ₹1,179.00" under the foreign amount, plus a tappable rate pill.
  /// Only rendered on a trip abroad — a domestic entry looks exactly as
  /// it always has.
  Widget _conversionLine(AppPalette palette) {
    final tag = _selectedTag;
    if (tag == null || !tag.isTravel) return const SizedBox.shrink();
    final home = Money.fromMinor(
      convertToHomeMinor(Money.parse(_amount).minor, tag.fxRateMicros!),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        children: [
          Text(
            '≈ ${home.format(locale: 'en_IN')}',
            style: TextStyle(color: palette.textDim, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            label:
                'Exchange rate, 1 ${tag.fxCurrency} equals '
                '${rateToString(tag.fxRateMicros!)} rupees. Tap to change.',
            child: GestureDetector(
              onTap: () => _editRate(tag),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  '1 ${tag.fxCurrency} = '
                  '${rateToString(tag.fxRateMicros!)} $homeCurrencyCode',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Correcting the rate mid-trip — the ATM gave worse than the fetched rate.
  /// Saves to the tag, so it applies to this entry and every later one, and
  /// never to what is already saved.
  Future<void> _editRate(TagRow tag) async {
    final controller = TextEditingController(
      text: rateToString(tag.fxRateMicros!),
    );
    final micros = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('1 ${tag.fxCurrency} equals'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: homeCurrencyCode,
            border: OutlineInputBorder(),
            helperText: 'Applies to new entries, not ones already saved',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(parseRateMicros(controller.text)),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (micros == null) return;
    // No setState: _selectedTag watches activeTagsProvider, so the Drift
    // stream rebuilds the conversion line on its own.
    await ref.read(tagRepositoryProvider).setFxRate(tag.id, micros);
  }

  Widget _subLine(
    BuildContext context,
    CategoryRow? selected,
    AppPalette palette,
  ) {
    final label = selected?.name ?? 'Select category';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: palette.textDim, fontSize: 13),
        ),
      ),
    );
  }

  /// Backdating chip: shows the selected date, tap opens a bounded picker
  /// (today back to 90 days ago, no future dates).
  /// Shared date/trip chip shell. [emphasized] gives it the bordered-pill
  /// treatment; the quiet (unbordered) form is used for each chip's default
  /// value (today, no trip) so the two highest-frequency decisions — amount
  /// and category — aren't visually competing with defaults nobody needs to
  /// look at. Tapping still opens the same picker either way.
  Widget _metaChip({
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onTap,
    required AppPalette palette,
    bool emphasized = false,
    Color? emphasisColor,
  }) {
    final color = emphasisColor ?? palette.textDim;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: emphasized
              ? BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: emphasisColor ?? palette.line),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateChip(BuildContext context, AppPalette palette) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    return _metaChip(
      icon: Icons.calendar_today_outlined,
      label: relativeDayLabel(_selectedDate),
      semanticsLabel: 'Expense date, ${relativeDayLabel(_selectedDate)}',
      onTap: _pickDate,
      palette: palette,
      emphasized: !isToday,
    );
  }

  /// Trip/tag chip: shows the selected tag or "Add trip", tap opens a picker
  /// of active tags. Orthogonal to category — see [Expenses.tagId].
  Widget _tripChip(BuildContext context, AppPalette palette) {
    final tags = ref.watch(activeTagsProvider).value ?? const <TagRow>[];
    final selected = tags
        .where((t) => t.id == _tagId)
        .cast<TagRow?>()
        .firstOrNull;
    return _metaChip(
      icon: Icons.card_travel_outlined,
      label: selected?.name ?? 'Add trip',
      semanticsLabel: selected == null ? 'Add trip' : 'Trip, ${selected.name}',
      onTap: () => _openTagPicker(tags),
      palette: palette,
      emphasized: selected != null,
      emphasisColor: selected == null ? null : Color(selected.colorValue),
    );
  }

  Future<void> _openTagPicker(List<TagRow> tags) async {
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('Trip'),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tags.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(
                          Icons.add,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        title: const Text(
                          '+ New trip',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          final newId = await showTagEditSheet(context);
                          if (newId != null && mounted) {
                            setState(() {
                              _tagId = newId;
                              _tagManuallySet = true;
                              _touched = true;
                            });
                          }
                        },
                      );
                    }
                    if (i == 1) {
                      return ListTile(
                        leading: const Icon(Icons.close, size: 20),
                        title: const Text('No trip'),
                        trailing: _tagId == null
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 18,
                              )
                            : null,
                        onTap: () =>
                            Navigator.of(sheetContext).pop<int?>(_noTripChoice),
                      );
                    }
                    final t = tags[i - 2];
                    return ListTile(
                      leading: Icon(
                        Icons.card_travel_outlined,
                        size: 20,
                        color: Color(t.colorValue),
                      ),
                      title: Text(t.name),
                      trailing: t.id == _tagId
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop<int?>(t.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Dismissing without a choice (backdrop tap / back) also yields null,
    // same as picking "No trip" — distinguish via a sentinel so dismissal
    // never wipes an existing selection.
    if (chosen == null || !mounted) return;
    setState(() {
      _tagId = chosen == _noTripChoice ? null : chosen;
      _tagManuallySet = true;
      _touched = true;
    });
  }

  static const _noTripChoice = -1;

  Widget _noteField(BuildContext context, AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: TextField(
        controller: _noteController,
        focusNode: _noteFocusNode,
        textInputAction: TextInputAction.done,
        onEditingComplete: () => _noteFocusNode.unfocus(),
        textCapitalization: TextCapitalization.sentences,
        maxLength: 140,
        style: TextStyle(fontSize: 13, color: palette.textDim),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Add a note',
          counterText: '',
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final (firstDate, lastDate) = backdatePickerBounds(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _touched = true;
      });
    }
  }

  Widget _categoryGrid(List<CategoryRow> categories) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final showMore = categories.length > _gridCap;
    final visible = showMore
        ? visibleCategoryTiles(categories, _categoryId)
        : categories;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visible.length + (showMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
      ),
      itemBuilder: (context, i) {
        if (showMore && i == visible.length) {
          return Semantics(
            button: true,
            label: 'More categories',
            child: GestureDetector(
              onTap: () => _openCategoryPicker(categories),
              child: _CategoryTile(
                glyph: Icon(
                  Icons.grid_view_rounded,
                  size: 22,
                  color: palette.textDim,
                ),
                name: 'More',
                selected: false,
              ),
            ),
          );
        }
        final c = visible[i];
        final sel = c.id == _categoryId;
        return Semantics(
          button: true,
          selected: sel,
          label: c.name,
          child: GestureDetector(
            onTap: () => setState(() {
              _categoryId = c.id;
              _touched = true;
            }),
            child: _CategoryTile(
              glyph: CategoryGlyph(c.icon, size: 22),
              name: c.name,
              selected: sel,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCategoryPicker(List<CategoryRow> categories) async {
    final chosen = await showModalBottomSheet<CategoryRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('All categories'),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    return ListTile(
                      leading: CategoryGlyph(c.icon, size: 20),
                      title: Text(c.name),
                      trailing: c.id == _categoryId
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _categoryId = chosen.id;
        _touched = true;
      });
    }
  }

  Widget _saveButton(BuildContext context) {
    final label = _isEdit ? 'Save changes' : 'Save expense';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: _save,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
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

  /// The trip currently selected, or null. Watched, not read, so an edited
  /// rate re-renders the conversion line — and so this never serves a value
  /// that lags a write (see test/reactive_read_staleness_test.dart).
  /// The write path in [_save] does NOT use this; it re-reads the tag.
  TagRow? get _selectedTag {
    if (_tagId == null) return null;
    final tags = ref.watch(activeTagsProvider).value ?? const <TagRow>[];
    return tags.where((t) => t.id == _tagId).cast<TagRow?>().firstOrNull;
  }

  /// Resolves what actually gets stored: the home-currency amount, plus the
  /// foreign receipt when the selected trip is abroad. [typed] is what the
  /// user keyed in — in the trip's currency when it has one. [tag] must be a
  /// freshly-read row, not a cached one, so a rate edited moments ago is the
  /// one that gets applied.
  ///
  /// **The freeze rule lives here.** Reopening an already-converted expense
  /// and saving it without retyping the amount keeps its ORIGINAL home
  /// amount, even if the trip's rate has since moved. Only a retyped amount
  /// (or a changed trip) re-converts at the current rate. Rewriting the
  /// former would silently move totals for a month the user already
  /// reconciled.
  ({Money home, String? fxCurrency, Money? fxAmount}) _resolveAmounts(
    Money typed,
    TagRow? tag,
  ) {
    if (tag == null || !tag.isTravel) {
      return (home: typed, fxCurrency: null, fxAmount: null);
    }
    final editing = widget.editing;
    final untouched =
        editing != null &&
        editing.isForeign &&
        editing.tagId == tag.id &&
        _amount == _initialAmount;
    if (untouched) {
      return (
        home: editing.amount,
        fxCurrency: editing.fxCurrency,
        fxAmount: editing.fxAmount,
      );
    }
    return (
      home: Money.fromMinor(convertToHomeMinor(typed.minor, tag.fxRateMicros!)),
      fxCurrency: tag.fxCurrency,
      fxAmount: typed,
    );
  }

  Future<void> _save() async {
    final typed = Money.parse(_amount);
    if (typed.minor <= 0 || _categoryId == null) {
      final missing = typed.minor <= 0 && _categoryId == null
          ? 'Enter an amount and pick a category'
          : typed.minor <= 0
          ? 'Enter an amount'
          : 'Pick a category';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(missing)));
      return;
    }
    // Fresh read, not the cached tag list: _editRate may have just written a
    // new rate, and converting at a stale one would store the wrong amount.
    final tag = _tagId == null
        ? null
        : await ref.read(tagRepositoryProvider).byId(_tagId!);
    if (!mounted) return;
    // Everything below this line deals in `amount`, which is ALWAYS home
    // currency — budgets, alerts and every total downstream depend on that.
    final resolved = _resolveAmounts(typed, tag);
    final amount = resolved.home;
    final categoryId = _categoryId!;
    final oldAmount = widget.editing?.amount ?? Money.zero;
    final note = _noteController.text.trim();
    final repo = ref.read(expenseRepositoryProvider);
    if (_isEdit) {
      await repo.update(
        widget.editing!.id,
        amount: amount,
        categoryId: categoryId,
        date: _selectedDate,
        note: Value(note.isEmpty ? null : note),
        tagId: Value(_tagId),
        // Always passed, never absent: moving an expense off a trip has to
        // clear the foreign receipt, not leave a stale one behind.
        fxCurrency: Value(resolved.fxCurrency),
        fxAmount: Value(resolved.fxAmount),
      );
    } else {
      await repo.add(
        amount: amount,
        categoryId: categoryId,
        date: _selectedDate,
        note: note.isEmpty ? null : note,
        tagId: _tagId,
        fxCurrency: resolved.fxCurrency,
        fxAmount: resolved.fxAmount,
      );
    }
    // Fire budget-threshold alerts for the affected category + overall (FR-25).
    // Only the delta counts toward the "before → after" crossing so an edit
    // that keeps the same category alerts on its net change.
    final sameCategory = _isEdit && widget.editing!.categoryId == categoryId;
    final delta = sameCategory ? amount - oldAmount : amount;
    await _checkBudgetAlerts(categoryId, delta);
    if (!mounted) return;
    // Only a fresh add gets a confirmation — an edit is a correction, not a
    // habit-loop moment worth celebrating.
    if (_isEdit) {
      Navigator.of(context).pop();
    } else {
      final categoryName = _categories
          .where((c) => c.id == categoryId)
          .cast<CategoryRow?>()
          .firstOrNull
          ?.name;
      Navigator.of(context).pop(
        '${amount.format(locale: 'en_IN')} logged'
        '${categoryName == null ? '' : ' to $categoryName'}',
      );
    }
  }

  /// After a write, compare category + overall month totals against their
  /// budgets and notify on each newly crossed 80% / 100% line.
  Future<void> _checkBudgetAlerts(int categoryId, Money delta) async {
    if (delta.minor <= 0) return; // only rising spend can cross a threshold
    final expenses = ref.read(expenseRepositoryProvider);
    final (start, end) = monthBounds(_selectedDate);
    final byCategory = await expenses.totalsByCategory(start, end);
    final notifier = ref.read(notificationServiceProvider);

    // Fresh one-shot reads, not the cached perCategoryBudgetsForMonthProvider/
    // categoriesByIdProvider/overallBudgetForMonthProvider — those are
    // Providers built from a Drift stream's cached `.value`, which lags the
    // write just above by at least one microtask (docs/architecture.md §8.1).
    final budgetRows = await ref
        .read(budgetRepositoryProvider)
        .watchAllForMonth(_selectedDate)
        .first;
    final perCategoryBudgets = {
      for (final r in budgetRows)
        if (r.categoryId != null) r.categoryId!: Money.fromMinor(r.amountMinor),
    };
    final categoriesById = {
      for (final c
          in await ref.read(categoryRepositoryProvider).watchAll().first)
        c.id: c,
    };
    final ignored = ignoredCategoryIds(categoriesById);

    // Per-category budget.
    final catBudget = perCategoryBudgets[categoryId];
    if (catBudget != null) {
      final after = byCategory[categoryId] ?? Money.zero;
      final name = categoriesById[categoryId]?.name ?? 'Category';
      for (final pct in crossedThresholds(after - delta, after, catBudget)) {
        await notifier.showBudgetAlert(name, pct);
      }
    }

    // Overall budget — ignored-for-budget categories don't count toward it,
    // and their own budget allocation is netted out of the target too.
    final rawOverall = await ref
        .read(budgetRepositoryProvider)
        .watchOverallBudget(_selectedDate)
        .first;
    final overall = effectiveOverallBudget(
      rawOverall,
      perCategoryBudgets,
      ignored,
    );
    if (overall != null) {
      final after = byCategory.entries
          .where((e) => !ignored.contains(e.key))
          .fold(Money.zero, (a, e) => a + e.value);
      // If this write's own category is ignored, it never entered `after`,
      // so the overall total didn't move — no threshold crossing to check.
      final effectiveDelta = ignored.contains(categoryId) ? Money.zero : delta;
      for (final pct in crossedThresholds(
        after - effectiveDelta,
        after,
        overall,
      )) {
        await notifier.showBudgetAlert('Overall', pct);
      }
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.glyph,
    required this.name,
    required this.selected,
  });

  final Widget glyph;
  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.10)
                : palette.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: selected ? AppColors.primary : palette.line,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph,
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : palette.textDim,
                ),
              ),
            ],
          ),
        ),
        // Selection isn't color-only: a checkmark badge marks the selected
        // tile too.
        if (selected)
          const Positioned(
            top: 3,
            right: 3,
            child: Icon(Icons.check_circle, size: 14, color: AppColors.primary),
          ),
      ],
    );
  }
}

/// Push Quick Add and show its post-save confirmation (if any) once back on
/// this screen — the confirmation SnackBar has to live here, not inside
/// QuickAddScreen itself, since that screen is already gone by the time it
/// would show.
Future<void> openQuickAddScreen(
  BuildContext context, {
  ExpenseRow? editing,
  int? initialCategoryId,
}) async {
  final confirmation = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => QuickAddScreen(
        editing: editing,
        initialCategoryId: initialCategoryId,
      ),
    ),
  );
  if (confirmation != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmation)));
  }
}
