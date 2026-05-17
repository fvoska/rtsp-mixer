import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/protect_api_client.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_error.dart';
import '../../../core/storage/storage_service.dart';
import '../../cameras/providers/camera_provider.dart';
import '../models/auth_state.dart';

final apiClientProvider = Provider((_) => ProtectApiClient());
final storageProvider = Provider((_) => StorageService());

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    appLog('AUTH', 'build() — checking saved credentials');
    final storage = ref.read(storageProvider);
    // Reset Keychain if this is the first launch after a reinstall.
    // flutter_secure_storage on macOS/iOS is Keychain-backed, which survives
    // app uninstall — without this, a fresh install inherits the previous
    // install's credentials, `was_monitoring`, and camera selections, and
    // auto-resumes into a stale session.
    await storage.ensureFreshInstallChecked();
    final creds = await storage.loadCredentials();
    if (creds == null) {
      appLog('AUTH', 'No saved credentials');
      return const AuthState.unauthenticated();
    }

    // Set API key immediately so camera loading can use it
    final client = ref.read(apiClientProvider);
    client.setApiKey(creds.apiKey);

    // Load cached cameras (instant, no network)
    await ref.read(cameraNotifierProvider.notifier).loadCameras(creds.host);

    final wasMonitoring = await storage.read('was_monitoring') == 'true';
    appLog('AUTH', 'Cached credentials found (wasMonitoring=$wasMonitoring), validating in background...');

    // Validate credentials in background — interrupt if invalid
    _validateInBackground(creds.host, creds.apiKey);

    return AuthState.authenticated(host: creds.host, resumeMonitoring: wasMonitoring);
  }

  void _validateInBackground(String host, String apiKey) {
    Future(() async {
      // Let the UI settle with cached state before potentially revoking
      await Future.delayed(const Duration(seconds: 2));
      try {
        final client = ref.read(apiClientProvider);
        final ok = await client.verifyConnection(host);
        if (!ok) {
          appLog('AUTH', 'Background validation failed — credentials invalid');
          state = const AsyncData(AuthState.unauthenticated(
            errorMessage: 'API key is no longer valid. Please re-enter.',
          ));
        } else {
          appLog('AUTH', 'Background validation succeeded');
        }
      } catch (e) {
        appLog('AUTH', 'Background validation error: $e');
        // Network error — don't kick user out, cached state is fine
      }
    });
  }

  Future<void> login(String host, String apiKey) async {
    appLog('AUTH', 'login($host, key=${apiKey.length}chars)');
    state = const AsyncLoading();
    final client = ref.read(apiClientProvider);
    client.setApiKey(apiKey);
    try {
      final ok = await client.verifyConnection(host);
      if (ok) {
        appLog('AUTH', 'Login succeeded');
        final storage = ref.read(storageProvider);
        await storage.saveCredentials(host, apiKey);
        await ref.read(cameraNotifierProvider.notifier).loadCameras(host);
        state = AsyncData(AuthState.authenticated(host: host));
      } else {
        appLog('AUTH', 'Login failed — bad response');
        state = const AsyncData(AuthState.unauthenticated(
          errorMessage: 'Invalid API key.',
          errorType: AppErrorType.invalidCredentials,
        ));
      }
    } on AppError catch (e) {
      appLog('AUTH', 'Login AppError: ${e.type} ${e.message}');
      state = AsyncData(AuthState.unauthenticated(
        errorMessage: e.message,
        errorType: e.type,
      ));
    } catch (e) {
      appLog('AUTH', 'Login unexpected error: $e');
      state = AsyncData(AuthState.unauthenticated(
        errorMessage: 'Unexpected error: $e',
        errorType: AppErrorType.unknown,
      ));
    }
  }

  Future<void> logout() async {
    appLog('AUTH', 'Logging out');
    final storage = ref.read(storageProvider);
    await storage.clearAll();
    state = const AsyncData(AuthState.unauthenticated());
  }

  /// Drop the resumeMonitoring flag from the current AuthState.
  ///
  /// resumeMonitoring is set at app-launch from the persisted `was_monitoring`
  /// key and reflects "the app died with monitoring running — resume it." Once
  /// the user explicitly stops monitoring, that signal is no longer valid;
  /// without clearing it the UI predicates that combine it with session state
  /// (inline stop banner, ActiveSessionBar) would stay visible forever,
  /// making the Stop button look broken.
  void clearResumeFlag() {
    final current = state.value;
    if (current == null || !current.isAuthenticated) return;
    if (!current.resumeMonitoring) return;
    state = AsyncData(AuthState.authenticated(
      host: current.host,
      resumeMonitoring: false,
    ));
    appLog('AUTH', 'Cleared resumeMonitoring flag');
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
