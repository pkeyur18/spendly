import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../dev/debug_data_screen.dart';
import '../settings/theme_mode_provider.dart';

/// Sprint 0 home shell: themed empty state + bottom nav matching the prototype.
/// Real dashboard (hero total, donut, trend, recent list) lands in Sprint 2.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: const Text('₹', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Spendly'),
          ],
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Debug data',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebugDataScreen()),
              ),
              icon: const Icon(Icons.bug_report_outlined),
            ),
          IconButton(
            tooltip: 'Theme',
            onPressed: () => _cycleTheme(ref),
            icon: const Icon(Icons.brightness_6_outlined),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(AppRadius.hero),
                ),
                alignment: Alignment.center,
                child: const Text('₹', style: TextStyle(color: Colors.white, fontSize: 34)),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('No expenses yet', style: text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tap + to log your first expense.\nYour dashboard fills in from here.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: palette.textDim),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(19),
        ),
        child: FloatingActionButton(
          onPressed: () => _soon(context, 'Quick Add (Sprint 2)'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        palette: palette,
        onTap: (label) => _soon(context, label),
      ),
    );
  }

  void _cycleTheme(WidgetRef ref) {
    final current = ref.read(themeModeProvider).value ?? ThemeMode.system;
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(current) + 1) % order.length];
    ref.read(themeModeProvider.notifier).setMode(next);
  }

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what — coming soon')));
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.palette, required this.onTap});

  final AppPalette palette;
  final void Function(String label) onTap;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, {bool active = false}) {
      return IconButton(
        onPressed: () => onTap(label),
        icon: Icon(icon, color: active ? AppColors.primary : palette.textDim),
      );
    }

    return BottomAppBar(
      color: palette.card,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          item(Icons.home_rounded, 'Home', active: true),
          item(Icons.bar_chart_rounded, 'Reports (Sprint 4)'),
          const SizedBox(width: 40), // FAB notch
          item(Icons.sell_rounded, 'Categories (Sprint 3)'),
          item(Icons.settings_rounded, 'Settings'),
        ],
      ),
    );
  }
}
