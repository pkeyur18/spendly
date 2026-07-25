import 'package:flutter/material.dart';

import '../money/money.dart';
import '../theme/tokens.dart';

/// Apply a keypad key to the current amount string. Pure so it's unit-testable.
/// Keys: '0'-'9', '.', 'del'. Blocks a 3rd decimal (money is 2 places).
String applyAmountKey(String amount, String key) {
  if (key == 'del') {
    return amount.length > 1 ? amount.substring(0, amount.length - 1) : '0';
  }
  if (key == '.') {
    return amount.contains('.') ? amount : '$amount.';
  }
  final dot = amount.indexOf('.');
  if (dot >= 0 && amount.length - dot > 2) return amount; // already 2 decimals
  return amount == '0' ? key : amount + key;
}

/// The 12-key numeric pad (0-9, ., ⌫) — no OS keyboard (FR-5). Emits taps via
/// [onKey]; the parent owns the amount string and applies [applyAmountKey].
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.onKey});

  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      childAspectRatio: 1.9,
      children: [
        for (final k in keys)
          Semantics(
            button: true,
            label: k == 'del'
                ? 'Delete'
                : (k == '.' ? 'Decimal point' : 'Digit $k'),
            child: GestureDetector(
              onTap: () => onKey(k),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.line),
                ),
                alignment: Alignment.center,
                child: k == 'del'
                    ? const Icon(Icons.backspace_outlined, size: 20)
                    : Text(
                        k,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Big ₹ + digits display shared by Quick Add and the budget sheet.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay(this.amount, {super.key, this.fontSize = 48});

  final String amount;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      child: RichText(
        // RichText doesn't inherit the ambient MediaQuery textScaler like Text
        // does — pass it explicitly so this honors Dynamic Type.
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            letterSpacing: -2,
          ),
          children: [
            TextSpan(
              text: '₹',
              style: TextStyle(
                color: palette.textDim,
                fontSize: fontSize * 0.62,
              ),
            ),
            TextSpan(
              text: amount,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge!.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal sheet to enter an exact amount (budgets). Returns the [Money] on Set,
/// or null on dismiss. Reuses the same keypad as Quick Add.
Future<Money?> showAmountSheet(
  BuildContext context, {
  Money? initial,
  String title = 'Set amount',
}) {
  return showModalBottomSheet<Money>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _AmountSheet(initial: initial, title: title),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({this.initial, required this.title});

  final Money? initial;
  final String title;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late String _amount = _seed(widget.initial);

  static String _seed(Money? m) {
    if (m == null || m.minor <= 0) return '0';
    return m.minor % 100 == 0
        ? (m.minor ~/ 100).toString()
        : m.major.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          AmountDisplay(_amount, fontSize: 42),
          const SizedBox(height: AppSpacing.lg),
          AmountKeypad(
            onKey: (k) => setState(() => _amount = applyAmountKey(_amount, k)),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            button: true,
            label: 'Set budget',
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(Money.parse(_amount)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Set budget',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: Colors.white,
                    fontSize: 15,
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
}
