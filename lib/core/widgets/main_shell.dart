import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/monitoring/widgets/active_session_bar.dart';

/// Width at which we swap the bottom NavigationBar for a side NavigationRail.
/// 600dp is the canonical Material 3 "compact → medium" breakpoint.
const double _kRailBreakpoint = 600;

/// Top-level shell hosting the four primary tabs.
///
/// Backed by go_router's [StatefulShellRoute.indexedStack]: the injected
/// [navigationShell] owns one Navigator per branch (each keyed with a
/// GlobalKey) and keeps their state alive across router refreshes — the auth
/// `refreshListenable` fires several times during start-up — as well as tab
/// switches and the rail/bottom-nav breakpoint. MonitoringScreen's audio
/// pipeline, video controllers, and State are therefore never torn down by
/// navigation, unlike the previous hand-rolled ShellRoute + IndexedStack.
///
/// Layout:
/// - Width < 600dp → bottom NavigationBar (phone)
/// - Width ≥ 600dp → collapsible NavigationRail at the leading edge
///
/// Routing contract (branch index):
/// - `/monitoring` → 0
/// - `/sessions` → 1
/// - `/logs` → 2
/// - `/settings` → 3
/// - `/sessions/:id` is NOT a branch — it stacks ON TOP of the shell via a
///   top-level `MaterialPage` pageBuilder (its own AppBar + back button).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  /// The stateful shell created by [StatefulShellRoute.indexedStack]; renders
  /// the active branch and exposes [StatefulNavigationShell.goBranch].
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// User-controlled rail expansion (icon-only vs icon+label). Applies only
  /// when the rail is shown (width ≥ _kRailBreakpoint).
  bool _railExtended = false;

  /// Switch to branch [index]. Tapping the already-selected tab pops that
  /// branch back to its initial location — standard bottom-nav behaviour.
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.navigationShell.currentIndex;
    final useRail = MediaQuery.sizeOf(context).width >= _kRailBreakpoint;

    final body = Column(
      children: [
        Expanded(child: widget.navigationShell),
        // ActiveSessionBar sits at the bottom of the body column. On phones it
        // visually floats just above the NavigationBar; on tablet/desktop it
        // floats at the bottom of the main content area, next to the rail.
        // The widget hides itself when no session is running or the user is
        // already on the Monitor tab.
        ActiveSessionBar(selectedIndex: selectedIndex),
      ],
    );

    if (!useRail) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: _goBranch,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart),
              label: 'Monitor',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Sessions',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: 'Logs',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: _railExtended,
              selectedIndex: selectedIndex,
              onDestinationSelected: _goBranch,
              labelType: _railExtended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              leading: _RailToggle(
                extended: _railExtended,
                onPressed: () =>
                    setState(() => _railExtended = !_railExtended),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.monitor_heart_outlined),
                  selectedIcon: Icon(Icons.monitor_heart),
                  label: Text('Monitor'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('Sessions'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.article_outlined),
                  selectedIcon: Icon(Icons.article),
                  label: Text('Logs'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Hamburger/close icon at the top of the rail that toggles between
/// icon-only (collapsed) and icon+label (extended) layouts.
class _RailToggle extends StatelessWidget {
  const _RailToggle({required this.extended, required this.onPressed});

  final bool extended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(extended ? Icons.menu_open : Icons.menu);
    if (extended) {
      // When the rail is extended, align the toggle with the destination
      // labels so the chevron sits at the leading edge of the wider rail.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: IconButton(
            icon: icon,
            tooltip: 'Collapse navigation',
            onPressed: onPressed,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        icon: icon,
        tooltip: 'Expand navigation',
        onPressed: onPressed,
      ),
    );
  }
}
