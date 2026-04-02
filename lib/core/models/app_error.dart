enum AppErrorType { connectionRefused, invalidCredentials, timeout, unknown }

class AppError implements Exception {
  final AppErrorType type;
  final String message;
  const AppError({required this.type, required this.message});

  @override
  String toString() => message;
}
