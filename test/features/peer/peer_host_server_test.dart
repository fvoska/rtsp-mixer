import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/helpers/peer_urls.dart';
import 'package:rtsp_mixer/features/peer/models/battery_status.dart';
import 'package:rtsp_mixer/features/peer/peer_protocol.dart';
import 'package:rtsp_mixer/features/peer/services/pairing_code.dart';
import 'package:rtsp_mixer/features/peer/services/peer_host_server.dart';

import '../../support/async.dart';

/// Loopback harness around [PeerHostServer] with an injectable PCM source.
class _Harness {
  _Harness({PairingGate? gate}) {
    server = PeerHostServer(
      hostId: 'host-1',
      hostName: () => 'Nursery phone',
      pairingCode: () => code,
      isTokenValid: (t) => validTokens.contains(t),
      issueToken: (id, name) async {
        issued.add((id: id, name: name));
        final t = 'tok-${issued.length}';
        validTokens.add(t);
        return t;
      },
      audio: audio.stream,
      currentLevel: () => 0.42,
      currentLevelDb: () => -18.5,
      currentBattery: () => battery,
      onListenersChanged: (n) => listenerCounts.add(n),
      gate: gate,
    );
  }

  /// The pairing code the fake host expects.
  final String code = '123456';
  final audio = StreamController<Uint8List>.broadcast();
  final validTokens = <String>{'good'};

  /// What the fake host reports as its battery; null omits the field.
  BatteryStatus? battery = const BatteryStatus(percent: 73, plugged: true);
  final issued = <({String id, String name})>[];
  final listenerCounts = <int>[];
  late final PeerHostServer server;
  late int port;

  Future<void> start() async {
    port = await server.start(
        bindAddress: InternetAddress.loopbackIPv4, preferredPort: 0);
  }

  Future<void> stop() async {
    await server.stop();
    await audio.close();
  }

  Future<HttpClientResponse> get(String path, {String? token}) async {
    final client = HttpClient();
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: path,
      queryParameters: token == null ? null : {'token': token},
    );
    final req = await client.getUrl(uri);
    return req.close();
  }

  Future<(int, Map<String, dynamic>)> post(
      String path, Map<String, Object?> body) async {
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    client.close(force: true);
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }
}

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.start();
  });

  tearDown(() => h.stop());

  test('info is unauthenticated and identifies the host', () async {
    final res = await h.get(kPeerInfoPath);
    expect(res.statusCode, 200);
    final json = jsonDecode(await utf8.decoder.bind(res).join());
    expect(json['app'], 'roomtone');
    expect(json['hostId'], 'host-1');
    expect(json['name'], 'Nursery phone');
    expect(json['protocol'], kPeerProtocolVersion);
  });

  test('unknown path is 404, wrong method is 405', () async {
    expect((await h.get('/nope')).statusCode, 404);
    expect((await h.get(kPeerPairPath)).statusCode, 405);
  });

  test('pair rejects a wrong code and accepts the right one', () async {
    final (badStatus, bad) =
        await h.post(kPeerPairPath, {'code': '000000', 'clientId': 'c1'});
    expect(badStatus, 403);
    expect(bad['error'], 'wrong_code');
    expect(h.issued, isEmpty);

    final (okStatus, ok) = await h.post(kPeerPairPath,
        {'code': '123 456', 'clientId': 'c1', 'clientName': 'Pixel'});
    expect(okStatus, 200);
    expect(ok['token'], 'tok-1');
    expect(ok['hostId'], 'host-1');
    expect(ok['streamPath'], kPeerAudioPath);
    expect(h.issued.single.name, 'Pixel');
  });

  test('pair validates input and protocol', () async {
    expect((await h.post(kPeerPairPath, {'code': '123456'})).$1, 400);
    expect(
        (await h.post(kPeerPairPath,
                {'code': '123456', 'clientId': 'c', 'protocol': 99}))
            .$1,
        409);
  });

  test('pairing locks after repeated wrong codes', () async {
    await h.stop();
    h = _Harness(gate: PairingGate(maxFailures: 2));
    await h.start();
    await h.post(kPeerPairPath, {'code': '1', 'clientId': 'c'});
    final (lockedNow, body) =
        await h.post(kPeerPairPath, {'code': '1', 'clientId': 'c'});
    expect(lockedNow, 403);
    expect(body['retryAfterSeconds'], greaterThan(0));
    // Even the RIGHT code is refused while locked.
    final (status, locked) =
        await h.post(kPeerPairPath, {'code': '123456', 'clientId': 'c'});
    expect(status, 429);
    expect(locked['error'], 'locked');
  });

  test('status and audio require a valid token', () async {
    expect((await h.get(kPeerStatusPath)).statusCode, 401);
    expect((await h.get(kPeerStatusPath, token: 'bad')).statusCode, 401);
    expect((await h.get(kPeerAudioPath, token: 'bad')).statusCode, 401);
    final res = await h.get(kPeerStatusPath, token: 'good');
    expect(res.statusCode, 200);
    final json = jsonDecode(await utf8.decoder.bind(res).join());
    expect(json['level'], 0.42);
    expect(json['levelDb'], -18.5);
    expect(json['listeners'], 0);
    expect(json['battery'], {'percent': 73, 'plugged': true});
  });

  test('status omits the battery when the host has no reading', () async {
    h.battery = null;
    final res = await h.get(kPeerStatusPath, token: 'good');
    expect(res.statusCode, 200);
    final json = jsonDecode(await utf8.decoder.bind(res).join());
    expect(json.containsKey('battery'), isFalse);
    expect(json['level'], 0.42);
  });

  test('audio streams a WAV header followed by live PCM, and tracks listeners',
      () async {
    final client = HttpClient();
    final req = await client.getUrl(
        Uri.parse(peerStreamUrl('127.0.0.1', h.port, 'good')));
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'audio/wav');

    final received = BytesBuilder();
    final done = Completer<void>();
    final sub = res.listen(received.add,
        onDone: () => done.complete(), onError: (_) => done.complete());

    await waitFor(() => h.server.listenerCount == 1,
        reason: 'server registers the audio listener');
    // Feed a chunk after the client is attached.
    final chunk = Uint8List.fromList(List.generate(320, (i) => i % 256));
    h.audio.add(chunk);
    await waitFor(() => received.length >= 44 + 320,
        reason: 'client receives header + one chunk');
    final bytes = received.toBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    expect(bytes.sublist(44, 44 + 320), chunk);

    // Client hangs up → the next writes fail and the listener is dropped.
    // (Disconnects are detected on write, which is fine in production where
    // the microphone feeds ~50 chunks/s.)
    await sub.cancel();
    client.close(force: true);
    final feeder = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!h.audio.isClosed) h.audio.add(chunk);
    });
    addTearDown(feeder.cancel);
    await waitFor(() => h.server.listenerCount == 0,
        reason: 'server drops the disconnected listener');
    feeder.cancel();
    expect(h.listenerCounts, containsAllInOrder([1, 0]));
  });

  test('two connections from one monitor count as one listener', () async {
    final clients = <HttpClient>[];
    for (var i = 0; i < 2; i++) {
      final client = HttpClient();
      clients.add(client);
      final req = await client.getUrl(
          Uri.parse(peerStreamUrl('127.0.0.1', h.port, 'good')));
      final res = await req.close();
      res.listen((_) {}, onError: (_) {});
    }
    await waitFor(() => h.server.connectionCount == 2,
        reason: 'both audio connections attach');
    expect(h.server.listenerCount, 1);
    for (final c in clients) {
      c.close(force: true);
    }
  });

  test('stop closes open listeners', () async {
    final client = HttpClient();
    final req = await client.getUrl(
        Uri.parse(peerStreamUrl('127.0.0.1', h.port, 'good')));
    final res = await req.close();
    final ended = Completer<void>();
    void finish([Object? _]) {
      if (!ended.isCompleted) ended.complete();
    }
    res.listen((_) {}, onDone: finish, onError: finish);
    await waitFor(() => h.server.listenerCount == 1, reason: 'listener attached');
    await h.server.stop();
    await ended.future.timeout(const Duration(seconds: 5));
    expect(h.server.listenerCount, 0);
    expect(h.server.isRunning, isFalse);
    client.close(force: true);
  });
}
