import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/services/discovery.dart';

import '../../support/async.dart';

void main() {
  group('parseDiscoveryReply', () {
    final now = DateTime(2026, 9, 19);
    test('accepts a well-formed reply and uses the datagram source address',
        () {
      final h = parseDiscoveryReply(
        utf8.encode(jsonEncode({
          'app': 'roomtone',
          'type': 'host',
          'protocol': 1,
          'hostId': 'abc',
          'name': ' Nursery ',
          'port': 47831,
          'pairing': true,
        })),
        '192.168.1.20',
        now,
      );
      expect(h, isNotNull);
      expect(h!.hostId, 'abc');
      expect(h.name, 'Nursery');
      expect(h.address, '192.168.1.20');
      expect(h.port, 47831);
      expect(h.protocol, 1);
      expect(h.pairingOpen, isTrue);
      expect(h.lastSeen, now);
    });

    test('rejects probes, foreign apps, garbage and bad ports', () {
      DateTime t() => now;
      expect(parseDiscoveryReply([0xff, 0xfe], 'x', t()), isNull);
      expect(
          parseDiscoveryReply(
              utf8.encode('{"app":"roomtone","type":"probe"}'), 'x', t()),
          isNull);
      expect(
          parseDiscoveryReply(
              utf8.encode(
                  '{"app":"other","type":"host","hostId":"a","port":1}'),
              'x',
              t()),
          isNull);
      expect(
          parseDiscoveryReply(
              utf8.encode(
                  '{"app":"roomtone","type":"host","hostId":"a","port":0}'),
              'x',
              t()),
          isNull);
      expect(parseDiscoveryReply(utf8.encode('[1,2]'), 'x', t()), isNull);
    });
  });

  group('beacon + scanner on loopback', () {
    late DiscoveryBeacon beacon;

    setUp(() async {
      beacon = DiscoveryBeacon(
        hostId: 'host-xyz',
        hostName: () => 'Nursery phone',
        httpPort: () => 51000,
      );
      final ok = await beacon.start(
          bindAddress: InternetAddress.loopbackIPv4, port: 0);
      expect(ok, isTrue);
    });

    tearDown(() => beacon.stop());

    test('scanner finds the beacon and reports its HTTP port', () async {
      final scanner = DiscoveryScanner(
        targetPort: beacon.port!,
        probeInterval: const Duration(milliseconds: 100),
        targets: () async => [InternetAddress.loopbackIPv4],
      );
      addTearDown(scanner.dispose);
      expect(await scanner.start(), isTrue);
      await waitFor(() => scanner.currentHosts.isNotEmpty,
          reason: 'the beacon answers a loopback probe');
      final host = scanner.currentHosts.single;
      expect(host.hostId, 'host-xyz');
      expect(host.name, 'Nursery phone');
      expect(host.port, 51000);
      expect(host.address, '127.0.0.1');
    });

    test('hosts age out once they stop answering', () async {
      var now = DateTime(2026, 9, 19, 12);
      final scanner = DiscoveryScanner(
        targetPort: beacon.port!,
        probeInterval: const Duration(milliseconds: 100),
        staleAfter: const Duration(seconds: 3),
        targets: () async => [InternetAddress.loopbackIPv4],
        now: () => now,
      );
      addTearDown(scanner.dispose);
      await scanner.start();
      await waitFor(() => scanner.currentHosts.isNotEmpty,
          reason: 'host discovered');
      beacon.stop();
      now = now.add(const Duration(seconds: 10));
      await waitFor(() => scanner.currentHosts.isEmpty,
          reason: 'silent host expires from the list');
    });

    test('findHost resolves a host by id and gives up on unknown ids',
        () async {
      final found = await DiscoveryScanner.findHost(
        'host-xyz',
        targetPort: beacon.port!,
        targets: () async => [InternetAddress.loopbackIPv4],
        timeout: const Duration(seconds: 3),
      );
      expect(found, isNotNull);
      expect(found!.address, '127.0.0.1');
      expect(found.port, 51000);

      final missing = await DiscoveryScanner.findHost(
        'someone-else',
        targetPort: beacon.port!,
        targets: () async => [InternetAddress.loopbackIPv4],
        timeout: const Duration(milliseconds: 400),
      );
      expect(missing, isNull);
    });
  });
}
