import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_audio_mixer/core/api/dio_client.dart';

void main() {
  group('Dio Client Factory', () {
    test('creates Dio instance that accepts self-signed certs when configured',
        () {
      final dio = createProtectDio(acceptSelfSigned: true);

      // Verify the adapter is IOHttpClientAdapter (it always is on non-web)
      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());

      // Verify createHttpClient was set (the function is non-null)
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNotNull);
    });

    test('creates Dio instance with default cert validation when not configured',
        () {
      final dio = createProtectDio(acceptSelfSigned: false);

      expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
      // createHttpClient should be null (default behavior)
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNull);
    });
  });
}
