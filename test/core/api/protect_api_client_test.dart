import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/core/models/app_error.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';

/// A [HttpClientAdapter] that returns scripted responses.
///
/// Used with [ProtectApiClient.setHttpClientAdapterForTest] so the client's own
/// Dio — including the 429 retry interceptor — stays in the path. Each call
/// pops the next scripted reply, so a retry sequence can be scripted as
/// `[429, 200]`.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.replies);

  /// Each entry is either a `(statusCode, body)` pair or a [DioException] to
  /// throw (for transport-level failures like a connection error).
  final List<Object> replies;
  final List<RequestOptions> requests = [];
  int _next = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    // Past the end of the script, keep returning the last reply — a test that
    // under-scripts its retries should fail on its request-count assertion,
    // not on a RangeError from the adapter.
    final reply = replies[_next < replies.length ? _next++ : replies.length - 1];
    if (reply is DioExceptionType) {
      throw DioException(requestOptions: options, type: reply);
    }
    final (int status, Object? body) = reply as (int, Object?);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProtectApiClient _client(_ScriptedAdapter adapter) {
  final client = ProtectApiClient()..setApiKey('test-key');
  client.setHttpClientAdapterForTest(adapter);
  return client;
}

void main() {
  setUp(() {
    // Keep the 429 backoff out of wall-clock time.
    ProtectApiClient.retryBaseDelay = Duration.zero;
  });

  tearDown(() {
    ProtectApiClient.retryBaseDelay = const Duration(seconds: 1);
  });

  group('ProtectApiClient camera parsing', () {
    test('parses camera fixture JSON correctly', () {
      // Test the parsing logic directly with fixture data
      final json = jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()) as List;
      final cameras = json.map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>)).toList();

      expect(cameras, hasLength(3));
      expect(cameras[0].id, 'cam-001');
      expect(cameras[0].name, 'Nursery');
      expect(cameras[0].isConnected, true);
      expect(cameras[0].isMicEnabled, true);
      expect(cameras[2].isConnected, false);
    });

    test('client can be created and configured', () {
      final client = ProtectApiClient();
      client.setApiKey('test-key');
      // No exception means success — actual HTTP calls tested via integration
    });
  });

  group('ProtectApiClient test seams', () {
    // Regression: _dio was `late final` and assigned in the constructor, so
    // this threw LateInitializationError every time. The client's only
    // injection point was dead, which is why nothing below could exist.
    test('setDioForTest installs the replacement Dio without throwing', () {
      final client = ProtectApiClient();
      expect(() => client.setDioForTest(Dio()), returnsNormally);
    });

    test('setDioForTest actually routes requests through the replacement', () async {
      final adapter = _ScriptedAdapter([(200, <dynamic>[])]);
      final replacement = Dio()..httpClientAdapter = adapter;
      final client = ProtectApiClient()..setApiKey('k');
      client.setDioForTest(replacement);

      await client.verifyConnection('10.0.0.1');
      expect(adapter.requests, hasLength(1));
    });
  });

  group('ProtectApiClient.verifyConnection', () {
    test('true on 200', () async {
      final client = _client(_ScriptedAdapter([(200, <dynamic>[])]));
      expect(await client.verifyConnection('10.0.0.1'), true);
    });

    test('false on a non-200 that is still below 500', () async {
      // validateStatus allows <500 through, so a 404 is a `false`, not a throw.
      final client = _client(_ScriptedAdapter([(404, null)]));
      expect(await client.verifyConnection('10.0.0.1'), false);
    });

    test('targets the integration v1 cameras endpoint with the API key header',
        () async {
      final adapter = _ScriptedAdapter([(200, <dynamic>[])]);
      await _client(adapter).verifyConnection('10.0.0.1');

      final req = adapter.requests.single;
      expect(req.uri.toString(),
          'https://10.0.0.1/proxy/protect/integration/v1/cameras');
      expect(req.headers['X-API-Key'], 'test-key');
    });
  });

  group('ProtectApiClient error mapping', () {
    // A wrong error type is not cosmetic: AuthNotifier only falls back to the
    // remote host on connectionRefused/timeout, and only revokes cached
    // credentials on invalidCredentials.
    Future<AppError> errorFor(Object reply) async {
      final client = _client(_ScriptedAdapter([reply]));
      try {
        await client.getCameras('10.0.0.1');
      } on AppError catch (e) {
        return e;
      }
      fail('expected getCameras to throw an AppError for $reply');
    }

    test('401 maps to invalidCredentials', () async {
      expect((await errorFor((401, null))).type, AppErrorType.invalidCredentials);
    });

    test('403 maps to invalidCredentials', () async {
      expect((await errorFor((403, null))).type, AppErrorType.invalidCredentials);
    });

    test('connectionError maps to connectionRefused', () async {
      expect(
        (await errorFor(DioExceptionType.connectionError)).type,
        AppErrorType.connectionRefused,
      );
    });

    test('connectionTimeout maps to connectionRefused', () async {
      // Grouped with connectionError deliberately: both mean "wrong address",
      // which is the class of failure that justifies trying the remote host.
      expect(
        (await errorFor(DioExceptionType.connectionTimeout)).type,
        AppErrorType.connectionRefused,
      );
    });

    test('receiveTimeout maps to timeout', () async {
      expect(
        (await errorFor(DioExceptionType.receiveTimeout)).type,
        AppErrorType.timeout,
      );
    });

    test('sendTimeout maps to timeout', () async {
      expect(
        (await errorFor(DioExceptionType.sendTimeout)).type,
        AppErrorType.timeout,
      );
    });

    test('an unrecognised failure maps to unknown rather than escaping', () async {
      expect(
        (await errorFor(DioExceptionType.badCertificate)).type,
        AppErrorType.unknown,
      );
    });
  });

  group('ProtectApiClient.getCameras', () {
    test('maps the response list into ProtectCamera models', () async {
      final client = _client(_ScriptedAdapter([
        (
          200,
          [
            {'id': 'c1', 'name': 'Nursery', 'state': 'CONNECTED'},
            {'id': 'c2', 'name': 'Garage', 'state': 'DISCONNECTED'},
          ]
        )
      ]));

      final cameras = await client.getCameras('10.0.0.1');
      expect(cameras.map((c) => c.id), ['c1', 'c2']);
      expect(cameras[0].isConnected, true);
      expect(cameras[1].isConnected, false);
    });

    test('an empty list is not an error', () async {
      final client = _client(_ScriptedAdapter([(200, <dynamic>[])]));
      expect(await client.getCameras('10.0.0.1'), isEmpty);
    });
  });

  group('ProtectApiClient.getRtspsUrls', () {
    test('extracts the low/medium/high aliases', () async {
      final client = _client(_ScriptedAdapter([
        (
          200,
          {
            'low': 'rtsps://10.0.0.1:7441/lowAlias?enableSrtp',
            'medium': 'rtsps://10.0.0.1:7441/medAlias?enableSrtp',
            'high': 'rtsps://10.0.0.1:7441/highAlias?enableSrtp',
          }
        )
      ]));

      final urls = await client.getRtspsUrls('10.0.0.1', 'cam-1');
      expect(urls.keys, containsAll(['low', 'medium', 'high']));
      expect(urls['low'], 'rtsps://10.0.0.1:7441/lowAlias?enableSrtp');
    });

    test('omits qualities the console did not return', () async {
      final client = _client(_ScriptedAdapter([
        (200, {'low': 'rtsps://h/l'})
      ]));

      final urls = await client.getRtspsUrls('10.0.0.1', 'cam-1');
      expect(urls, {'low': 'rtsps://h/l'});
    });

    test('ignores unexpected keys instead of leaking them as qualities',
        () async {
      final client = _client(_ScriptedAdapter([
        (200, {'low': 'rtsps://h/l', 'ultra': 'rtsps://h/u'})
      ]));

      expect(await client.getRtspsUrls('10.0.0.1', 'cam-1'), {'low': 'rtsps://h/l'});
    });

    test('returns empty on failure instead of throwing', () async {
      // Per CLAUDE.md this must degrade rather than propagate: a failed
      // quality lookup must not take down a stream that is already playing.
      final client = _client(_ScriptedAdapter([DioExceptionType.connectionError]));
      expect(await client.getRtspsUrls('10.0.0.1', 'cam-1'), isEmpty);
    });

    test('targets the per-camera rtsps-stream endpoint', () async {
      final adapter = _ScriptedAdapter([
        (200, {'low': 'rtsps://h/l'})
      ]);
      await _client(adapter).getRtspsUrls('10.0.0.1', 'cam-1');

      expect(
        adapter.requests.single.uri.toString(),
        'https://10.0.0.1/proxy/protect/integration/v1/cameras/cam-1/rtsps-stream',
      );
    });
  });

  group('ProtectApiClient 429 retry interceptor', () {
    test('retries a 429 and resolves with the retried response', () async {
      final adapter = _ScriptedAdapter([
        (429, null),
        (200, <dynamic>[]),
      ]);
      final client = _client(adapter);

      expect(await client.getCameras('10.0.0.1'), isEmpty);
      expect(adapter.requests, hasLength(2),
          reason: 'the 429 must be followed by exactly one retry');
    });

    test('gives up after 3 retries and surfaces an AppError', () async {
      final adapter = _ScriptedAdapter([
        (429, null),
        (429, null),
        (429, null),
        (429, null),
      ]);
      final client = _client(adapter);

      await expectLater(
        client.getCameras('10.0.0.1'),
        throwsA(isA<AppError>()),
      );
      // Original attempt + 3 retries, then it stops rather than looping.
      expect(adapter.requests, hasLength(4));
    });
  });
}
