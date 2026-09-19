import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../models/discovered_host.dart';
import '../peer_protocol.dart';

/// LAN discovery of Roomtone hosts over a tiny UDP protocol.
///
/// The monitor broadcasts a JSON probe to [kPeerDiscoveryPort]; every host
/// answers unicast with its id, name and HTTP port. Chosen over an mDNS
/// plugin because it is dependency-free, deterministic, and testable on the
/// loopback interface in `flutter test`; QR and typed addresses remain as
/// fallbacks for networks that block broadcast.
///
/// Every socket operation here is wrapped: discovery is a convenience and a
/// failure must never take down host mode or the monitor's pairing screen.

/// IPv4 addresses of this device that look like LAN addresses (non-loopback,
/// non-link-local), most likely home-network ranges first. Used for the QR
/// payload and the host screen. Never throws; may be empty.
Future<List<String>> lanIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    final addrs = <String>[];
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        addrs.add(a.address);
      }
    }
    int rank(String a) {
      if (a.startsWith('192.168.')) return 0;
      if (a.startsWith('10.')) return 1;
      if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a)) return 2;
      return 3;
    }
    addrs.sort((x, y) => rank(x).compareTo(rank(y)));
    return addrs;
  } catch (e) {
    appLog('DISCOVERY', 'NetworkInterface.list failed: $e');
    return const [];
  }
}

/// Broadcast targets for a probe: the limited broadcast address plus a /24
/// directed broadcast per local IPv4 address (Dart exposes no netmask, and a
/// /24 is what virtually every home LAN uses). Deduplicated.
Future<List<InternetAddress>> discoveryBroadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  for (final a in await lanIPv4Addresses()) {
    final parts = a.split('.');
    if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }
  return targets.map(InternetAddress.new).toList();
}

/// Host side: answers probes while hosting.
class DiscoveryBeacon {
  DiscoveryBeacon({
    required this.hostId,
    required this.hostName,
    required this.httpPort,
    this.pairingOpen,
  });

  final String hostId;
  final String Function() hostName;
  final int Function() httpPort;
  final bool Function()? pairingOpen;

  RawDatagramSocket? _socket;

  bool get isRunning => _socket != null;
  int? get port => _socket?.port;

  /// Bind and start answering. Returns false (and logs) when the port can't
  /// be bound — hosting continues without auto-discovery in that case.
  Future<bool> start({
    InternetAddress? bindAddress,
    int port = kPeerDiscoveryPort,
  }) async {
    if (_socket != null) return true;
    try {
      final socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      socket.listen(_onEvent, onError: (Object e) {
        appLog('DISCOVERY', 'beacon socket error (non-fatal): $e');
      });
      appLog('DISCOVERY', 'Beacon listening on UDP ${socket.port}');
      return true;
    } catch (e) {
      appLog('DISCOVERY', 'Beacon bind on UDP $port failed: $e');
      _socket = null;
      return false;
    }
  }

  void stop() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    try {
      final dg = socket.receive();
      if (dg == null) return;
      final probe = _decodeProbe(dg.data);
      if (probe == null) return;
      final reply = <String, Object?>{
        'app': kDiscoveryAppTag,
        'type': kDiscoveryReplyType,
        'protocol': kPeerProtocolVersion,
        'nonce': probe['nonce'],
        'hostId': hostId,
        'name': hostName(),
        'port': httpPort(),
        'pairing': pairingOpen?.call() ?? true,
      };
      socket.send(utf8.encode(jsonEncode(reply)), dg.address, dg.port);
    } catch (e) {
      appLog('DISCOVERY', 'beacon reply failed (non-fatal): $e');
    }
  }

  static Map<String, dynamic>? _decodeProbe(List<int> data) {
    try {
      if (data.length > 1024) return null;
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != kDiscoveryAppTag) return null;
      if (decoded['type'] != kDiscoveryProbeType) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

/// Monitor side: probes the LAN and keeps a live list of answering hosts.
class DiscoveryScanner {
  DiscoveryScanner({
    this.targetPort = kPeerDiscoveryPort,
    this.probeInterval = const Duration(seconds: 1),
    this.staleAfter = const Duration(seconds: 6),
    Future<List<InternetAddress>> Function()? targets,
    DateTime Function()? now,
  })  : _targets = targets ?? discoveryBroadcastTargets,
        _now = now ?? DateTime.now;

  final int targetPort;
  final Duration probeInterval;
  final Duration staleAfter;
  final Future<List<InternetAddress>> Function() _targets;
  final DateTime Function() _now;

  RawDatagramSocket? _socket;
  Timer? _timer;
  String _nonce = '';
  final Map<String, DiscoveredHost> _hosts = {};
  final _controller = StreamController<List<DiscoveredHost>>.broadcast();

  /// Emits the current host list whenever it changes (and on every probe
  /// tick so stale hosts age out visibly).
  Stream<List<DiscoveredHost>> get hosts => _controller.stream;
  List<DiscoveredHost> get currentHosts => _sorted();
  bool get isRunning => _socket != null;

  Future<bool> start() async {
    if (_socket != null) return true;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      _socket = socket;
      socket.listen(_onEvent, onError: (Object e) {
        appLog('DISCOVERY', 'scanner socket error (non-fatal): $e');
      });
      _timer = Timer.periodic(probeInterval, (_) => _tick());
      // ignore: unawaited_futures
      _tick();
      return true;
    } catch (e) {
      appLog('DISCOVERY', 'scanner bind failed: $e');
      _socket = null;
      return false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  /// Also closes the stream — call once, when the owner is disposed.
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _tick() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      _expire();
      _nonce = _now().microsecondsSinceEpoch.toRadixString(36);
      final probe = utf8.encode(jsonEncode({
        'app': kDiscoveryAppTag,
        'type': kDiscoveryProbeType,
        'protocol': kPeerProtocolVersion,
        'nonce': _nonce,
      }));
      for (final target in await _targets()) {
        try {
          socket.send(probe, target, targetPort);
        } catch (e) {
          // A single unroutable broadcast target (e.g. no default route in a
          // sandbox) must not stop the others.
          appLog('DISCOVERY', 'probe to ${target.address} failed: $e');
        }
      }
      _emit();
    } catch (e) {
      appLog('DISCOVERY', 'probe tick failed (non-fatal): $e');
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    try {
      final dg = socket.receive();
      if (dg == null) return;
      final host = parseDiscoveryReply(dg.data, dg.address.address, _now());
      if (host == null) return;
      final prev = _hosts[host.hostId];
      _hosts[host.hostId] = host;
      if (prev != host) _emit();
    } catch (e) {
      appLog('DISCOVERY', 'reply parse failed (non-fatal): $e');
    }
  }

  void _expire() {
    final cutoff = _now().subtract(staleAfter);
    final before = _hosts.length;
    _hosts.removeWhere((_, h) => h.lastSeen.isBefore(cutoff));
    if (_hosts.length != before) _emit();
  }

  List<DiscoveredHost> _sorted() {
    final list = _hosts.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_sorted());
  }

  /// One-shot: probe until a host with [hostId] answers or [timeout] elapses.
  /// Used to re-resolve a paired host whose LAN IP may have changed.
  static Future<DiscoveredHost?> findHost(
    String hostId, {
    Duration timeout = const Duration(seconds: 2),
    int targetPort = kPeerDiscoveryPort,
    Future<List<InternetAddress>> Function()? targets,
  }) async {
    final scanner = DiscoveryScanner(
      targetPort: targetPort,
      targets: targets,
      probeInterval: const Duration(milliseconds: 500),
    );
    try {
      final completer = Completer<DiscoveredHost?>();
      final sub = scanner.hosts.listen((hosts) {
        for (final h in hosts) {
          if (h.hostId == hostId && !completer.isCompleted) {
            completer.complete(h);
          }
        }
      });
      if (!await scanner.start()) return null;
      final result = await completer.future
          .timeout(timeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (e) {
      appLog('DISCOVERY', 'findHost($hostId) failed: $e');
      return null;
    } finally {
      await scanner.dispose();
    }
  }
}

/// Parse a beacon reply datagram into a [DiscoveredHost]. Null for anything
/// that is not a well-formed Roomtone reply. Pure; tested directly.
DiscoveredHost? parseDiscoveryReply(
    List<int> data, String fromAddress, DateTime now) {
  try {
    if (data.length > 2048) return null;
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['app'] != kDiscoveryAppTag) return null;
    if (decoded['type'] != kDiscoveryReplyType) return null;
    final id = decoded['hostId'];
    final port = decoded['port'];
    if (id is! String || id.isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    final name = decoded['name'];
    final protocol = decoded['protocol'];
    return DiscoveredHost(
      hostId: id,
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Phone camera',
      address: fromAddress,
      port: port,
      protocol: protocol is int ? protocol : 0,
      pairingOpen: decoded['pairing'] != false,
      lastSeen: now,
    );
  } catch (_) {
    return null;
  }
}
