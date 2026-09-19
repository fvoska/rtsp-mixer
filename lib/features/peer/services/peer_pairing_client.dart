import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../helpers/peer_urls.dart';
import '../models/discovered_host.dart';
import '../peer_protocol.dart';

/// Why a pairing attempt failed. Drives the copy on the pairing screen.
enum PairFailure { wrongCode, locked, unreachable, incompatible, notRoomtone, other }

/// Result of [PeerPairingClient.pair].
class PairResult {
  const PairResult.success({
    required this.token,
    required this.hostId,
    required this.hostName,
  })  : failure = null,
        message = null,
        retryAfterSeconds = 0;

  const PairResult.failed(this.failure, {this.message, this.retryAfterSeconds = 0})
      : token = null,
        hostId = null,
        hostName = null;

  final String? token;
  final String? hostId;
  final String? hostName;
  final PairFailure? failure;
  final String? message;
  final int retryAfterSeconds;

  bool get isSuccess => token != null;
}

/// Plain `dart:io` HTTP client for the two pairing-time calls the monitor
/// makes to a host. Deliberately not dio: no interceptors, no TLS, and the
/// same client runs unchanged against the loopback server in tests.
class PeerPairingClient {
  PeerPairingClient({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Ask a host who it is. Null when the address does not answer, or answers
  /// with something that is not a Roomtone host.
  Future<DiscoveredHost?> fetchInfo(String address, int port) async {
    try {
      final body = await _get(peerInfoUrl(address, port));
      if (body == null) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != kDiscoveryAppTag) return null;
      final id = decoded['hostId'];
      if (id is! String || id.isEmpty) return null;
      return DiscoveredHost(
        hostId: id,
        name: (decoded['name'] as String?)?.trim().isNotEmpty == true
            ? (decoded['name'] as String).trim()
            : 'Phone camera',
        address: address,
        port: port,
        protocol: decoded['protocol'] is int ? decoded['protocol'] as int : 0,
        pairingOpen: decoded['pairing'] != false,
        lastSeen: DateTime.now(),
      );
    } catch (e) {
      appLog('PAIR', 'info $address:$port failed: $e');
      return null;
    }
  }

  Future<PairResult> pair({
    required String address,
    required int port,
    required String code,
    required String clientId,
    required String clientName,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse(peerPairUrl(address, port)))
          .timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'code': code,
        'clientId': clientId,
        'clientName': clientName,
        'protocol': kPeerProtocolVersion,
      }));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join().timeout(timeout);
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(body);
        json = decoded is Map<String, dynamic> ? decoded : const {};
      } catch (_) {
        json = const {};
      }
      switch (res.statusCode) {
        case 200:
          final token = json['token'];
          final hostId = json['hostId'];
          if (token is! String || token.isEmpty || hostId is! String) {
            return const PairResult.failed(PairFailure.notRoomtone,
                message: 'Unexpected reply from host.');
          }
          final protocol = json['protocol'];
          if (protocol is int && protocol != kPeerProtocolVersion) {
            return const PairResult.failed(PairFailure.incompatible,
                message: 'The host runs a different Roomtone version.');
          }
          return PairResult.success(
            token: token,
            hostId: hostId,
            hostName: (json['name'] as String?) ?? 'Phone camera',
          );
        case 403:
          final retry = json['retryAfterSeconds'];
          return PairResult.failed(PairFailure.wrongCode,
              message: 'Wrong code — check the code on the host phone.',
              retryAfterSeconds: retry is int ? retry : 0);
        case 429:
          final retry = json['retryAfterSeconds'];
          return PairResult.failed(PairFailure.locked,
              message: 'Too many attempts — try again shortly.',
              retryAfterSeconds: retry is int ? retry : 60);
        case 409:
          return const PairResult.failed(PairFailure.incompatible,
              message: 'The host runs a different Roomtone version.');
        case 404:
          return const PairResult.failed(PairFailure.notRoomtone,
              message: 'That address is not a Roomtone host.');
        default:
          return PairResult.failed(PairFailure.other,
              message: 'Host replied ${res.statusCode}.');
      }
    } on TimeoutException {
      return const PairResult.failed(PairFailure.unreachable,
          message: 'Host did not answer — same Wi‑Fi network?');
    } on SocketException catch (e) {
      return PairResult.failed(PairFailure.unreachable,
          message: 'Could not reach the host (${e.osError?.message ?? e.message}).');
    } catch (e) {
      appLog('PAIR', 'pair $address:$port failed: $e');
      return PairResult.failed(PairFailure.other, message: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _get(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return await utf8.decoder.bind(res).join().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
