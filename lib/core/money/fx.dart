/// Foreign-currency conversion for trips abroad.
///
/// The one rule this file exists to serve: `expenses.amountMinor` is ALWAYS
/// home currency. Conversion happens once, at save time, using the rate stored
/// on the trip tag — nothing recomputes when a rate later changes.
///
/// Rates are integers scaled by [rateScale] so no rate ever rides a double,
/// same discipline as [Money].
library;

/// Rates are stored as home-currency units per 1 foreign unit × 1e6, so
/// 2.62 INR per THB is `2_620_000`.
const rateScale = 1000000;

/// Home-currency minor units for [fxMinor] at [rateMicros], rounded half-up.
///
/// All integer math — never via double. Both arguments are already scaled
/// integers, so the product stays exact; at 1e6 scale a ₹1 crore expense is
/// ~1e15, comfortably inside Dart's 64-bit int.
int convertToHomeMinor(int fxMinor, int rateMicros) {
  final negative = fxMinor < 0;
  final magnitude = negative ? -fxMinor : fxMinor;
  // + half a unit before truncating = round half-up, applied to the magnitude
  // so negatives round away from zero symmetrically rather than towards it.
  final home = (magnitude * rateMicros + rateScale ~/ 2) ~/ rateScale;
  return negative ? -home : home;
}

/// Rate as a plain decimal string for display and for prefilling the editor,
/// e.g. `2_620_000` -> "2.62". Trailing zeros are trimmed; a whole rate comes
/// back without a decimal point at all.
String rateToString(int rateMicros) {
  final whole = rateMicros ~/ rateScale;
  final frac = rateMicros % rateScale;
  if (frac == 0) return '$whole';
  final digits = frac.toString().padLeft(6, '0').replaceAll(RegExp(r'0+$'), '');
  return '$whole.$digits';
}

/// Parses a typed rate like "2.62" into micros. Returns null for anything
/// that isn't a positive number — an empty field, letters, a stray minus.
///
/// Walks the string the way [Money.parse] does rather than going through
/// double, so "0.000001" is exact and not a binary-float approximation.
int? parseRateMicros(String input) {
  final s = input.trim().replaceAll(',', '');
  if (s.isEmpty) return null;

  final dot = s.indexOf('.');
  final intPart = dot < 0 ? s : s.substring(0, dot);
  final fracPart = dot < 0 ? '' : s.substring(dot + 1);

  // Reject anything non-numeric, including a second '.' left in fracPart.
  final digitsOnly = RegExp(r'^\d*$');
  if (!digitsOnly.hasMatch(intPart) || !digitsOnly.hasMatch(fracPart)) {
    return null;
  }
  if (intPart.isEmpty && fracPart.isEmpty) return null;

  final whole = intPart.isEmpty ? 0 : int.parse(intPart);
  // Pad/truncate to exactly 6 fractional digits; extra precision is dropped,
  // which is far below anything a published rate carries.
  final micros = int.parse(fracPart.padRight(6, '0').substring(0, 6));

  final rate = whole * rateScale + micros;
  return rate > 0 ? rate : null;
}

/// Effective rate implied by totals already converted and stored — used for
/// the "avg 1 THB = 2.62 INR" line on a trip report. Derived, never stored,
/// so a rate edited mid-trip shows up honestly as a blend of both.
/// Null when there is nothing to divide by.
int? averageRateMicros(int homeMinorTotal, int fxMinorTotal) {
  if (fxMinorTotal == 0) return null;
  return (homeMinorTotal * rateScale + fxMinorTotal ~/ 2) ~/ fxMinorTotal;
}
