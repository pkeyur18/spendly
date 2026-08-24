/// Ranks and filters previously-used notes for Quick Add's autocomplete —
/// pure so it's unit-testable without a database. [rankedNotes] is every
/// distinct past note, most-frequently-used first (the repository query
/// this feeds from already returns it in that order, so this never re-sorts
/// by anything but prefix match).
List<String> matchingNotes(
  List<String> rankedNotes,
  String query, {
  int limit = 5,
}) {
  final q = query.trim().toLowerCase();
  final matches = q.isEmpty
      ? rankedNotes
      : rankedNotes.where((n) => n.toLowerCase().startsWith(q)).toList();
  // Never suggest exactly what's already typed — there's nothing left for
  // tapping it to complete.
  return matches.where((n) => n.toLowerCase() != q).take(limit).toList();
}
