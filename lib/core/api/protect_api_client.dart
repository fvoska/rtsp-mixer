import 'package:dio/dio.dart';

import '../../features/cameras/models/protect_camera.dart';
import '../models/app_error.dart';
import 'protect_auth_interceptor.dart';

/// Single API client for Unifi Protect authentication and camera discovery (D-11).
///
/// Handles login with CSRF token management, bootstrap data fetching,
/// and camera list parsing. Uses a [ProtectAuthInterceptor] to automatically
/// inject auth headers on all requests.
class ProtectApiClient {
  final Dio _dio;
  final ProtectAuthInterceptor _authInterceptor;
  String? _host;
  String? _lastUpdateId;

  ProtectApiClient({
    required Dio dio,
    required ProtectAuthInterceptor authInterceptor,
  })  : _dio = dio,
        _authInterceptor = authInterceptor {
    _dio.interceptors.add(_authInterceptor);
  }

  /// The last update ID from the most recent bootstrap response.
  /// Used to initialize WebSocket connections for real-time events.
  String? get lastUpdateId => _lastUpdateId;

  /// Authenticate with the Protect console.
  ///
  /// Returns true on success, false on invalid credentials.
  /// Throws [AppError] on connection failures.
  ///
  /// If the initial login returns 403 without a CSRF token, fetches the
  /// base URL first to acquire an initial CSRF token, then retries.
  Future<bool> login(String host, String username, String password) async {
    _host = host;

    try {
      return await _attemptLogin(host, username, password);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return false;
      }
      if (e.response?.statusCode == 403 && _authInterceptor.csrfToken == null) {
        // Fetch initial CSRF token and retry
        await _fetchInitialCsrf(host);
        try {
          return await _attemptLogin(host, username, password);
        } on DioException catch (retryError) {
          if (retryError.response?.statusCode == 401) {
            return false;
          }
          throw _mapDioError(retryError);
        }
      }
      throw _mapDioError(e);
    }
  }

  Future<bool> _attemptLogin(
      String host, String username, String password) async {
    final response = await _dio.post(
      'https://$host/api/auth/login',
      data: {
        'username': username,
        'password': password,
        'rememberMe': true,
        'token': '',
      },
      options: Options(
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode == 200) {
      return true;
    }
    if (response.statusCode == 401) {
      return false;
    }
    // Re-throw as DioException for 403 etc.
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  /// Fetch the base URL to acquire an initial CSRF token from response headers.
  Future<void> _fetchInitialCsrf(String host) async {
    await _dio.get(
      'https://$host/',
      options: Options(
        validateStatus: (status) => true,
      ),
    );
    // The ProtectAuthInterceptor will automatically extract the CSRF token
    // from the response headers.
  }

  /// Fetch bootstrap data from Protect API and return camera list.
  ///
  /// Requires prior successful [login].
  Future<List<ProtectCamera>> getBootstrap(String host) async {
    _host = host;

    try {
      final response = await _dio.get(
        'https://$host/proxy/protect/api/bootstrap',
      );

      final data = response.data as Map<String, dynamic>;
      _lastUpdateId = data['lastUpdateId'] as String?;

      final cameras = (data['cameras'] as List<dynamic>)
          .map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>))
          .toList();

      return cameras;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  AppError _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return const AppError(
          type: AppErrorType.connectionRefused,
          message:
              'Could not reach the console. Check the IP address and make sure you are on the same network.',
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppError(
          type: AppErrorType.timeout,
          message: 'Connection timed out. Please try again.',
        );
      default:
        if (e.response?.statusCode == 401) {
          return const AppError(
            type: AppErrorType.invalidCredentials,
            message: 'Invalid username or password.',
          );
        }
        return AppError(
          type: AppErrorType.unknown,
          message: e.message ?? 'An unknown error occurred.',
        );
    }
  }
}
