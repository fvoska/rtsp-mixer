import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/services/foreground_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/paired_client.dart';
import '../models/peer_host_state.dart';
import '../peer_protocol.dart';
import '../services/discovery.dart';
import '../services/mic_capture.dart';
import '../services/pairing_code.dart';
import '../services/pcm_level.dart';
import '../services/peer_host_server.dart';

/// Injectable microphone source (tests substitute a fake PCM stream).
final audioCaptureSourceProvider =
    Provider<AudioCaptureSource>((_) => MicrophoneCapture());

/// Knobs that differ between the app and tests (bind loopback, ephemeral
/// ports, no foreground service). Production uses the defaults.
class PeerHostOptions {
  const PeerHostOptions({
    this.bindAddress,
    this.httpPort = kPeerPreferredHttpPort,
    this.discoveryPort = kPeerDiscoveryPort,
    this.useForegroundService = true,
    this.announce = true,
  });

  final InternetAddress? bindAddress;
  final int httpPort;
  final int discoveryPort;
  final bool useForegroundService;
  final bool announce;
}

final peerHostOptionsProvider =
    Provider<PeerHostOptions>((_) => const PeerHostOptions());

final peerHostProvider =
    NotifierProvider<PeerHostNotifier, PeerHostState>(PeerHostNotifier.new);

/// Host mode: this phone is a camera.
///
/// Owns the microphone stream, the HTTP server, the discovery beacon, the
/// paired-device registry and its persistence. Reliability rules mirror the
/// monitor's: a dropped microphone stream is restarted with backoff while
/// the server keeps serving; a failing beacon never stops hosting; nothing
/// throws out of a stream callback.
class PeerHostNotifier extends Notifier<PeerHostState> {
  static const _configKeyHostId = 'hostId';
  static const _configKeyName = 'name';
  static const _configKeyPaired = 'paired';
  static const _configKeyAutoResume = 'autoResume';

  PeerHostServer? _server;
  DiscoveryBeacon? _beacon;
  StreamSubscription<Uint8List>? _micSub;
  StreamController<Uint8List>? _audio;
  Timer? _levelTimer;
  Timer? _micRestartTimer;
  int _micRestartAttempt = 0;
  double _level = 0.0;
  bool _micStarting = false;

  /// Resolves once the persisted config has been read.
  late final Future<void> _loaded;

  /// Captured in build(): onDispose may not touch `ref`, and both providers
  /// are constant for the container's lifetime.
  late final AudioCaptureSource _mic;
  late final PeerHostOptions _options;

  /// Serializes start/stop so a double tap can't interleave them.
  Future<void>? _lifecycleOp;

  @override
  PeerHostState build() {
    _mic = ref.read(audioCaptureSourceProvider);
    _options = ref.read(peerHostOptionsProvider);
    ref.onDispose(() {
      _levelTimer?.cancel();
      _micRestartTimer?.cancel();
      // ignore: unawaited_futures
      _teardown();
    });
    _loaded = _loadConfig();
    return const PeerHostState();
  }

  // ---------------------------------------------------------------- config

  Future<void> _loadConfig() async {
    try {
      final raw = await ref.read(storageProvider).loadPeerHostConfig();
      var hostId = raw?[_configKeyHostId];
      if (hostId is! String || hostId.isEmpty) hostId = generatePeerId();
      final name = raw?[_configKeyName];
      final paired = <PairedClient>[];
      final rawPaired = raw?[_configKeyPaired];
      if (rawPaired is List) {
        for (final entry in rawPaired) {
          final c = PairedClient.tryFromJson(entry);
          if (c != null) paired.add(c);
        }
      }
      final autoResume = raw?[_configKeyAutoResume] == true;
      state = state.copyWith(
        loaded: true,
        hostId: hostId,
        name: name is String && name.trim().isNotEmpty
            ? name.trim()
            : state.name,
        pairedClients: paired,
        autoResume: autoResume,
      );
      appLog('PEER_HOST',
          'Config loaded: id=$hostId paired=${paired.length} autoResume=$autoResume');
      if (raw == null) await _saveConfig();
      if (autoResume) {
        appLog('PEER_HOST', 'Auto-resuming host mode');
        // ignore: unawaited_futures
        start();
      }
    } catch (e) {
      appLog('PEER_HOST', 'Config load failed (using defaults): $e');
      state = state.copyWith(loaded: true, hostId: generatePeerId());
    }
  }

  Future<void> _saveConfig() async {
    try {
      await ref.read(storageProvider).savePeerHostConfig({
        _configKeyHostId: state.hostId,
        _configKeyName: state.name,
        _configKeyPaired: state.pairedClients.map((c) => c.toJson()).toList(),
        _configKeyAutoResume: state.autoResume,
      });
    } catch (e) {
      appLog('PEER_HOST', 'Config save failed (continuing): $e');
    }
  }

  // ------------------------------------------------------------- lifecycle

  Future<void> _runLifecycle(Future<void> Function() op) async {
    final previous = _lifecycleOp;
    final completer = Completer<void>();
    _lifecycleOp = completer.future;
    try {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await op();
    } finally {
      completer.complete();
      if (identical(_lifecycleOp, completer.future)) _lifecycleOp = null;
    }
  }

  /// Start hosting. Safe to call while running (no-op).
  Future<void> start() => _runLifecycle(_startLocked);

  Future<void> _startLocked() async {
    await _loaded;
    if (state.isRunning || state.isBusy) return;
    final options = _options;
    state = state.copyWith(
      status: PeerHostStatus.starting,
      errorMessage: null,
      lastPairingNote: null,
    );
    appLog('PEER_HOST', 'Starting host mode as "${state.name}"');
    try {
      if (!await _mic.hasPermission()) {
        throw StateError(
            'Microphone permission denied — allow it in system settings.');
      }

      final audio = StreamController<Uint8List>.broadcast();
      _audio = audio;

      final server = PeerHostServer(
        hostId: state.hostId,
        hostName: () => state.name,
        pairingCode: () => state.code,
        isTokenValid: _isTokenValid,
        issueToken: _issueToken,
        audio: audio.stream,
        currentLevel: () => _level,
        onListenersChanged: (n) {
          if (n != state.listeners) state = state.copyWith(listeners: n);
        },
        onPairingAttempt: (ok, remote) {
          state = state.copyWith(
            lastPairingNote: ok
                ? 'Paired with a monitor at $remote'
                : 'Wrong code entered from $remote',
          );
        },
      );
      final port = await server.start(
        bindAddress: options.bindAddress,
        preferredPort: options.httpPort,
      );
      _server = server;

      // Discovery is a convenience — a failed bind only logs.
      var discoveryActive = false;
      if (options.announce) {
        final beacon = DiscoveryBeacon(
          hostId: state.hostId,
          hostName: () => state.name,
          httpPort: () => port,
          pairingOpen: () => state.isRunning,
        );
        discoveryActive = await beacon.start(
          bindAddress: options.bindAddress,
          port: options.discoveryPort,
        );
        _beacon = beacon;
      }

      final addresses = options.bindAddress != null &&
              options.bindAddress!.isLoopback
          ? [options.bindAddress!.address]
          : await lanIPv4Addresses();

      state = state.copyWith(
        status: PeerHostStatus.running,
        code: generatePairingCode(),
        port: port,
        addresses: addresses,
        discoveryActive: discoveryActive,
        listeners: 0,
        startedAt: DateTime.now(),
        autoResume: true,
      );
      await _saveConfig();

      _micRestartAttempt = 0;
      await _startMic();
      _levelTimer?.cancel();
      _levelTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        try {
          if (state.isRunning && (state.level - _level).abs() > 0.005) {
            state = state.copyWith(level: _level);
          }
        } catch (_) {}
      });

      if (options.useForegroundService) {
        try {
          await ForegroundServiceManager.startHost(state.name);
        } catch (e) {
          appLog('PEER_HOST', 'Foreground service start failed (continuing): $e');
        }
      }
      appLog('PEER_HOST',
          'Host mode running on ${addresses.join(", ")}:$port (discovery=$discoveryActive)');
    } catch (e) {
      appLog('PEER_HOST', 'Start failed: $e');
      await _teardown();
      state = state.copyWith(
        status: PeerHostStatus.error,
        errorMessage: e.toString().replaceFirst('Bad state: ', ''),
        code: '',
        port: null,
        autoResume: false,
        micActive: false,
      );
      await _saveConfig();
    }
  }

  /// Stop hosting and clear the auto-resume flag.
  Future<void> stop() => _runLifecycle(() async {
        await _loaded;
        appLog('PEER_HOST', 'Stopping host mode');
        await _teardown();
        state = state.copyWith(
          status: PeerHostStatus.idle,
          code: '',
          port: null,
          level: 0,
          listeners: 0,
          autoResume: false,
          discoveryActive: false,
          micActive: false,
          startedAt: null,
          errorMessage: null,
        );
        await _saveConfig();
      });

  Future<void> _teardown() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    _micRestartTimer?.cancel();
    _micRestartTimer = null;
    try {
      await _micSub?.cancel();
    } catch (_) {}
    _micSub = null;
    try {
      await _mic.stop();
    } catch (e) {
      appLog('PEER_HOST', 'mic stop failed (ignored): $e');
    }
    _beacon?.stop();
    _beacon = null;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.stop();
      } catch (e) {
        appLog('PEER_HOST', 'server stop failed (ignored): $e');
      }
    }
    try {
      await _audio?.close();
    } catch (_) {}
    _audio = null;
    _level = 0;
    if (_options.useForegroundService) {
      try {
        await ForegroundServiceManager.stopHost();
      } catch (e) {
        appLog('PEER_HOST', 'FGS stopHost failed (ignored): $e');
      }
    }
  }

  // ------------------------------------------------------------ microphone

  Future<void> _startMic() async {
    if (_micStarting) return;
    _micStarting = true;
    try {
      final stream = await _mic.start();
      await _micSub?.cancel();
      _micSub = stream.listen(
        _onPcm,
        onError: (Object e) {
          appLog('PEER_HOST', 'mic stream error: $e');
          _scheduleMicRestart();
        },
        onDone: () {
          appLog('PEER_HOST', 'mic stream ended');
          _scheduleMicRestart();
        },
        cancelOnError: true,
      );
      _micRestartAttempt = 0;
      if (state.isRunning && !state.micActive) {
        state = state.copyWith(micActive: true);
      }
      appLog('PEER_HOST', 'Microphone capture started');
    } catch (e) {
      appLog('PEER_HOST', 'mic start failed: $e');
      _scheduleMicRestart();
      rethrow;
    } finally {
      _micStarting = false;
    }
  }

  void _onPcm(Uint8List chunk) {
    try {
      final audio = _audio;
      if (audio == null || audio.isClosed) return;
      audio.add(chunk);
      // Fast attack, slow release so a short cry registers on the meter.
      final instant = pcm16Level(chunk);
      _level = math.max(instant, _level * 0.85);
    } catch (e) {
      appLog('PEER_HOST', 'pcm handling failed (chunk dropped): $e');
    }
  }

  /// The mic died while hosting: keep the server up and retry with capped
  /// exponential backoff (1 s → 30 s). A monitor sees silence, its zombie
  /// watchdog reconnects, and audio resumes on the first successful retry.
  void _scheduleMicRestart() {
    if (!state.isRunning) return;
    if (state.micActive) state = state.copyWith(micActive: false);
    if (_micRestartTimer != null) return;
    final delay = Duration(
        seconds: math.min(30, 1 << math.min(5, _micRestartAttempt)));
    _micRestartAttempt++;
    appLog('PEER_HOST',
        'Restarting microphone in ${delay.inSeconds}s (attempt $_micRestartAttempt)');
    _micRestartTimer = Timer(delay, () async {
      _micRestartTimer = null;
      if (!state.isRunning) return;
      try {
        await _mic.stop();
      } catch (_) {}
      try {
        await _startMic();
      } catch (_) {
        // _startMic already scheduled the next attempt.
      }
    });
  }

  // --------------------------------------------------------------- pairing

  bool _isTokenValid(String token) {
    final hash = hashToken(token);
    for (final c in state.pairedClients) {
      if (constantTimeEquals(c.tokenHash, hash)) return true;
    }
    return false;
  }

  Future<String> _issueToken(String clientId, String clientName) async {
    final token = generateToken();
    final client = PairedClient(
      id: clientId,
      name: clientName,
      tokenHash: hashToken(token),
      pairedAt: DateTime.now(),
    );
    // Re-pairing from the same device replaces its old token.
    final others = state.pairedClients.where((c) => c.id != clientId).toList();
    state = state.copyWith(
      pairedClients: [...others, client],
      // A used code is spent: anyone who saw it over a shoulder can't reuse it.
      code: generatePairingCode(),
    );
    await _saveConfig();
    return token;
  }

  /// Show a fresh code (e.g. the old one was seen by the wrong person).
  void regenerateCode() {
    if (!state.isRunning) return;
    state = state.copyWith(code: generatePairingCode(), lastPairingNote: null);
    appLog('PEER_HOST', 'Pairing code regenerated');
  }

  /// Forget a paired monitor; its token stops working immediately (the
  /// next status poll or stream open gets 401, and an open stream ends when
  /// the monitor reconnects).
  Future<void> revoke(String clientId) async {
    await _loaded;
    state = state.copyWith(
      pairedClients:
          state.pairedClients.where((c) => c.id != clientId).toList(),
    );
    await _saveConfig();
    appLog('PEER_HOST', 'Revoked paired device $clientId');
  }

  Future<void> revokeAll() async {
    await _loaded;
    state = state.copyWith(pairedClients: const []);
    await _saveConfig();
    appLog('PEER_HOST', 'Revoked all paired devices');
  }

  /// Rename this host. Applies live — discovery replies and `/info` read
  /// the name through a closure.
  Future<void> setName(String name) async {
    await _loaded;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.name) return;
    state = state.copyWith(name: trimmed);
    await _saveConfig();
    appLog('PEER_HOST', 'Host renamed to "$trimmed"');
  }
}
