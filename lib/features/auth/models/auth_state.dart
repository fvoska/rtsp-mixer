import '../../../core/models/app_error.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated }

class AuthState {
  final AuthStatus status;
  final String? host;
  final String? errorMessage;
  final AppErrorType? errorType;

  const AuthState.unauthenticated({this.errorMessage, this.errorType})
      : status = AuthStatus.unauthenticated,
        host = null;

  const AuthState.authenticated({required this.host})
      : status = AuthStatus.authenticated,
        errorMessage = null,
        errorType = null;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
