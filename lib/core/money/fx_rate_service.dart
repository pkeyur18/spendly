import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fx.dart';

/// Home currency every rate is fetched against. Hardcoded alongside the rest
/// of the app's single-home-currency assumption (PRD Q1).
const homeCurrencyCode = 'INR';

/// Fetches today's mid-market rate for a trip's currency.
///
/// Deliberately thin: one GET, no caching, no retry, no background refresh.
/// Called only when the user picks a currency in the tag editor — the result
/// is a prefill for an editable field, never a binding value. Everything
/// after that point works off the rate stored on the tag.
///
/// Every failure (offline, timeout, rate limit, bad payload) comes back as
/// null. Being offline abroad is the normal case, not an error worth a dialog.
class FxRateService {
  const FxRateService();

  /// open.er-api.com is free and needs no API key.
  static const _host = 'open.er-api.com';
  static const _timeout = Duration(seconds: 5);

  /// Home-currency units per 1 [currencyCode], in micros — or null if the
  /// rate could not be fetched.
  Future<int?> fetchRateMicros(String currencyCode) async {
    if (currencyCode == homeCurrencyCode) return rateScale;

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.https(_host, '/v6/latest/$currencyCode');
      final response = await client
          .getUrl(uri)
          .then((request) => request.close())
          .timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      final rates = decoded['rates'];
      if (rates is! Map) return null;

      final rate = rates[homeCurrencyCode];
      if (rate is! num || rate <= 0) return null;

      // The API hands back a double; funnel it through the same string parser
      // the typed field uses so there is exactly one path from decimal to
      // micros, and no double survives past this line.
      return parseRateMicros(rate.toStringAsFixed(6));
    } on Object {
      // Socket, timeout, TLS, malformed JSON — all mean the same thing here:
      // no rate, let the user type one.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

final fxRateServiceProvider = Provider<FxRateService>(
  (ref) => const FxRateService(),
);
