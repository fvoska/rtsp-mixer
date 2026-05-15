import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/cameras/screens/camera_list_screen.dart';
import '../../features/monitoring/providers/session_history_provider.dart';
import '../../features/monitoring/screens/health_summary_screen.dart';
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

      // Not authenticated — go to login
      if (!authenticated) {
        return location == '/login' ? null : '/login';
      }

      // Authenticated — always land in the shell on /monitoring. When no
      // cameras are selected, MonitoringScreen renders an empty state with
      // a CTA to /cameras. This way the persistent nav (Sessions / Logs /
      // Settings) is reachable immediately, not gated behind monitoring.
      if (location == '/login') {
        return '/monitoring';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/cameras', builder: (_, __) => const CameraListScreen()),
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
      // ShellRoute hosts the three primary tabs. MainShell uses an IndexedStack
      // internally so MonitoringScreen stays mounted across tab switches
      // (260514-siv). Sub-route builders return SizedBox.shrink() — the actual
      // widgets live in MainShell's IndexedStack. EXCEPTION: /sessions/:id uses
      // a pageBuilder so it stacks ON TOP of the shell as a MaterialPage.
      ShellRoute(
        builder: (context, state, _) => MainShell(
          currentLocation: state.matchedLocation,
        ),
        routes: [
          GoRoute(
            path: '/monitoring',
            builder: (_, __) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/sessions',
            builder: (_, __) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/logs',
            builder: (_, __) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SizedBox.shrink(),
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
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}
