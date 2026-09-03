import 'package:flutter/material.dart';

/// Root widget for the read-only macOS build.
///
/// Deliberately separate from [SpendlyApp] (`lib/app.dart`) rather than
/// reusing it behind a flag — that widget wires `home_widget`, local
/// notifications and other mobile-only plugins that have no macOS
/// implementation and would throw if touched here. The macOS build gets its
/// own shell, its own screens, and never calls into mobile-only code.
class MacosSpendlyApp extends StatelessWidget {
  const MacosSpendlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Spendly',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Spendly for Mac'))),
    );
  }
}
