import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';
import '../peer_protocol.dart';
import 'pairing_code.dart';
import 'wav_stream.dart';

/// HTTP server run by the host phone. Pure `dart:io`, no plugins, so it is
/// exercised end-to-end on the loopback interface in `flutter test`.
///
/// Endpoints (all under [kPeerApiPrefix]):
///  - `GET  /info`              identity, unauthenticated
///  - `POST /pair`              `{code, clientId, clientName}` → `{token,…}`
///  - `GET  /status?token=`     `{level, listeners, uptimeSeconds}`
///  - `GET  /audio.wav?token=`  endless PCM16 WAV
///
/// Defensive by contract (CLAUDE.md): a bad request, a slow or vanished
/// client, or a failing callback is logged and that one connection is
/// dropped. The server itself, and every other listener's stream, keep going.
class PeerHostServer {
  PeerHostServer({
    required this.hostId,
    required this.hostName,
    required this.pairingCode,
    required this.isTokenValid,
    required this.issueToken,
    required this.audio,
    required this.currentLevel,
    this.onListenersChanged,
    this.onPairingAttempt,
    PairingGate? gate,
    Duration? maxBacklog,
  })  : gate = gate ?? PairingGate(),
        maxBacklogBytes =
            (maxBacklog ?? const Duration(seconds: 5)).inMilliseconds *
                kPeerBytesPerSecond ~/
                1000;

  final String hostId;
  final String Function() hostName;
  final String Function() pairingCode;
  final bool Function(String token) isTokenValid;

  /// Called on a correct code; returns the bearer token to hand out. The
  /// owner persists the hash and rotates the pairing code.
  final Future<String> Function(String clientId, String clientName) issueToken;

  /// Broadcast stream of PCM16 chunks in the [kPeerSampleRate] format.
  final Stream<Uint8List> audio;
  final double Function() currentLevel;
  final void Function(int listeners)? onListenersChanged;

  /// `(success, remoteAddress)` — lets the host UI show "wrong code from
  /// 192.168.1.30" without the server knowing about UI.
  final void Function(bool success, String remote)? onPairingAttempt;
  final PairingGate gate;

  /// Bytes a listener may fall behind before it is dropped so it reconnects
  /// at the live edge — a baby monitor prefers a gap to growing delay.
  final int maxBacklogBytes;

  HttpServer? _server;
  final Set<_AudioListener> _listeners = {};
  DateTime? _startedAt;

  int? get port => _server?.port;
  bool get isRunning => _server != null;
  int get listenerCount => _listeners.length;
  DateTime? get startedAt => _startedAt;

  /// Bind on [bindAddress] (default: all IPv4) trying [preferredPort] first
  /// and an ephemeral port second. Throws only when even that fails.
  Future<int> start({
    InternetAddress? bindAddress,
    int preferredPort = kPeerPreferredHttpPort,
  }) async {
    if (_server != null) return _server!.port;
    final address = bindAddress ?? InternetAddress.anyIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(address, preferredPort, shared: false);
    } catch (e) {
      appLog('PEER_HOST',
          'Port $preferredPort unavailable ($e) — using an ephemeral port');
      server = await HttpServer.bind(address, 0);
    }
    // Never buffer: a live stream must hit the socket as soon as we have it.
    server.autoCompress = false;
    server.idleTimeout = const Duration(minutes: 5);
    _server = server;
    _startedAt = DateTime.now();
    server.listen(_dispatch, onError: (Object e) {
      appLog('PEER_HOST', 'server error (non-fatal): $e');
    });
    appLog('PEER_HOST', 'Serving on ${address.address}:${server.port}');
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _startedAt = null;
    for (final l in _listeners.toList()) {
      l.close('server stopping');
    }
    _listeners.clear();
    _notifyListeners();
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (e) {
        appLog('PEER_HOST', 'close threw (ignored): $e');
      }
    }
    appLog('PEER_HOST', 'Stopped');
  }

  void _notifyListeners() {
    try {
      onListenersChanged?.call(_listeners.length);
    } catch (e) {
      appLog('PEER_HOST', 'onListenersChanged threw (ignored): $e');
    }
  }

  Future<void> _dispatch(HttpRequest req) async {
    try {
      final path = req.uri.path;
      final method = req.method;
      if (path == kPeerInfoPath && method == 'GET') {
        return _json(req, 200, _infoBody());
      }
      if (path == kPeerPairPath) {
        if (method != 'POST') return _json(req, 405, {'error': 'method'});
        return _handlePair(req);
      }
      if (path == kPeerStatusPath || path == kPeerAudioPath) {
        if (method != 'GET') return _json(req, 405, {'error': 'method'});
        final token = req.uri.queryParameters[kPeerTokenParam];
        if (token == null || token.isEmpty || !_tokenOk(token)) {
          return _json(req, 401, {'error': 'unauthorized'});
        }
        if (path == kPeerStatusPath) return _json(req, 200, _statusBody());
        return _serveAudio(req);
      }
      return _json(req, 404, {'error': 'not_found'});
    } catch (e, st) {
      appLog('PEER_HOST', 'request ${req.uri.path} failed: $e\n$st');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  bool _tokenOk(String token) {
    try {
      return isTokenValid(token);
    } catch (e) {
      appLog('PEER_HOST', 'isTokenValid threw (treated as invalid): $e');
      return false;
    }
  }

  Map<String, Object?> _infoBody() => {
        'app': kDiscoveryAppTag,
        'protocol': kPeerProtocolVersion,
        'hostId': hostId,
        'name': hostName(),
        'pairing': true,
        'sampleRate': kPeerSampleRate,
        'channels': kPeerChannels,
      };

  Map<String, Object?> _statusBody() {
    double level;
    try {
      level = currentLevel();
      if (!level.isFinite) level = 0.0;
    } catch (_) {
      level = 0.0;
    }
    final started = _startedAt;
    return {
      'level': level.clamp(0.0, 1.0),
      'listeners': _listeners.length,
      'uptimeSeconds':
          started == null ? 0 : DateTime.now().difference(started).inSeconds,
      'name': hostName(),
      'hostId': hostId,
    };
  }

  Future<void> _handlePair(HttpRequest req) async {
    final remote = _remoteOf(req);
    final retry = gate.retryAfterSeconds();
    if (retry > 0) {
      appLog('PEER_HOST', 'pair from $remote refused — locked for ${retry}s');
      return _json(req, 429, {'error': 'locked', 'retryAfterSeconds': retry});
    }
    Map<String, dynamic> body;
    try {
      final raw = await _readBody(req, maxBytes: 4096);
      final decoded = jsonDecode(raw);
      body = decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return _json(req, 400, {'error': 'bad_json'});
    }
    final code = normalizePairingCode(body['code']?.toString() ?? '');
    final clientId = (body['clientId']?.toString() ?? '').trim();
    final clientName = (body['clientName']?.toString() ?? '').trim();
    final protocol = body['protocol'];
    if (protocol is int && protocol != kPeerProtocolVersion) {
      return _json(req, 409,
          {'error': 'incompatible', 'protocol': kPeerProtocolVersion});
    }
    if (code.isEmpty || clientId.isEmpty) {
      return _json(req, 400, {'error': 'missing_fields'});
    }
    final expected = pairingCode();
    if (!constantTimeEquals(code, expected)) {
      final locked = gate.recordFailure();
      appLog('PEER_HOST',
          'wrong pairing code from $remote${locked ? " — pairing locked" : ""}');
      _reportAttempt(false, remote);
      return _json(req, 403, {
        'error': 'wrong_code',
        if (locked) 'retryAfterSeconds': gate.retryAfterSeconds(),
      });
    }
    gate.recordSuccess();
    final token = await issueToken(
        clientId, clientName.isEmpty ? 'Monitor ($remote)' : clientName);
    appLog('PEER_HOST', 'paired "$clientName" from $remote');
    _reportAttempt(true, remote);
    return _json(req, 200, {
      'token': token,
      'hostId': hostId,
      'name': hostName(),
      'protocol': kPeerProtocolVersion,
      'streamPath': kPeerAudioPath,
      'statusPath': kPeerStatusPath,
    });
  }

  void _reportAttempt(bool ok, String remote) {
    try {
      onPairingAttempt?.call(ok, remote);
    } catch (e) {
      appLog('PEER_HOST', 'onPairingAttempt threw (ignored): $e');
    }
  }

  /// Stream audio over the request's raw socket.
  ///
  /// Why not `HttpResponse.add`: dart:io defers socket write errors until
  /// `close()`, so a monitor that vanished mid-stream would never be noticed
  /// and the listener would leak until the host stopped. A detached socket
  /// reports the peer's FIN through its read stream and a broken pipe through
  /// `done` within a couple of writes. Framing is HTTP/1.1 identity with
  /// `Connection: close`, which FFmpeg's HTTP reader handles as a live source.
  Future<void> _serveAudio(HttpRequest req) async {
    final res = req.response;
    final remote = _remoteOf(req);
    Socket socket;
    try {
      res.statusCode = 200;
      res.headers.contentType = ContentType('audio', 'wav');
      res.headers.set('Cache-Control', 'no-store');
      res.headers.set('Accept-Ranges', 'none');
      res.headers.set('X-Roomtone-Host', hostId);
      res.headers.chunkedTransferEncoding = false;
      res.persistentConnection = false;
      socket = await res.detachSocket(writeHeaders: true);
    } catch (e) {
      appLog('PEER_HOST', 'audio handshake with $remote failed: $e');
      return;
    }
    final listener = _AudioListener(
      socket,
      remote: remote,
      maxBacklogBytes: maxBacklogBytes,
      onClosed: (l) {
        if (_listeners.remove(l)) _notifyListeners();
      },
    );
    _listeners.add(listener);
    _notifyListeners();
    appLog('PEER_HOST', 'listener connected from $remote (${_listeners.length})');
    try {
      socket.add(wavStreamHeader());
    } catch (e) {
      listener.close('header write failed: $e');
      return;
    }
    listener.attach(audio);
  }

  static String _remoteOf(HttpRequest req) {
    try {
      final info = req.connectionInfo;
      return info == null ? '?' : info.remoteAddress.address;
    } catch (_) {
      return '?';
    }
  }

  static Future<String> _readBody(HttpRequest req, {required int maxBytes}) async {
    final buf = BytesBuilder(copy: false);
    await for (final chunk in req) {
      buf.add(chunk);
      if (buf.length > maxBytes) throw const FormatException('body too large');
    }
    return utf8.decode(buf.takeBytes());
  }

  static Future<void> _json(
      HttpRequest req, int status, Map<String, Object?> body) async {
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set('Cache-Control', 'no-store');
    res.write(jsonEncode(body));
    await res.close();
  }
}

/// One connected audio consumer. Owns its subscription to the PCM broadcast
/// and the backlog accounting that drops a client that can't keep up.
class _AudioListener {
  _AudioListener(
    this.socket, {
    required this.remote,
    required this.maxBacklogBytes,
    required this.onClosed,
  }) {
    // Peer FIN / RST → the read side ends; broken pipe → `done` errors.
    socket.listen(
      (_) {},
      onDone: () => close('client disconnected'),
      onError: (Object e) => close('socket error: $e'),
      cancelOnError: true,
    );
    unawaited(socket.done.then((_) {}, onError: (Object e) {
      close('write failed: $e');
    }));
  }

  final Socket socket;
  final String remote;
  final int maxBacklogBytes;
  final void Function(_AudioListener) onClosed;

  StreamSubscription<Uint8List>? _sub;
  Future<void>? _flush;
  int _pending = 0;
  bool _closed = false;

  void attach(Stream<Uint8List> audio) {
    if (_closed) return;
    _sub = audio.listen(
      _onChunk,
      onError: (Object e) => close('audio source error: $e'),
      onDone: () => close('audio source ended'),
      cancelOnError: true,
    );
  }

  void _onChunk(Uint8List chunk) {
    if (_closed) return;
    _pending += chunk.length;
    if (_pending > maxBacklogBytes) {
      close('too slow (${_pending}B behind)');
      return;
    }
    try {
      socket.add(chunk);
      _flush ??= socket.flush().then((_) {
        _pending = 0;
        _flush = null;
      }, onError: (Object e) {
        _flush = null;
        close('flush failed: $e');
      });
    } catch (e) {
      close('write threw: $e');
    }
  }

  void close(String reason) {
    if (_closed) return;
    _closed = true;
    appLog('PEER_HOST', 'listener $remote closed: $reason');
    try {
      unawaited(_sub?.cancel());
    } catch (_) {}
    _sub = null;
    try {
      // destroy() drops both directions at once — a live stream has nothing
      // worth flushing to a listener that is going away.
      socket.destroy();
    } catch (_) {}
    onClosed(this);
  }
}
