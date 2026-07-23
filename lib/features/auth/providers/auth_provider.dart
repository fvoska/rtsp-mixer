import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/protect_api_client.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_error.dart';
import '../../../core/storage/storage_service.dart';
import '../../cameras/providers/camera_provider.dart';
import '../models/auth_state.dart';

final apiClientProvider = Provider((_) => ProtectApiClient());
final storageProvider = Provider((_) => StorageService());

/// Normalize a user-entered console address: trim whitespace, strip a pasted
/// scheme prefix (e.g. `https://`), and strip trailing slashes. Returns null
/// when the result is empty. Never throws.
String? normalizeHostInput(String? raw) {
  try {
    var host = (raw ?? '').trim();
    final schemeMatch =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').firstMatch(host);
    if (schemeMatch != null) host = host.substring(schemeMatch.end);
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    return host.isEmpty ? null : host;
  } catch (_) {
    return raw?.trim().isEmpty ?? true ? null : raw!.trim();
  }
}

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
      // No Unifi credentials — but the user may have set up manual mode.
      final mode = await storage.loadAuthMode();
      if (mode == 'manual') {
        appLog('AUTH', 'Manual mode (no Unifi credentials)');
        final remoteHost = await _loadRemoteHostSafe(storage);
        await ref.read(cameraNotifierProvider.notifier).loadCameras();
        final wasMonitoring = await storage.read('was_monitoring') == 'true';
        return AuthState.manual(
          remoteHost: remoteHost,
          resumeMonitoring: wasMonitoring,
        );
      }
      appLog('AUTH', 'No saved credentials');
      return const AuthState.unauthenticated();
    }

    // Set API key immediately so camera loading can use it
    final client = ref.read(apiClientProvider);
    client.setApiKey(creds.apiKey);

    final remoteHost = await _loadRemoteHostSafe(storage);

    // Load cached cameras (instant, no network)
    await ref
        .read(cameraNotifierProvider.notifier)
        .loadCameras(creds.host, remoteHost);

    final wasMonitoring = await storage.read('was_monitoring') == 'true';
    appLog('AUTH', 'Cached credentials found (wasMonitoring=$wasMonitoring), validating in background...');

    // Validate credentials in background — interrupt if invalid
    _validateInBackground(creds.host, remoteHost, creds.apiKey);

    return AuthState.authenticated(
      host: creds.host,
      remoteHost: remoteHost,
      resumeMonitoring: wasMonitoring,
    );
  }

  /// Read the persisted remote console address. Defensive: storage failures
  /// degrade to "no remote configured" rather than blocking auth.
  Future<String?> _loadRemoteHostSafe(StorageService storage) async {
    try {
      final remote = await storage.loadRemoteHost();
      return (remote == null || remote.trim().isEmpty) ? null : remote.trim();
    } catch (e) {
      appLog('AUTH', 'Failed to load remote host (continuing without): $e');
      return null;
    }
  }

  /// Whether an [AppError] represents "host unreachable" — the only class of
  /// failure where trying the remote address makes sense. Auth errors (bad
  /// key) would fail identically on both addresses.
  static bool _isReachabilityError(AppError e) =>
      e.type == AppErrorType.connectionRefused ||
      e.type == AppErrorType.timeout;

  /// Verify the connection against the local host first, falling back to the
  /// remote host when the local attempt fails with a reachability error.
  ///
  /// Returns the verification result plus whichever host answered. When both
  /// hosts fail, the LOCAL attempt's error is surfaced (the remote failure is
  /// logged, never escalated — it must not mask the primary error).
  Future<({bool ok, String host})> _verifyWithFallback(
    ProtectApiClient client,
    String localHost,
    String? remoteHost,
  ) async {
    try {
      final ok = await client.verifyConnection(localHost);
      return (ok: ok, host: localHost);
    } on AppError catch (localError) {
      if (_isReachabilityError(localError) &&
          remoteHost != null &&
          remoteHost.isNotEmpty &&
          remoteHost != localHost) {
        appLog('AUTH',
            'Local host $localHost unreachable (${localError.type.name}) — trying remote host $remoteHost');
        try {
          final ok = await client.verifyConnection(remoteHost);
          appLog('AUTH', 'Remote host $remoteHost answered (ok=$ok)');
          return (ok: ok, host: remoteHost);
        } catch (remoteError) {
          // Never mask the local error with the remote one.
          appLog('AUTH', 'Remote host attempt also failed: $remoteError');
        }
      }
      rethrow;
    }
  }

  void _validateInBackground(String host, String? remoteHost, String apiKey) {
    Future(() async {
      // Let the UI settle with cached state before potentially revoking
      await Future.delayed(const Duration(seconds: 2));
      try {
        final client = ref.read(apiClientProvider);
        final result = await _verifyWithFallback(client, host, remoteHost);
        if (!result.ok) {
          appLog('AUTH', 'Background validation failed — credentials invalid');
          state = const AsyncData(AuthState.unauthenticated(
            errorMessage: 'API key is no longer valid. Please re-enter.',
          ));
        } else {
          appLog('AUTH',
              'Background validation succeeded via ${result.host == host ? "local" : "remote"} host');
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
    final storage = ref.read(storageProvider);
    final remoteHost = await _loadRemoteHostSafe(storage);
    try {
      final result = await _verifyWithFallback(client, host, remoteHost);
      if (result.ok) {
        appLog('AUTH',
            'Login succeeded via ${result.host == host ? "local" : "remote"} host');
        await storage.saveCredentials(host, apiKey);
        await storage.saveAuthMode('unifi');
        // Lead with whichever host answered so the camera refresh doesn't
        // sit through another connect timeout; the other host stays as the
        // fallback candidate.
        final fallback = result.host == host ? remoteHost : host;
        await ref
            .read(cameraNotifierProvider.notifier)
            .loadCameras(result.host, fallback);
        state = AsyncData(
            AuthState.authenticated(host: host, remoteHost: remoteHost));
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

  /// Update the console's local (primary) address. Persists it, updates the
  /// in-memory state, and reloads cameras against the new address. Covers
  /// the "set up away from home via the remote address, add the real local
  /// address later" flow — the user can also swap values between the fields.
  Future<void> updateLocalHost(String host) async {
    final normalized = normalizeHostInput(host);
    if (normalized == null) {
      appLog('AUTH', 'updateLocalHost ignored — empty input');
      return;
    }
    appLog('AUTH', 'updateLocalHost($normalized)');
    final storage = ref.read(storageProvider);
    try {
      // saveCredentials owns the 'host' key; write it directly so we don't
      // need to re-read + re-write the API key.
      await storage.write('host', normalized);
    } catch (e) {
      appLog('AUTH', 'Failed to persist local host (continuing): $e');
    }
    final current = state.value;
    if (current != null && current.isAuthenticated && !current.isManualMode) {
      state = AsyncData(AuthState.authenticated(
        host: normalized,
        remoteHost: current.remoteHost,
        resumeMonitoring: current.resumeMonitoring,
      ));
    }
    await _reloadCamerasSafe(normalized);
  }

  /// Set or clear the console's remote (VPN/Tailscale) address. Null or an
  /// empty string clears it. Persists, updates state, reloads cameras.
  Future<void> updateRemoteHost(String? host) async {
    final normalized = normalizeHostInput(host);
    appLog('AUTH', 'updateRemoteHost(${normalized ?? "<clear>"})');
    final storage = ref.read(storageProvider);
    try {
      if (normalized == null) {
        await storage.deleteRemoteHost();
      } else {
        await storage.saveRemoteHost(normalized);
      }
    } catch (e) {
      appLog('AUTH', 'Failed to persist remote host (continuing): $e');
    }
    final current = state.value;
    if (current != null && current.isAuthenticated) {
      state = AsyncData(current.isManualMode
          ? AuthState.manual(
              remoteHost: normalized,
              resumeMonitoring: current.resumeMonitoring,
            )
          : AuthState.authenticated(
              host: current.host,
              remoteHost: normalized,
              resumeMonitoring: current.resumeMonitoring,
            ));
    }
    // No-op in manual mode (host is null) — manual cameras need no API reload.
    await _reloadCamerasSafe(current?.host);
  }

  /// Trigger a camera reload with the current local + remote addresses.
  /// Defensive: a reload failure never surfaces to the settings UI.
  Future<void> _reloadCamerasSafe(String? localHost) async {
    if (localHost == null || localHost.isEmpty) return;
    try {
      final storage = ref.read(storageProvider);
      final remote = await _loadRemoteHostSafe(storage);
      await ref
          .read(cameraNotifierProvider.notifier)
          .loadCameras(localHost, remote);
    } catch (e) {
      appLog('AUTH', 'Camera reload after host update failed (continuing): $e');
    }
  }

  /// Skip Unifi login and use manually-entered RTSP URLs only. Persists the
  /// choice so the app returns to manual mode on next launch instead of the
  /// login screen.
  Future<void> skipUnifi() async {
    appLog('AUTH', 'Skipping Unifi login — entering manual mode');
    final storage = ref.read(storageProvider);
    await storage.saveAuthMode('manual');
    await ref.read(cameraNotifierProvider.notifier).loadCameras();
    state = const AsyncData(AuthState.manual());
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
    state = AsyncData(current.isManualMode
        ? AuthState.manual(
            remoteHost: current.remoteHost,
            resumeMonitoring: false,
          )
        : AuthState.authenticated(
            host: current.host,
            remoteHost: current.remoteHost,
            resumeMonitoring: false,
          ));
    appLog('AUTH', 'Cleared resumeMonitoring flag');
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
