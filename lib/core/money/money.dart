import 'package:intl/intl.dart';

/// Decimal-safe money. Stored as an integer count of minor units (paise/cents)
/// so all arithmetic is exact — NEVER use double for money.
///
/// `Money(minor: 2450)` == ₹24.50. Two-decimal currencies assumed for v1
/// (matches INR default and the single-currency decision).
class Money {
  const Money._(this.minor);

  /// Raw minor units (e.g. paise). Can be negative.
  final int minor;

  static const zero = Money._(0);

  factory Money.fromMinor(int minor) => Money._(minor);

  /// Build from a major-unit decimal string like "24.50" or "1240".
  /// Parses the string directly (never via double) so there's no binary-float
  /// rounding error. Keeps 2 decimals, rounding half-up on the 3rd. Throws on
  /// non-numeric input.
  factory Money.parse(String input) {
    var s = input.trim().replaceAll(',', '');
    if (s.isEmpty) return zero;
    final negative = s.startsWith('-');
    if (negative || s.startsWith('+')) s = s.substring(1);

    final dot = s.indexOf('.');
    var intPart = dot < 0 ? s : s.substring(0, dot);
    final fracPart = dot < 0 ? '' : s.substring(dot + 1);
    if (intPart.isEmpty) intPart = '0';

    final whole = int.parse(intPart); // throws on non-digits
    final frac = fracPart.padRight(3, '0');
    var cents = int.parse(frac.substring(0, 2));
    if (int.parse(frac.substring(2, 3)) >= 5) cents += 1; // round 3rd digit

    final minor = whole * 100 + cents;
    return Money._(negative ? -minor : minor);
  }

  /// Major-unit value as a double — for display/formatting ONLY, never for math.
  double get major => minor / 100;

  Money operator +(Money o) => Money._(minor + o.minor);
  Money operator -(Money o) => Money._(minor - o.minor);
  Money operator *(int factor) => Money._(minor * factor);
  bool operator <(Money o) => minor < o.minor;
  bool operator >(Money o) => minor > o.minor;
  bool operator <=(Money o) => minor <= o.minor;
  bool operator >=(Money o) => minor >= o.minor;

  /// Percentage of [budget] this amount represents, 0 when budget is zero.
  double ratioOf(Money budget) => budget.minor == 0 ? 0 : minor / budget.minor;

  /// Always non-negative — e.g. for showing a debt's magnitude regardless of
  /// which sign it's stored with.
  Money abs() => minor < 0 ? Money._(-minor) : this;

  /// Locale-aware currency string, e.g. "₹24,350.00".
  /// [locale] defaults to the device locale; symbol follows the locale's currency.
  String format({String? locale, String? symbol}) {
    return NumberFormat.currency(
      locale: locale,
      symbol: symbol ?? _symbolFor(locale),
    ).format(major);
  }

  /// Formats as [currencyCode] (ISO 4217) instead of the home currency — for
  /// showing what was actually paid abroad alongside the home-currency amount.
  ///
  /// Digit count follows the currency's own convention, so a JPY amount stored
  /// as 150000 minor units renders "¥1,500", not "¥1,500.00".
  String formatAs(String currencyCode) {
    final format = NumberFormat.simpleCurrency(name: currencyCode);
    return format.format(major);
  }

  /// Compact form for tight UI, e.g. "₹24.3k".
  String formatCompact({String? locale, String? symbol}) {
    return NumberFormat.compactCurrency(
      locale: locale,
      symbol: symbol ?? _symbolFor(locale),
    ).format(major);
  }

  static String _symbolFor(String? locale) {
    // ponytail: default to ₹ (single-currency v1). Locale drives grouping/format;
    // swap to a settings-driven currency code when multi-currency lands (v2).
    return NumberFormat.simpleCurrency(
      locale: locale ?? 'en_IN',
    ).currencySymbol;
  }

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money($minor minor)';
}
