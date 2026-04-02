import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Creates a Dio instance configured for Protect API communication.
///
/// When [acceptSelfSigned] is true, the HTTP client accepts self-signed
/// certificates (required for Unifi Protect consoles which use self-signed certs).
Dio createProtectDio({required bool acceptSelfSigned}) {
  final dio = Dio();

  if (acceptSelfSigned) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    };
  }

  return dio;
}
