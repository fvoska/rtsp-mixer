import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/monitoring/screens/log_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';
import '../../features/monitoring/screens/sessions_list_screen.dart';
import '../../features/monitoring/widgets/active_session_bar.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Width at which we swap the bottom NavigationBar for a side NavigationRail.
/// 600dp is the canonical Material 3 "compact → medium" breakpoint.
const double _kRailBreakpoint = 600;

/// Top-level shell hosting the four primary tabs.
///
/// IndexedStack keeps MonitoringScreen mounted across tab switches so the
/// audio pipeline, video controllers, and ConsumerStatefulWidget state are
/// not torn down on every navigation. We deliberately ignore the
/// `ShellRoute.builder`'s `child` parameter — that pattern only renders the
/// active route's widget, which would unmount the others.
///
/// Layout:
/// - Width < 600dp → bottom NavigationBar (phone)
/// - Width ≥ 600dp → collapsible NavigationRail at the leading edge
///
/// Routing contract:
/// - `/monitoring` → index 0
/// - `/sessions` (and prefix-matches like `/sessions/`) → index 1
/// - `/logs` → index 2
/// - `/settings` → index 3
/// - `/sessions/:id` is NOT in the IndexedStack — it pushes on top of the
///   shell via go_router's `MaterialPage` pageBuilder.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.currentLocation});

  final String currentLocation;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _tabs = ['/monitoring', '/sessions', '/logs', '/settings'];

  /// User-controlled rail expansion (icon-only vs icon+label). Applies only
  /// when the rail is shown (width ≥ _kRailBreakpoint).
  bool _railExtended = false;

  int _indexFor(String loc) {
    if (loc.startsWith('/sessions')) return 1;
    if (loc.startsWith('/logs')) return 2;
    if (loc.startsWith('/settings')) return 3;
    return 0; // default to monitoring
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _indexFor(widget.currentLocation);
    final useRail = MediaQuery.sizeOf(context).width >= _kRailBreakpoint;

    final body = Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: selectedIndex,
            children: const [
              MonitoringScreen(),
              SessionsListScreen(),
              LogScreen(),
              SettingsScreen(),
            ],
          ),
        ),
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
          onDestinationSelected: (i) => context.go(_tabs[i]),
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
              onDestinationSelected: (i) => context.go(_tabs[i]),
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
