import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/monitoring/screens/log_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';
import '../../features/monitoring/screens/sessions_list_screen.dart';
// ActiveSessionBar is wired in Task 3 of 260514-siv. Until then a SizedBox
// placeholder sits in the slot below the IndexedStack.

/// Top-level shell hosting the three primary tabs.
///
/// IndexedStack keeps MonitoringScreen mounted across tab switches so the
/// audio pipeline, video controllers, and ConsumerStatefulWidget state are
/// not torn down on every navigation. We deliberately ignore the
/// `ShellRoute.builder`'s `child` parameter — that pattern only renders the
/// active route's widget, which would unmount the others.
///
/// Routing contract:
/// - `/monitoring` → index 0
/// - `/sessions` (and prefix-matches like `/sessions/`) → index 1
/// - `/logs` → index 2
/// - `/sessions/:id` is NOT in the IndexedStack — it pushes on top of the
///   shell via go_router's `MaterialPage` pageBuilder.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.currentLocation});

  final String currentLocation;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _tabs = ['/monitoring', '/sessions', '/logs'];

  int _indexFor(String loc) {
    if (loc.startsWith('/sessions')) return 1;
    if (loc.startsWith('/logs')) return 2;
    return 0; // default to monitoring
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _indexFor(widget.currentLocation);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: const [
                MonitoringScreen(),
                SessionsListScreen(),
                LogScreen(),
              ],
            ),
          ),
          // ActiveSessionBar slot (Task 3): sits inside the body Column,
          // ABOVE the Scaffold's bottomNavigationBar — so it visually floats
          // just above the NavigationBar without breaking SafeArea.
          const SizedBox.shrink(),
        ],
      ),
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
        ],
      ),
    );
  }
}
