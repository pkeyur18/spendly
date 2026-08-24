import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../categories/category_manager_screen.dart';
import '../expenses/quick_add_screen.dart';
import '../profile/avatar.dart';
import '../profile/profile_provider.dart';
import '../profile/profile_screen.dart';
import '../reports/monthly_report_screen.dart';
import 'home_screen.dart';

/// The four bottom-nav destinations, in bar order. The gap for the centre FAB
/// sits between [reports] and [categories].
enum ShellTab { home, reports, categories, profile }

/// Root navigation shell: one persistent Scaffold owning the bottom bar and
/// the Quick Add FAB, with the four destinations kept alive in an
/// [IndexedStack].
///
/// Replaces push-per-tab navigation, which grew the back stack on every tap
/// (tapping Home → Reports → Home left three routes deep) and discarded each
/// tab's scroll position and filter state on the way out.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  ShellTab _current = ShellTab.home;

  /// Tabs the user has actually opened. [IndexedStack] builds every child
  /// eagerly, which would drag the Reports, Categories and Profile trees —
  /// and their Drift subscriptions — onto the cold-start path for an app that
  /// deliberately defers work off it (see `main.dart`). Unvisited tabs render
  /// as an empty box until first opened; once visited they stay built, which
  /// is the point of the stack.
  final Set<ShellTab> _visited = {ShellTab.home};

  void _select(ShellTab tab) {
    if (tab == _current) return;
    setState(() {
      _current = tab;
      _visited.add(tab);
    });
  }

  Widget _tabView(ShellTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      ShellTab.home => const HomeScreen(),
      // Built on first open, so "this month" is resolved then rather than at
      // app launch.
      ShellTab.reports => MonthlyReportScreen(month: DateTime.now()),
      ShellTab.categories => const CategoryManagerScreen(),
      ShellTab.profile => const ProfileScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      body: IndexedStack(
        index: _current.index,
        children: [for (final tab in ShellTab.values) _tabView(tab)],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 4,
          ),
        ),
        child: FloatingActionButton(
          onPressed: () => openQuickAddScreen(context),
          tooltip: 'Add expense',
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        palette: palette,
        profile: profile,
        current: _current,
        onSelect: _select,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.palette,
    required this.profile,
    required this.current,
    required this.onSelect,
  });

  final AppPalette palette;
  final Profile? profile;
  final ShellTab current;
  final ValueChanged<ShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(
      IconData icon,
      String label,
      ShellTab tab, {
      Widget? leading,
    }) {
      final active = tab == current;
      return IconButton(
        onPressed: () => onSelect(tab),
        tooltip: label,
        isSelected: active,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          fixedSize: const Size(48, 48),
          backgroundColor: active
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
        ),
        icon:
            leading ??
            Icon(icon, color: active ? Colors.white : palette.navIconInactive),
      );
    }

    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.navBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: BottomAppBar(
          color: palette.navBackground,
          height: 56,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              item(Icons.home_rounded, 'Home', ShellTab.home),
              item(Icons.bar_chart_rounded, 'Reports', ShellTab.reports),
              const SizedBox(width: 40), // notch for the FAB
              item(Icons.sell_rounded, 'Categories', ShellTab.categories),
              item(
                Icons.account_circle_rounded,
                'Profile',
                ShellTab.profile,
                leading: ProfileAvatar(
                  name: profile?.name ?? '',
                  photoBytes: profile?.photoBytes,
                  avatarColorIndex: profile?.avatarColorIndex,
                  size: 26,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
