import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/core/models/app_error.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';

class FakeApiClient extends ProtectApiClient {
  bool verifyResult = true;
  AppError? verifyError;

  @override
  Future<bool> verifyConnection(String host) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult;
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
  for (var i = 0; i < 100; i++) {
    final v = c.read(authNotifierProvider);
    if (v is AsyncData<AuthState>) return v.value;
    if (v is AsyncError) throw v.error!;
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('AuthNotifier did not settle');
}

void main() {
  late StorageService storage;
  late FakeApiClient api;

  setUp(() {
    storage = StorageService();
    api = FakeApiClient();
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
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      // Initial state: authenticated from cache
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      // Background validation runs after 2s delay and revokes
      await Future.delayed(const Duration(seconds: 3));
      expect(c.read(authNotifierProvider).value?.isAuthenticated, false);
    });

    test('stays authenticated from cache on network error', () async {
      await storage.saveCredentials('10.0.0.1', 'key');
      api.verifyError = const AppError(type: AppErrorType.connectionRefused, message: 'fail');
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      final state = await waitForAuth(c);
      expect(state.isAuthenticated, true);
      // Background validation fails but doesn't kick user out (network error)
      await Future.delayed(const Duration(seconds: 3));
      expect(c.read(authNotifierProvider).value?.isAuthenticated, true);
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
