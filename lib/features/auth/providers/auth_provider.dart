import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/protect_api_client.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_error.dart';
import '../../../core/storage/storage_service.dart';
import '../models/auth_state.dart';

final apiClientProvider = Provider((_) => ProtectApiClient());
final storageProvider = Provider((_) => StorageService());

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    appLog('AUTH', 'build() — checking saved credentials');
    final storage = ref.read(storageProvider);
    final creds = await storage.loadCredentials();
    if (creds == null) {
      appLog('AUTH', 'No saved credentials');
      return const AuthState.unauthenticated();
    }
    appLog('AUTH', 'Found saved credentials, auto-connecting...');
    final client = ref.read(apiClientProvider);
    client.setApiKey(creds.apiKey);
    try {
      final ok = await client.verifyConnection(creds.host);
      if (ok) {
        appLog('AUTH', 'Auto-connect succeeded');
        final wasMonitoring = await storage.read('was_monitoring') == 'true';
        return AuthState.authenticated(host: creds.host, resumeMonitoring: wasMonitoring);
      }
      appLog('AUTH', 'Auto-connect failed (bad key?)');
      return const AuthState.unauthenticated(
        errorMessage: 'Could not reconnect. Check API key.',
      );
    } catch (e) {
      appLog('AUTH', 'Auto-connect error: $e');
      return const AuthState.unauthenticated(
        errorMessage: 'Could not reconnect.',
      );
    }
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
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
