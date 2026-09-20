import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/services/storage_service.dart';
import 'package:rtsp_mixer/core/services/update_checker.dart';

import '../../support/logging.dart';

/// A [HttpClientAdapter] that returns scripted responses.
///
/// Copied from `test/core/api/protect_api_client_test.dart` and used with
/// [UpdateChecker.setHttpClientAdapterForTest] so the checker's own Dio —
/// its BaseOptions, headers and `validateStatus` — stays in the path.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.replies);

  /// Each entry is either a `(statusCode, body)` pair (JSON-encoded), a
  /// [_RawReply] (body sent verbatim, for malformed-payload tests), or a
  /// [DioExceptionType] to throw (transport-level failures).
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
    final reply = replies[_next < replies.length ? _next++ : replies.length - 1];
    if (reply is DioExceptionType) {
      throw DioException(requestOptions: options, type: reply);
    }
    if (reply is _RawReply) {
      return ResponseBody.fromString(
        reply.body,
        reply.status,
        headers: {
          Headers.contentTypeHeader: [reply.contentType],
        },
      );
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

/// A response whose body is sent exactly as written — used to script the
/// "GitHub returned something that is not the JSON we expect" cases.
class _RawReply {
  const _RawReply(
    this.status,
    this.body, {
    this.contentType = Headers.jsonContentType,
  });

  final int status;
  final String body;
  final String contentType;
}

UpdateChecker _checker(_ScriptedAdapter adapter) =>
    UpdateChecker()..setHttpClientAdapterForTest(adapter);

/// A well-formed GitHub `/releases/latest` payload.
Map<String, dynamic> _release({
  String tag = 'v1.15.0',
  String htmlUrl = 'https://github.com/fvoska/rtsp-mixer/releases/tag/v1.15.0',
  List<Map<String, dynamic>>? assets,
  bool draft = false,
  bool prerelease = false,
}) =>
    {
      'tag_name': tag,
      'html_url': htmlUrl,
      'draft': draft,
      'prerelease': prerelease,
      'assets': assets ??
          [
            {
              'name': 'rtsp-mixer-1.15.0-android.apk',
              'browser_download_url':
                  'https://github.com/fvoska/rtsp-mixer/releases/download/v1.15.0/rtsp-mixer-1.15.0-android.apk',
            },
          ],
    };

void main() {
  installAppLoggerTestIsolation();

  group('isNewerVersion', () {
    test('a higher minor is newer', () {
      expect(isNewerVersion('v1.15.0', '1.14.0'), isTrue);
    });

    test('a higher patch is newer', () {
      expect(isNewerVersion('1.14.1', '1.14.0'), isTrue);
    });

    test('a higher major is newer', () {
      expect(isNewerVersion('v2.0.0', '1.14.0'), isTrue);
    });

    test('the same version is not newer', () {
      expect(isNewerVersion('v1.14.0', '1.14.0'), isFalse);
    });

    test('an older version is not newer', () {
      expect(isNewerVersion('v1.13.9', '1.14.0'), isFalse);
    });

    test('missing components pad with zero rather than counting as newer', () {
      expect(isNewerVersion('v1.14', '1.14.0'), isFalse);
    });

    test('build metadata after + is ignored', () {
      // The running build reports `1.14.0` with a separate build number, and
      // the tag may carry one too — neither may influence the comparison.
      expect(isNewerVersion('v1.15.0+3', '1.14.0+22'), isTrue);
      expect(isNewerVersion('v1.14.0+99', '1.14.0+22'), isFalse);
    });

    test('a pre-release suffix after - is ignored for the numeric compare', () {
      expect(isNewerVersion('v1.15.0-rc.1', '1.14.0'), isTrue);
    });

    test('unparseable input on either side never produces a banner', () {
      for (final tag in ['latest', '', 'v', '1.x.0', '  ', 'nightly']) {
        expect(isNewerVersion(tag, '1.14.0'), isFalse,
            reason: 'tag "$tag" must not be treated as newer');
      }
      for (final current in ['latest', '', 'v', '1.x.0']) {
        expect(isNewerVersion('v99.0.0', current), isFalse,
            reason: 'current "$current" must not be compared against');
      }
    });
  });

  group('AppUpdate.fromJson', () {
    test('strips the leading v from the tag and keeps html_url', () {
      final update = AppUpdate.fromJson(_release())!;
      expect(update.version, '1.15.0');
      expect(update.releaseUrl,
          'https://github.com/fvoska/rtsp-mixer/releases/tag/v1.15.0');
    });

    test('picks the first asset whose name ends in .apk', () {
      final update = AppUpdate.fromJson(_release(assets: [
        {
          'name': 'roomtone-1.15.0.aab',
          'browser_download_url': 'https://example.com/a.aab',
        },
        {
          'name': 'rtsp-mixer-1.15.0-android.apk',
          'browser_download_url': 'https://example.com/a.apk',
        },
        {
          'name': 'other-1.15.0.apk',
          'browser_download_url': 'https://example.com/b.apk',
        },
      ]))!;
      expect(update.apkUrl, 'https://example.com/a.apk');
    });

    test('no apk asset leaves apkUrl null', () {
      final update = AppUpdate.fromJson(_release(assets: []))!;
      expect(update.apkUrl, isNull);
    });

    test('a malformed asset entry does not break the parse', () {
      final update = AppUpdate.fromJson(_release(assets: [
        {'name': 42, 'browser_download_url': 'https://example.com/x.apk'},
        {'name': 'good.apk', 'browser_download_url': 7},
        {
          'name': 'real.apk',
          'browser_download_url': 'https://example.com/real.apk',
        },
      ]))!;
      expect(update.apkUrl, 'https://example.com/real.apk');
    });

    test('a draft release is rejected', () {
      expect(AppUpdate.fromJson(_release(draft: true)), isNull);
    });

    test('a pre-release is rejected', () {
      expect(AppUpdate.fromJson(_release(prerelease: true)), isNull);
    });

    test('a missing or wrong-typed tag_name returns null, never throws', () {
      expect(AppUpdate.fromJson({'html_url': 'https://example.com'}), isNull);
      expect(
        AppUpdate.fromJson({'tag_name': 5, 'html_url': 'https://example.com'}),
        isNull,
      );
      expect(
        AppUpdate.fromJson({'tag_name': '  ', 'html_url': 'https://x.com'}),
        isNull,
      );
    });

    test('a missing or wrong-typed html_url returns null, never throws', () {
      expect(AppUpdate.fromJson({'tag_name': 'v1.15.0'}), isNull);
      expect(AppUpdate.fromJson({'tag_name': 'v1.15.0', 'html_url': []}), isNull);
    });

    test('a wrong-typed assets field degrades to no apk rather than throwing', () {
      final json = _release()..['assets'] = 'not-a-list';
      final update = AppUpdate.fromJson(json);
      expect(update, isNotNull);
      expect(update!.apkUrl, isNull);
    });
  });

  group('AppUpdate.downloadUrl', () {
    test('off Android it is the human-readable release page', () {
      // The suite never runs on Android; on every host platform the parent
      // should land on the release page, not on a raw APK download.
      expect(Platform.isAndroid, isFalse,
          reason: 'this expectation encodes the non-Android branch');
      final update = AppUpdate.fromJson(_release())!;
      expect(update.downloadUrl, update.releaseUrl);
    });

    test('falls back to the release page when there is no apk asset', () {
      final update = AppUpdate.fromJson(_release(assets: []))!;
      expect(update.downloadUrl, update.releaseUrl);
    });
  });

  group('UpdateChecker.fetchLatestRelease', () {
    test('a well-formed 200 yields the parsed update', () async {
      final update =
          await _checker(_ScriptedAdapter([(200, _release())])).fetchLatestRelease();

      expect(update, isNotNull);
      expect(update!.version, '1.15.0');
      expect(update.apkUrl, endsWith('rtsp-mixer-1.15.0-android.apk'));
    });

    test('targets the public fvoska/rtsp-mixer latest-release endpoint', () async {
      final adapter = _ScriptedAdapter([(200, _release())]);
      await _checker(adapter).fetchLatestRelease();

      final req = adapter.requests.single;
      expect(req.uri.toString(),
          'https://api.github.com/repos/fvoska/rtsp-mixer/releases/latest');
      expect(req.method, 'GET');
      expect(req.headers['Accept'], 'application/vnd.github+json');
      expect(req.headers['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('sends no Authorization header — the endpoint is public', () async {
      final adapter = _ScriptedAdapter([(200, _release())]);
      await _checker(adapter).fetchLatestRelease();

      final headers = adapter.requests.single.headers;
      final keys = headers.keys.map((k) => k.toLowerCase()).toList();
      expect(keys, isNot(contains('authorization')));
    });

    test('403 (rate limited) yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([(403, null)])).fetchLatestRelease(),
        isNull,
      );
    });

    test('404 yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([(404, null)])).fetchLatestRelease(),
        isNull,
      );
    });

    test('500 yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([(500, null)])).fetchLatestRelease(),
        isNull,
      );
    });

    test('a connection error (offline) yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([DioExceptionType.connectionError]))
            .fetchLatestRelease(),
        isNull,
      );
      expect(
        await _checker(_ScriptedAdapter([DioExceptionType.receiveTimeout]))
            .fetchLatestRelease(),
        isNull,
      );
    });

    test('a non-JSON body yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([const _RawReply(200, '<html>nope</html>')]))
            .fetchLatestRelease(),
        isNull,
      );
      expect(
        await _checker(_ScriptedAdapter([
          const _RawReply(200, 'plain text', contentType: 'text/plain')
        ])).fetchLatestRelease(),
        isNull,
      );
    });

    test('a JSON array body yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([
          (200, [_release()])
        ])).fetchLatestRelease(),
        isNull,
      );
    });

    test('an empty body yields null without throwing', () async {
      expect(
        await _checker(_ScriptedAdapter([(200, null)])).fetchLatestRelease(),
        isNull,
      );
    });
  });

  group('selectUpdate', () {
    AppUpdate update() => AppUpdate.fromJson(_release())!;

    test('a newer, undismissed release is offered', () {
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '1.14.0',
          dismissedVersion: null,
        ),
        isNotNull,
      );
    });

    test('a newer release dismissed at that exact version is suppressed', () {
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '1.14.0',
          dismissedVersion: '1.15.0',
        ),
        isNull,
      );
    });

    test('a dismissal of an OLDER version does not suppress a newer one', () {
      // Dismissal is per-version, not forever.
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '1.14.0',
          dismissedVersion: '1.14.5',
        ),
        isNotNull,
      );
    });

    test('no release at all is no update', () {
      expect(
        selectUpdate(
          latest: null,
          currentVersion: '1.14.0',
          dismissedVersion: null,
        ),
        isNull,
      );
    });

    test('a release that is not newer is no update', () {
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '1.15.0',
          dismissedVersion: null,
        ),
        isNull,
      );
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '2.0.0',
          dismissedVersion: null,
        ),
        isNull,
      );
    });

    test('an unparseable running version never produces an update', () {
      expect(
        selectUpdate(
          latest: update(),
          currentVersion: '',
          dismissedVersion: null,
        ),
        isNull,
      );
    });
  });

  group('rememberDismissedUpdate', () {
    test('writes the version under the dismissed-update key', () async {
      final storage = StorageService.inMemory();
      await rememberDismissedUpdate(storage, '1.15.0');
      expect(await storage.read(kDismissedUpdateVersionKey), '1.15.0');
    });

    test('a storage failure is swallowed rather than escaping', () async {
      // Per CLAUDE.md: a failed write costs the dismissal memory, never the
      // running stream.
      await expectLater(
        rememberDismissedUpdate(_ThrowingStorage(), '1.15.0'),
        completes,
      );
    });
  });

  group('update check under flutter test', () {
    test('the check is disabled so no test ever hits the network', () {
      expect(updateCheckDisabled, isTrue);
    });

    test('updateCheckProvider resolves to null without a request', () async {
      final container = ProviderContainer(overrides: [
        updateCheckerProvider.overrideWithValue(_ExplodingChecker()),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(updateCheckProvider.future), isNull);
    });
  });
}

/// Storage whose writes always blow up, standing in for a keystore that is
/// unavailable or full.
class _ThrowingStorage extends StorageService {
  _ThrowingStorage() : super.inMemory();

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keystore unavailable');
}

/// Fails loudly if the provider ever reaches the network under `flutter test`.
class _ExplodingChecker extends UpdateChecker {
  @override
  Future<AppUpdate?> fetchLatestRelease() async =>
      fail('the update check must not run under flutter test');
}
