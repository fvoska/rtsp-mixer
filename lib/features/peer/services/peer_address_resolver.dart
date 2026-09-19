import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../cameras/models/protect_camera.dart';
import '../helpers/peer_urls.dart';
import '../peer_protocol.dart';
import 'discovery.dart';

/// Injectable so the player tests can stub "the host moved" without UDP.
final peerAddressResolverProvider =
    Provider<PeerAddressResolver>((_) => resolvePeerStreamUrl);

/// Ask the LAN where a paired phone lives right now.
///
/// Returns the camera's stream URL re-pointed at the host's current
/// address/port when discovery finds it somewhere else, or null when the
/// address is unchanged, the host didn't answer in time, or anything at all
/// went wrong. Never throws: the stored URL stays the fallback.
typedef PeerAddressResolver = Future<String?> Function(ProtectCamera camera);

Future<String?> resolvePeerStreamUrl(
  ProtectCamera camera, {
  Duration timeout = const Duration(seconds: 2),
  int targetPort = kPeerDiscoveryPort,
  Future<List<InternetAddress>> Function()? targets,
}) async {
  try {
    final hostId = camera.peerHostId;
    final current = camera.rtspsStreamUrls['stream'];
    if (hostId == null || hostId.isEmpty || current == null) return null;
    final found = await DiscoveryScanner.findHost(
      hostId,
      timeout: timeout,
      targetPort: targetPort,
      targets: targets,
    );
    if (found == null) {
      appLog('PEER', '${camera.name ?? camera.id}: host $hostId not seen on '
          'the LAN within ${timeout.inSeconds}s — keeping last address');
      return null;
    }
    final updated = repointPeerUrl(current, found.address, found.port);
    if (updated == current) return null;
    appLog('PEER',
        '${camera.name ?? camera.id}: host moved to ${found.address}:${found.port}');
    return updated;
  } catch (e) {
    appLog('PEER', 'resolvePeerStreamUrl failed (keeping last address): $e');
    return null;
  }
}
