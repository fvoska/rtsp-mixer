import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../logging/app_logger.dart';
import '../models/app_error.dart';
import '../../features/cameras/models/protect_camera.dart';

/// Client for the official Unifi Protect API (integration/v1).
/// Authenticates via X-API-Key header.
class ProtectApiClient {
  late final Dio _dio;
  String? _apiKey;

  ProtectApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
    ));

    // Accept self-signed certificates (Unifi consoles use them)
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (_, _, _) => true;
      return client;
    };

    // Retry on 429 with exponential backoff
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (error.response?.statusCode == 429) {
          final retries = (error.requestOptions.extra['_retryCount'] as int?) ?? 0;
          if (retries < 3) {
            final delay = Duration(seconds: 1 << retries); // 1s, 2s, 4s
            appLog('API', '429 rate limited, retry ${retries + 1}/3 after ${delay.inSeconds}s');
            await Future.delayed(delay);
            error.requestOptions.extra['_retryCount'] = retries + 1;
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } on DioException catch (e) {
              return handler.reject(e);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

  void setApiKey(String key) => _apiKey = key;

  // ignore: use_setters_to_change_properties
  /// Test-only: replace the Dio instance with a mock.
  void setDioForTest(Dio dio) => _dio = dio;

  String _url(String host, String path) =>
      'https://$host/proxy/protect/integration/v1$path';

  /// Verify the API key by fetching camera list. Returns true on 200.
  Future<bool> verifyConnection(String host) async {
    final url = _url(host, '/cameras');
    appLog('API', 'GET $url');
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {'X-API-Key': _apiKey},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      appLog('API', 'Response: ${response.statusCode}');
      return response.statusCode == 200;
    } on DioException catch (e) {
      appLog('API', 'Error: ${e.type} ${e.message} ${e.error}');
      throw _mapError(e);
    }
  }

  /// Fetch all cameras from the official Protect API.
  Future<List<ProtectCamera>> getCameras(String host) async {
    final url = _url(host, '/cameras');
    appLog('API', 'GET $url (cameras)');
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: {'X-API-Key': _apiKey}),
      );
      appLog('API', 'Got ${(response.data as List).length} cameras');
      return (response.data as List<dynamic>)
          .map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      appLog('API', 'Error fetching cameras: ${e.type} ${e.message}');
      throw _mapError(e);
    }
  }

  /// Fetch all available RTSPS stream URLs for a camera from the integration API.
  /// Returns a map of quality → URL (e.g. {"high": "rtsps://...", "medium": "rtsps://..."}).
  Future<Map<String, String>> getRtspsUrls(String host, String cameraId) async {
    final url = _url(host, '/cameras/$cameraId/rtsps-stream');
    appLog('API', 'GET $url');
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: {'X-API-Key': _apiKey}),
      );
      final data = response.data as Map<String, dynamic>;
      final urls = <String, String>{};
      for (final key in ['low', 'medium', 'high']) {
        final value = data[key] as String?;
        if (value != null) urls[key] = value;
      }
      appLog('API', 'RTSPS URLs for $cameraId: ${urls.keys.join(', ')}');
      return urls;
    } on DioException catch (e) {
      appLog('API', 'Error fetching RTSPS URLs for $cameraId: ${e.type} ${e.message}');
      return {};
    }
  }

  AppError _mapError(DioException e) {
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      return const AppError(
        type: AppErrorType.invalidCredentials,
        message: 'Invalid API key.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const AppError(
        type: AppErrorType.connectionRefused,
        message: 'Cannot reach console. Check IP and network.',
      );
    }
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const AppError(
        type: AppErrorType.timeout,
        message: 'Connection timed out.',
      );
    }
    return AppError(
      type: AppErrorType.unknown,
      message: e.message ?? 'Unknown error.',
    );
  }
}
