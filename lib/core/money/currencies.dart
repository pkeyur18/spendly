/// Currencies offered in the trip picker.
///
/// ponytail: a hand-picked list of common travel destinations, not a full ISO
/// 4217 table — that would be a dependency (or 180 lines of dead data) for no
/// gain. Add codes here as people ask for them.
library;

class CurrencyOption {
  const CurrencyOption(this.code, this.name, this.flag);

  /// ISO 4217 code, e.g. 'THB'. This is what lands in `tags.fxCurrency`.
  final String code;
  final String name;
  final String flag;
}

const travelCurrencies = <CurrencyOption>[
  CurrencyOption('USD', 'US Dollar', '🇺🇸'),
  CurrencyOption('EUR', 'Euro', '🇪🇺'),
  CurrencyOption('GBP', 'British Pound', '🇬🇧'),
  CurrencyOption('AED', 'UAE Dirham', '🇦🇪'),
  CurrencyOption('SGD', 'Singapore Dollar', '🇸🇬'),
  CurrencyOption('THB', 'Thai Baht', '🇹🇭'),
  CurrencyOption('JPY', 'Japanese Yen', '🇯🇵'),
  CurrencyOption('AUD', 'Australian Dollar', '🇦🇺'),
  CurrencyOption('CAD', 'Canadian Dollar', '🇨🇦'),
  CurrencyOption('CHF', 'Swiss Franc', '🇨🇭'),
  CurrencyOption('MYR', 'Malaysian Ringgit', '🇲🇾'),
  CurrencyOption('IDR', 'Indonesian Rupiah', '🇮🇩'),
  CurrencyOption('VND', 'Vietnamese Dong', '🇻🇳'),
  CurrencyOption('LKR', 'Sri Lankan Rupee', '🇱🇰'),
  CurrencyOption('NPR', 'Nepalese Rupee', '🇳🇵'),
  CurrencyOption('QAR', 'Qatari Riyal', '🇶🇦'),
  CurrencyOption('SAR', 'Saudi Riyal', '🇸🇦'),
  CurrencyOption('HKD', 'Hong Kong Dollar', '🇭🇰'),
  CurrencyOption('CNY', 'Chinese Yuan', '🇨🇳'),
  CurrencyOption('KRW', 'South Korean Won', '🇰🇷'),
  CurrencyOption('NZD', 'New Zealand Dollar', '🇳🇿'),
  CurrencyOption('ZAR', 'South African Rand', '🇿🇦'),
  CurrencyOption('TRY', 'Turkish Lira', '🇹🇷'),
  CurrencyOption('EGP', 'Egyptian Pound', '🇪🇬'),
  CurrencyOption('MVR', 'Maldivian Rufiyaa', '🇲🇻'),
  CurrencyOption('MUR', 'Mauritian Rupee', '🇲🇺'),
  CurrencyOption('PHP', 'Philippine Peso', '🇵🇭'),
  CurrencyOption('BHD', 'Bahraini Dinar', '🇧🇭'),
  CurrencyOption('OMR', 'Omani Rial', '🇴🇲'),
  CurrencyOption('SEK', 'Swedish Krona', '🇸🇪'),
];

/// The option for [code], or null if it isn't one we offer. Used to render a
/// stored `fxCurrency` — a restored backup could name a code this build
/// doesn't list, and that must not crash a tile.
CurrencyOption? currencyFor(String? code) {
  if (code == null) return null;
  for (final c in travelCurrencies) {
    if (c.code == code) return c;
  }
  return null;
}
