import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/cameras/providers/camera_provider.dart';
import '../../features/cameras/screens/camera_list_screen.dart';
import '../../features/monitoring/screens/log_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthRefreshNotifier(ref);
  bool camerasLoaded = false;

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authListenable,
    redirect: (_, state) {
      final auth = ref.read(authNotifierProvider);
      final authenticated = auth.value?.isAuthenticated ?? false;
      final location = state.matchedLocation;

      // Still loading auth — stay where we are
      if (auth.isLoading && !auth.hasValue) return null;

      // Not authenticated — go to login
      if (!authenticated) {
        return location == '/login' ? null : '/login';
      }

      // Authenticated — kick off camera loading once
      if (!camerasLoaded) {
        camerasLoaded = true;
        final host = auth.value?.host;
        if (host != null) {
          ref.read(cameraNotifierProvider.notifier).loadCameras(host);
        }
      }

      // If still on login, redirect to the right place
      if (location == '/login') {
        if (auth.value?.resumeMonitoring == true) {
          return '/monitoring';
        }
        return '/cameras';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/cameras', builder: (_, __) => const CameraListScreen()),
      GoRoute(path: '/monitoring', builder: (_, __) => const MonitoringScreen()),
      GoRoute(path: '/logs', builder: (_, __) => const LogScreen()),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}
