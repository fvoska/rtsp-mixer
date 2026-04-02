import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/protect_api_client_provider.dart';
import '../../../core/models/app_error.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../models/auth_state.dart';

/// Auth state notifier that handles login, auto-connect (D-07), and logout.
///
/// On build, checks for saved credentials and auto-connects.
/// If auto-connect fails, returns unauthenticated with error message.
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final storage = ref.read(secureStorageProvider);
    final credentials = await storage.loadCredentials();

    if (credentials == null) {
      return const AuthState.unauthenticated();
    }

    try {
      final client = ref.read(protectApiClientProvider);
      final success = await client.login(
        credentials.host,
        credentials.username,
        credentials.password,
      );

      if (success) {
        return AuthState.authenticated(host: credentials.host);
      }
      return const AuthState.unauthenticated(
        errorMessage: 'Could not reconnect. Please sign in again.',
      );
    } catch (e) {
      return const AuthState.unauthenticated(
        errorMessage: 'Could not reconnect. Please sign in again.',
      );
    }
  }

  /// Attempt login with provided credentials.
  ///
  /// On success, saves credentials to secure storage and transitions to
  /// authenticated state. On failure, sets error state with mapped error.
  Future<void> login(String host, String username, String password) async {
    state = const AsyncLoading();

    try {
      final client = ref.read(protectApiClientProvider);
      final success = await client.login(host, username, password);

      if (success) {
        final storage = ref.read(secureStorageProvider);
        await storage.saveCredentials(host, username, password);
        state = AsyncData(AuthState.authenticated(host: host));
      } else {
        state = const AsyncData(AuthState.unauthenticated(
          errorMessage: 'Invalid username or password.',
          errorType: AppErrorType.invalidCredentials,
        ));
      }
    } on AppError catch (e) {
      state = AsyncData(AuthState.unauthenticated(
        errorMessage: e.message,
        errorType: e.type,
      ));
    } catch (e) {
      state = AsyncData(AuthState.unauthenticated(
        errorMessage: 'An unexpected error occurred.',
        errorType: AppErrorType.unknown,
      ));
    }
  }

  /// Clear credentials and return to unauthenticated state.
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.clearCredentials();
    state = const AsyncData(AuthState.unauthenticated());
  }
}

/// Provider for the auth notifier.
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
