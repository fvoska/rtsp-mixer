import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rtsp_audio_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_audio_mixer/core/api/protect_api_client_provider.dart';
import 'package:rtsp_audio_mixer/core/api/protect_auth_interceptor.dart';
import 'package:rtsp_audio_mixer/core/models/app_error.dart';
import 'package:rtsp_audio_mixer/core/storage/secure_storage_provider.dart';
import 'package:rtsp_audio_mixer/core/storage/secure_storage_service.dart';
import 'package:rtsp_audio_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_audio_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/protect_camera.dart';

import '../../core/storage/fake_flutter_secure_storage.dart';

/// Fake API client for testing auth flows.
class FakeProtectApiClient extends ProtectApiClient {
  bool loginResult = true;
  AppError? loginError;
  List<ProtectCamera> bootstrapResult = [];

  FakeProtectApiClient()
      : super(
          dio: Dio(),
          authInterceptor: ProtectAuthInterceptor(),
        );

  @override
  Future<bool> login(String host, String username, String password) async {
    if (loginError != null) throw loginError!;
    return loginResult;
  }

  @override
  Future<List<ProtectCamera>> getBootstrap(String host) async {
    return bootstrapResult;
  }
}

ProviderContainer createContainer({
  required SecureStorageService storage,
  required ProtectApiClient apiClient,
}) {
  return ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      protectApiClientProvider.overrideWithValue(apiClient),
    ],
  );
}

/// Helper to wait for an AsyncNotifier to settle.
Future<AuthState> waitForAuthState(ProviderContainer container) async {
  // Wait for the async build to complete
  AuthState? result;
  for (var i = 0; i < 100; i++) {
    final value = container.read(authNotifierProvider);
    if (value is AsyncData<AuthState>) {
      result = value.value;
      break;
    }
    if (value is AsyncError) {
      throw value.error!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (result == null) {
    throw StateError('AuthNotifier did not settle within timeout');
  }
  return result;
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late SecureStorageService storageService;
  late FakeProtectApiClient fakeApiClient;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    storageService = SecureStorageService(fakeStorage);
    fakeApiClient = FakeProtectApiClient();
  });

  group('AuthNotifier', () {
    test('auto-connects with saved credentials on build', () async {
      // Pre-save credentials
      await storageService.saveCredentials('192.168.1.1', 'admin', 'pass');
      fakeApiClient.loginResult = true;

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      final authState = await waitForAuthState(container);

      expect(authState.isAuthenticated, isTrue);
      expect(authState.host, '192.168.1.1');
    });

    test('returns unauthenticated when no saved credentials', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      final authState = await waitForAuthState(container);

      expect(authState.isAuthenticated, isFalse);
      expect(authState.errorMessage, isNull);
    });

    test('falls back to unauthenticated when auto-connect fails', () async {
      await storageService.saveCredentials('192.168.1.1', 'admin', 'pass');
      fakeApiClient.loginResult = false;

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      final authState = await waitForAuthState(container);

      expect(authState.isAuthenticated, isFalse);
      expect(authState.errorMessage, contains('Could not reconnect'));
    });

    test('falls back to unauthenticated when auto-connect throws', () async {
      await storageService.saveCredentials('192.168.1.1', 'admin', 'pass');
      fakeApiClient.loginError = const AppError(
        type: AppErrorType.connectionRefused,
        message: 'Connection refused',
      );

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      final authState = await waitForAuthState(container);

      expect(authState.isAuthenticated, isFalse);
      expect(authState.errorMessage, contains('Could not reconnect'));
    });

    test('persists credentials on successful login', () async {
      fakeApiClient.loginResult = true;

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      // Wait for build to complete
      await waitForAuthState(container);

      // Perform login
      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.login('10.0.0.1', 'user', 'secret');

      // Check credentials were saved
      final creds = await storageService.loadCredentials();
      expect(creds, isNotNull);
      expect(creds!.host, '10.0.0.1');
      expect(creds.username, 'user');
      expect(creds.password, 'secret');

      // Check auth state
      final state = container.read(authNotifierProvider);
      expect(state.value?.isAuthenticated, isTrue);
      expect(state.value?.host, '10.0.0.1');
    });

    test('sets error state on failed login', () async {
      fakeApiClient.loginResult = false;

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForAuthState(container);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.login('10.0.0.1', 'user', 'wrong');

      final state = container.read(authNotifierProvider);
      expect(state.value?.isAuthenticated, isFalse);
      expect(state.value?.errorMessage, contains('Invalid'));
      expect(state.value?.errorType, AppErrorType.invalidCredentials);
    });

    test('sets error state on login connection error', () async {
      fakeApiClient.loginError = const AppError(
        type: AppErrorType.connectionRefused,
        message: 'Could not reach the console.',
      );

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForAuthState(container);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.login('10.0.0.1', 'user', 'pass');

      final state = container.read(authNotifierProvider);
      expect(state.value?.isAuthenticated, isFalse);
      expect(state.value?.errorType, AppErrorType.connectionRefused);
    });

    test('clears credentials on logout', () async {
      // Start authenticated
      await storageService.saveCredentials('192.168.1.1', 'admin', 'pass');
      fakeApiClient.loginResult = true;

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      final authState = await waitForAuthState(container);
      expect(authState.isAuthenticated, isTrue);

      // Logout
      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.logout();

      // Check state
      final state = container.read(authNotifierProvider);
      expect(state.value?.isAuthenticated, isFalse);

      // Check credentials cleared
      final creds = await storageService.loadCredentials();
      expect(creds, isNull);
    });
  });
}
