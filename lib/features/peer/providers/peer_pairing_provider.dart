import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/providers/camera_provider.dart';
import '../helpers/peer_urls.dart';
import '../models/discovered_host.dart';
import '../models/pairing_payload.dart';
import '../services/discovery.dart';
import '../services/pairing_code.dart';
import '../services/peer_pairing_client.dart';

final peerPairingClientProvider =
    Provider<PeerPairingClient>((_) => PeerPairingClient());

/// Factory so tests can point the scanner at a loopback beacon.
final discoveryScannerFactoryProvider =
    Provider<DiscoveryScanner Function()>((_) => DiscoveryScanner.new);

/// Monitor-side pairing screen state.
class PeerPairingState {
  const PeerPairingState({
    this.hosts = const [],
    this.scanning = false,
    this.pairing = false,
    this.error,
    this.pairedCameraId,
    this.pairedHostName,
  });

  final List<DiscoveredHost> hosts;
  final bool scanning;
  final bool pairing;
  final String? error;

  /// Set once a pairing succeeded — the screen pops on it.
  final String? pairedCameraId;
  final String? pairedHostName;

  static const Object _unset = Object();

  PeerPairingState copyWith({
    List<DiscoveredHost>? hosts,
    bool? scanning,
    bool? pairing,
    Object? error = _unset,
    Object? pairedCameraId = _unset,
    Object? pairedHostName = _unset,
  }) =>
      PeerPairingState(
        hosts: hosts ?? this.hosts,
        scanning: scanning ?? this.scanning,
        pairing: pairing ?? this.pairing,
        error: identical(error, _unset) ? this.error : error as String?,
        pairedCameraId: identical(pairedCameraId, _unset)
            ? this.pairedCameraId
            : pairedCameraId as String?,
        pairedHostName: identical(pairedHostName, _unset)
            ? this.pairedHostName
            : pairedHostName as String?,
      );
}

final peerPairingProvider =
    NotifierProvider.autoDispose<PeerPairingNotifier, PeerPairingState>(
        PeerPairingNotifier.new);

/// Discovers hosts while the pairing screen is open and performs the
/// pairing handshake, adding the result to [CameraNotifier] as a peer camera.
class PeerPairingNotifier extends Notifier<PeerPairingState> {
  DiscoveryScanner? _scanner;
  StreamSubscription<List<DiscoveredHost>>? _sub;

  @override
  PeerPairingState build() {
    ref.onDispose(() {
      // ignore: unawaited_futures
      _sub?.cancel();
      // ignore: unawaited_futures
      _scanner?.dispose();
    });
    return const PeerPairingState();
  }

  Future<void> startScan() async {
    if (_scanner != null) return;
    try {
      final scanner = ref.read(discoveryScannerFactoryProvider)();
      _scanner = scanner;
      _sub = scanner.hosts.listen((hosts) {
        state = state.copyWith(hosts: hosts);
      });
      final ok = await scanner.start();
      state = state.copyWith(scanning: ok);
      if (!ok) {
        appLog('PAIR', 'Discovery unavailable — manual entry only');
      }
    } catch (e) {
      appLog('PAIR', 'startScan failed: $e');
      state = state.copyWith(scanning: false);
    }
  }

  Future<void> stopScan() async {
    final scanner = _scanner;
    _scanner = null;
    await _sub?.cancel();
    _sub = null;
    if (scanner != null) await scanner.dispose();
    state = state.copyWith(scanning: false);
  }

  void clearError() => state = state.copyWith(error: null);

  /// Pair from a scanned QR payload.
  Future<bool> pairWithPayload(PairingPayload payload) {
    if (!payload.isSupportedProtocol) {
      state = state.copyWith(
          error: 'That phone runs a different Roomtone version — update both.');
      return Future.value(false);
    }
    return pair(
      address: payload.address,
      port: payload.port,
      code: payload.code,
      hostName: payload.hostName,
      hostId: payload.hostId,
    );
  }

  /// Pair with a host at [address]:[port] using [code]. On success the host
  /// is added (or re-paired) as a peer camera and [PeerPairingState.pairedCameraId]
  /// is set. Returns whether it succeeded; the failure copy lands in `error`.
  Future<bool> pair({
    required String address,
    required int port,
    required String code,
    String? hostName,
    String? hostId,
  }) async {
    if (state.pairing) return false;
    final normalized = normalizePairingCode(code);
    if (normalized.length != kPairingCodeLength) {
      state = state.copyWith(error: 'Enter the 6-digit code shown on the host.');
      return false;
    }
    state = state.copyWith(pairing: true, error: null);
    try {
      final client = ref.read(peerPairingClientProvider);
      final result = await client.pair(
        address: address,
        port: port,
        code: normalized,
        clientId: await _clientId(),
        clientName: _clientName(),
      );
      if (!result.isSuccess) {
        state = state.copyWith(
          pairing: false,
          error: result.message ?? 'Pairing failed.',
        );
        return false;
      }
      final resolvedHostId = result.hostId ?? hostId;
      if (resolvedHostId == null || resolvedHostId.isEmpty) {
        state = state.copyWith(pairing: false, error: 'Host sent no id.');
        return false;
      }
      final name = result.hostName ?? hostName ?? 'Phone camera';
      final url = peerStreamUrl(address, port, result.token!);
      final cameraId =
          await ref.read(cameraNotifierProvider.notifier).addPeerCamera(
                hostId: resolvedHostId,
                url: url,
                name: name,
              );
      appLog('PAIR', 'Paired with "$name" ($resolvedHostId) at $address:$port');
      state = state.copyWith(
        pairing: false,
        pairedCameraId: cameraId,
        pairedHostName: name,
      );
      return true;
    } catch (e) {
      appLog('PAIR', 'pair failed: $e');
      state = state.copyWith(pairing: false, error: 'Pairing failed: $e');
      return false;
    }
  }

  /// Verify a typed address is a Roomtone host before asking for the code.
  Future<DiscoveredHost?> lookup(String address, int port) =>
      ref.read(peerPairingClientProvider).fetchInfo(address.trim(), port);

  /// Stable id for this monitor so re-pairing replaces its old token on the
  /// host rather than piling up entries.
  Future<String> _clientId() async {
    const key = 'peer_client_id';
    try {
      final storage = ref.read(storageProvider);
      // Bounded: pairing must never hang on a stalled keystore call.
      final existing =
          await storage.read(key).timeout(const Duration(seconds: 2));
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = generatePeerId();
      await storage.write(key, fresh).timeout(const Duration(seconds: 2));
      return fresh;
    } catch (e) {
      appLog('PAIR', 'client id storage failed (using ephemeral id): $e');
      return generatePeerId();
    }
  }

  static String _clientName() {
    if (kIsWeb) return 'Roomtone (web)';
    try {
      final os = Platform.operatingSystem;
      return 'Roomtone on ${os[0].toUpperCase()}${os.substring(1)}';
    } catch (_) {
      return 'Roomtone monitor';
    }
  }
}
