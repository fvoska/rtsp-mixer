import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/cameras/providers/camera_provider.dart';

/// Root application widget.
///
/// Uses [MaterialApp.router] with [GoRouter] for declarative navigation.
/// Shows a loading screen during initial auto-connect (D-07).
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    // Show loading screen during initial auto-connect attempt
    if (authState.isLoading && !authState.hasValue) {
      return MaterialApp(
        title: 'RTSP Audio Mixer',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    // If auto-connect succeeded, trigger camera loading
    if (authState.value?.isAuthenticated == true) {
      final host = authState.value?.host;
      if (host != null) {
        // Use addPostFrameCallback to avoid modifying providers during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final cameraState = ref.read(cameraNotifierProvider);
          // Only load if cameras haven't been loaded yet
          if (cameraState.value?.cameras.isEmpty ?? true) {
            ref.read(cameraNotifierProvider.notifier).loadCameras(host);
          }
        });
      }
    }

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'RTSP Audio Mixer',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
