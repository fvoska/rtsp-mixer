import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/cameras/screens/camera_list_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';

/// GoRouter provider with auth-based redirect logic.
///
/// Watches [authNotifierProvider] and redirects:
/// - Unauthenticated users to /login
/// - Authenticated users away from /login to /cameras
final appRouterProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth state changes to GoRouter's Listenable-based refresh
  final authListenable = _AuthChangeNotifier(ref);

  return GoRouter(
    initialLocation: '/cameras',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final isAuthenticated = authState.value?.isAuthenticated ?? false;
      final isOnLogin = state.matchedLocation == '/login';

      // Still loading (initial auto-connect) -- don't redirect
      if (authState.isLoading && !authState.hasValue) return null;

      // Not authenticated and not on login page -> go to login
      if (!isAuthenticated && !isOnLogin) return '/login';

      // Authenticated and on login page -> go to cameras
      if (isAuthenticated && isOnLogin) return '/cameras';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/cameras',
        builder: (_, __) => const CameraListScreen(),
      ),
      GoRoute(
        path: '/monitoring',
        builder: (_, __) => const MonitoringScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod [authNotifierProvider] changes to GoRouter's
/// [Listenable]-based refresh mechanism.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) {
      notifyListeners();
    });
  }
}
