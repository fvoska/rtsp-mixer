import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/core/models/app_error.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';

import '../../support/async.dart';

class FakeApiClient extends ProtectApiClient {
  bool verifyResult = true;
  AppError? verifyError;

  /// When set, [verifyConnection] blocks until this completes.
  ///
  /// The two background-validation tests assert on an ordering: the cached
  /// session is served as authenticated *first*, and validation revokes (or
  /// doesn't) *after*. Collapsing the notifier's delay to zero without a gate
  /// just races those two — validation can land before the test ever observes
  /// the cached state. The gate pins the order without any wall-clock waiting.
  Completer<void>? gate;

  /// Number of verifyConnection calls that have finished (returned or thrown).
  ///
  /// Background validation has no observable state change on the "network
  /// error → stay authenticated" path — it logs and returns — so the test waits
  /// on this counter to know validation really ran before asserting that auth
  /// survived it. Without that, the test would also pass if validation never
  /// happened at all.
  int verifySettledCount = 0;

  @override
  Future<bool> verifyConnection(String host) async {
    try {
      if (gate != null) await gate!.future;
      if (verifyError != null) throw verifyError!;
      return verifyResult;
    } finally {
      verifySettledCount++;
    }
  }

  @override
  Future<List<ProtectCamera>> getCameras(String host) async => [];

  @override
  Future<Map<String, String>> getRtspsUrls(String host, String cameraId) async => {};
}

ProviderContainer createContainer({
  required StorageService storage,
  required ProtectApiClient api,
}) {
  return ProviderContainer(overrides: [
    storageProvider.overrideWithValue(storage),
    apiClientProvider.overrideWithValue(api),
  ]);
}

Future<AuthState> waitForAuth(ProviderContainer c) async {
  return waitForValue<AuthState>(
    () {
      final v = c.read(authNotifierProvider);
      if (v is AsyncError) throw v.error!;
      return v is AsyncData<AuthState> ? v.value : null;
    },
    reason: 'AuthNotifier to settle into AsyncData',
  );
}

/// Whether the notifier currently reports an authenticated session.
bool _isAuthenticated(ProviderContainer c) =>
    c.read(authNotifierProvider).value?.isAuthenticated ?? false;

void main() {
  late StorageService storage;
  late FakeApiClient api;

  setUp(() {
    storage = StorageService();
    api = FakeApiClient();
    // Background validation normally waits 2s before it may revoke cached
    // auth. Collapse it so the two tests below observe the outcome without
    // sleeping through a real timer (and without racing its 1s of slack).
    AuthNotifier.backgroundValidationDelay = Duration.zero;
  });

  tearDown(() {
    AuthNotifier.backgroundValidationDelay = const Duration(seconds: 2);
  });

  group('AuthNotifier', () {
    test('unauthenticated when no saved credentials', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, false);
    });

    test('auto-connects with saved credentials', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyResult = true;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      expect(state.host, '10.0.0.1');
    });

    test('returns authenticated from cache then background validation revokes on failure', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyResult = false;
      // Hold validation until the cached state has been observed, so the two
      // halves of this test are ordered rather than racing.
      api.gate = Completer<void>();
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      // Initial state: authenticated from cache
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      // Release validation; waiting on the transition itself is the assertion.
      api.gate!.complete();
      await waitFor(
        () => !_isAuthenticated(c),
        reason: 'background validation to revoke the cached session',
      );
    });

    test('stays authenticated from cache on network error', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyError = const AppError(type: AppErrorType.connectionRefused, message: 'fail');
      api.gate = Completer<void>();
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      // Background validation fails but doesn't kick the user out (network
      // error). "Still authenticated" is a negative — it can't be waited on —
      // so release validation, wait for the attempt to have actually
      // completed, then assert. Otherwise the test would also pass if
      // validation never ran at all.
      api.gate!.complete();
      await waitFor(
        () => api.verifySettledCount > 0,
        reason: 'the background validation attempt to complete',
      );
      expect(_isAuthenticated(c), true);
    });

    test('login saves credentials on success', () async {
      api.verifyResult = true;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForAuth(c);

      await c.read(authNotifierProvider.notifier).login('1.2.3.4', 'new-key');
      final creds = await storage.loadCredentials();
      expect(creds!.host, '1.2.3.4');
      expect(creds.apiKey, 'new-key');
      expect(c.read(authNotifierProvider).value?.isAuthenticated, true);
    });

    test('login sets error on failure', () async {
      api.verifyResult = false;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForAuth(c);

      await c.read(authNotifierProvider.notifier).login('1.2.3.4', 'bad');
      final state = c.read(authNotifierProvider).value!;
      expect(state.isAuthenticated, false);
      expect(state.errorType, AppErrorType.invalidCredentials);
    });

    test('login sets error on connection error', () async {
      api.verifyError = const AppError(type: AppErrorType.connectionRefused, message: 'nope');
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForAuth(c);

      await c.read(authNotifierProvider.notifier).login('1.2.3.4', 'key');
      expect(c.read(authNotifierProvider).value?.errorType, AppErrorType.connectionRefused);
    });

    test('skipUnifi enters manual mode and persists the choice', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForAuth(c);

      await c.read(authNotifierProvider.notifier).skipUnifi();
      final state = c.read(authNotifierProvider).value!;
      expect(state.isAuthenticated, true);
      expect(state.isManualMode, true);
      expect(state.host, isNull);
      expect(await storage.loadAuthMode(), 'manual');
    });

    test('auto-enters manual mode on launch when auth_mode is manual', () async {
      await storage.saveAuthMode('manual');
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);

      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      expect(state.isManualMode, true);
      expect(state.host, isNull);
    });

    test('logout clears credentials', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyResult = true;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForAuth(c);

      await c.read(authNotifierProvider.notifier).logout();
      expect(c.read(authNotifierProvider).value?.isAuthenticated, false);
      expect(await storage.loadCredentials(), isNull);
    });

    test('clearResumeFlag flips resumeMonitoring to false', () async {
      // Simulate "app died mid-session" by setting the was_monitoring flag
      // before the notifier reads it on build().
      await storage.saveCredentials('10.0.0.1', 'key');
      await storage.write('was_monitoring', 'true');
      api.verifyResult = true;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.resumeMonitoring, isTrue,
          reason: 'was_monitoring=true should surface as resumeMonitoring');

      c.read(authNotifierProvider.notifier).clearResumeFlag();
      expect(
        c.read(authNotifierProvider).value?.resumeMonitoring,
        isFalse,
        reason: 'after clearResumeFlag the predicate driving the stop banner '
            'must read false — otherwise the banner stays visible forever and '
            'the Stop button looks broken',
      );
      // host preserved
      expect(c.read(authNotifierProvider).value?.host, '10.0.0.1');
    });

    test('clearResumeFlag is a no-op when already false', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyResult = true;
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.resumeMonitoring, isFalse);
      // Should not throw, should leave state untouched.
      c.read(authNotifierProvider.notifier).clearResumeFlag();
      expect(c.read(authNotifierProvider).value?.isAuthenticated, isTrue);
    });
  });
}
