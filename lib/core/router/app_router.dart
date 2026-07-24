import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/about/screens/about_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/help/screens/help_screen.dart';
import '../../features/monitoring/providers/session_history_provider.dart';
import '../../features/monitoring/screens/health_summary_screen.dart';
import '../../features/monitoring/screens/log_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';
import '../../features/monitoring/screens/sessions_list_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../widgets/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authListenable,
    redirect: (_, state) {
      final auth = ref.read(authNotifierProvider);
      final authenticated = auth.value?.isAuthenticated ?? false;
      final location = state.matchedLocation;

      // Still loading auth (and cameras) — stay on login
      if (auth.isLoading && !auth.hasValue) return null;

      // Not authenticated — go to login. /help stays reachable so setup
      // instructions are available before any credentials exist.
      if (!authenticated) {
        return (location == '/login' || location == '/help')
            ? null
            : '/login';
      }

      // Authenticated — always land in the shell on /monitoring. The Monitor
      // tab handles both the idle (camera picker) and live states, so the
      // tab bar is reachable immediately and the user never gets stuck on a
      // headerless camera-selection screen.
      if (location == '/login') {
        return '/monitoring';
      }

      // Legacy /cameras link folded into /monitoring (idle state).
      if (location == '/cameras') {
        return '/monitoring';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // Help lives ABOVE the shell (like /sessions/:id) so it stacks as a
      // normal detail page with its own AppBar + back button, and is
      // reachable both before login and from inside the app.
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      // About lives ABOVE the shell (like /help) so it stacks as a normal
      // detail page with its own AppBar + back button.
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
      // Session detail lives ABOVE the shell so it stacks like a normal
      // detail page (its own AppBar + back button, no tab bar — standard
      // mobile pattern). Keeping it inside the ShellRoute hid it because
      // MainShell deliberately ignores ShellRoute.builder's `child` to make
      // IndexedStack work for the tab screens.
      GoRoute(
        path: '/sessions/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return MaterialPage(
            key: state.pageKey,
            child: _SessionDetailRoute(id: id),
          );
        },
      ),
      // StatefulShellRoute.indexedStack hosts the four primary tabs. Unlike a
      // plain ShellRoute + hand-rolled IndexedStack, it owns one Navigator per
      // branch and keeps their state alive across router refreshes (the
      // auth refreshListenable fires several times during start-up), tab
      // switches, and the rail/bottom-nav breakpoint — so MonitoringScreen is
      // no longer torn down and remounted mid-session. EXCEPTION: /sessions/:id
      // uses a top-level pageBuilder so it stacks ON TOP of the shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/monitoring',
                builder: (_, _) => const MonitoringScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sessions',
                builder: (_, _) => const SessionsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/logs',
                builder: (_, _) => const LogScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Looks up a session by id from sessionHistoryProvider (current + past).
/// Renders HealthSummaryScreen or a "Session not found" fallback — never crashes.
class _SessionDetailRoute extends ConsumerWidget {
  const _SessionDetailRoute({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(sessionHistoryProvider).value;
    final session = history == null
        ? null
        : (history.current?.id == id
            ? history.current
            : history.past.where((s) => s.id == id).firstOrNull);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('Session not found')),
      );
    }
    return HealthSummaryScreen(session: session);
  }
}

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (_, _) => notifyListeners());
  }
}
