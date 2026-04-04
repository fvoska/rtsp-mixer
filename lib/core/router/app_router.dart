import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/cameras/providers/camera_provider.dart';
import '../../features/cameras/screens/camera_list_screen.dart';
import '../../features/monitoring/screens/monitoring_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthRefreshNotifier(ref);
  bool resumeHandled = false;

  return GoRouter(
    initialLocation: '/cameras',
    refreshListenable: authListenable,
    redirect: (_, state) {
      final auth = ref.read(authNotifierProvider);
      final authenticated = auth.value?.isAuthenticated ?? false;
      final onLogin = state.matchedLocation == '/login';

      if (auth.isLoading && !auth.hasValue) return null;
      if (!authenticated && !onLogin) return '/login';
      if (authenticated && onLogin) return '/cameras';

      // Auto-resume: load cameras and go straight to monitoring
      if (authenticated && !resumeHandled) {
        resumeHandled = true;
        final host = auth.value?.host;
        if (host != null) {
          // Fire-and-forget camera loading — monitoring screen waits for it
          ref.read(cameraNotifierProvider.notifier).loadCameras(host);
          if (auth.value?.resumeMonitoring == true) {
            return '/monitoring';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/cameras', builder: (_, __) => const CameraListScreen()),
      GoRoute(path: '/monitoring', builder: (_, __) => const MonitoringScreen()),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}
