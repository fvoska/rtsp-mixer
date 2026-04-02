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
      client.badCertificateCallback = (_, __, ___) => true;
      return client;
    };
  }

  void setApiKey(String key) => _apiKey = key;

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
