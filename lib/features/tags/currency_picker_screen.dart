import 'package:flutter/material.dart';

import '../../core/money/currencies.dart';
import '../../core/theme/tokens.dart';

/// How many of [travelCurrencies]' curated leading entries count as
/// "Popular" when the search box is empty. The list itself is already
/// ordered by likely destination popularity — see currencies.dart.
const _popularCount = 8;

/// Currencies whose name or code contains [query] (case-insensitive,
/// whitespace-trimmed). An empty query matches everything, in original
/// (curated) order. Pulled out as a free function — same reasoning as
/// `tripForDate` in quick_add_screen.dart — so the matching rule is
/// unit-testable without a widget harness.
List<CurrencyOption> filterCurrencies(List<CurrencyOption> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return all
      .where(
        (c) =>
            c.name.toLowerCase().contains(q) ||
            c.code.toLowerCase().contains(q),
      )
      .toList();
}

/// Splits [currencies] into a "Popular" section (the leading
/// [_popularCount] entries, curated order preserved) and an "A–Z" section
/// (everything else, sorted by name). Only meaningful for the unfiltered
/// list — [CurrencyPickerScreen] skips sectioning once the user is
/// searching, since a search result is already a small, relevant set.
(List<CurrencyOption> popular, List<CurrencyOption> alphabetical)
sectionCurrencies(List<CurrencyOption> currencies) {
  final popular = currencies.take(_popularCount).toList();
  final rest = currencies.skip(_popularCount).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return (popular, rest);
}

/// Full-screen currency picker (push, not a bottom sheet) — search bar in
/// the app bar, autofocused. Replaces the old `showModalBottomSheet` picker,
/// which had no height cap and no way to search: on a 30-entry list that
/// meant an unbounded, overflowing sheet with no way to jump to one currency.
///
/// Resolves to the picked ISO 4217 code, or null if dismissed without
/// picking.
class CurrencyPickerScreen extends StatefulWidget {
  const CurrencyPickerScreen({super.key, this.selected});

  /// Currently selected currency code, checkmarked in the list.
  final String? selected;

  @override
  State<CurrencyPickerScreen> createState() => _CurrencyPickerScreenState();
}

class _CurrencyPickerScreenState extends State<CurrencyPickerScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final filtered = filterCurrencies(travelCurrencies, _query);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search currency',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _controller.clear();
                        _query = '';
                      }),
                    ),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Text(
                'No currencies found',
                style: TextStyle(color: palette.textDim),
              ),
            )
          : _query.isEmpty
          ? _sectionedList(filtered)
          : _flatList(filtered),
    );
  }

  /// Unfiltered view: a short curated "Popular" group, then the rest A–Z.
  Widget _sectionedList(List<CurrencyOption> currencies) {
    final (popular, alphabetical) = sectionCurrencies(currencies);
    return ListView(
      children: [
        _sectionLabel('Popular'),
        for (final c in popular) _row(c),
        _sectionLabel('A–Z'),
        for (final c in alphabetical) _row(c),
      ],
    );
  }

  /// Search results: a flat list — already a small, relevant set, so
  /// sectioning it further would just add noise.
  Widget _flatList(List<CurrencyOption> currencies) {
    return ListView(children: [for (final c in currencies) _row(c)]);
  }

  Widget _sectionLabel(String text) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: palette.textDim,
        ),
      ),
    );
  }

  Widget _row(CurrencyOption c) {
    final isSelected = c.code == widget.selected;
    return ListTile(
      leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
      title: Text(c.name),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
          : Text(
              c.code,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
      selected: isSelected,
      onTap: () => Navigator.of(context).pop(c.code),
    );
  }
}

/// Push the full-screen picker and await the chosen code (or null if
/// dismissed via back).
Future<String?> showCurrencyPickerScreen(
  BuildContext context, {
  String? selected,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => CurrencyPickerScreen(selected: selected),
    ),
  );
}
