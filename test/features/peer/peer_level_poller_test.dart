import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/models/battery_status.dart';
import 'package:rtsp_mixer/features/peer/services/peer_level_poller.dart';

import '../../support/async.dart';

void main() {
  test('reports the fetched level and listener count, null before/after', () async {
    var level = 0.3;
    var fail = false;
    var calls = 0;
    final poller = PeerLevelPoller(
      interval: const Duration(milliseconds: 20),
      staleAfter: const Duration(milliseconds: 150),
      fetch: (url, _) async {
        calls++;
        if (fail) throw Exception('down');
        return {'level': level, 'levelDb': -20.0, 'listeners': 2};
      },
    );
    addTearDown(poller.stopAll);
    expect(poller.levelFor('cam'), isNull);
    poller.start('cam', 'http://h/roomtone/v1/status?token=t');
    await waitFor(() => poller.levelFor('cam') == 0.3, reason: 'first poll lands');
    expect(poller.listenersFor('cam'), 2);
    expect(poller.dbFor('cam'), -20.0);
    level = 0.9;
    await waitFor(() => poller.levelFor('cam') == 0.9, reason: 'level updates');
    fail = true;
    await waitFor(() => poller.levelFor('cam') == null,
        reason: 'level goes stale when polls fail');
    expect(poller.dbFor('cam'), isNull);
    expect(calls, greaterThan(2));
    poller.stop('cam');
    final after = calls;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, after);
  });

  test('ignores null/garbage and clamps out-of-range levels', () async {
    var payload = <String, dynamic>{'level': 7.0};
    final poller = PeerLevelPoller(
      interval: const Duration(milliseconds: 20),
      fetch: (_, _) async => payload,
    );
    addTearDown(poller.stopAll);
    poller.start('cam', 'http://h/status');
    await waitFor(() => poller.levelFor('cam') == 1.0, reason: 'clamped to 1');
    payload = {'level': 'loud'};
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(poller.levelFor('cam'), 1.0); // last good value retained
  });

  test('reports the host battery, drops it when absent or stale', () async {
    Map<String, dynamic> payload = {
      'level': 0.2,
      'battery': {'percent': 42, 'plugged': false},
    };
    var fail = false;
    final poller = PeerLevelPoller(
      interval: const Duration(milliseconds: 20),
      staleAfter: const Duration(milliseconds: 150),
      fetch: (_, _) async {
        if (fail) throw Exception('down');
        return payload;
      },
    );
    addTearDown(poller.stopAll);
    expect(poller.batteryFor('cam'), isNull);
    poller.start('cam', 'http://h/status');
    await waitFor(
        () => poller.batteryFor('cam') ==
            const BatteryStatus(percent: 42, plugged: false),
        reason: 'battery parsed from the first poll');
    payload = {'level': 0.2, 'battery': {'percent': 43, 'plugged': true}};
    await waitFor(() => poller.batteryFor('cam')?.plugged == true,
        reason: 'battery follows the host');
    // An older host that stops sending the field: no reading, no crash.
    payload = {'level': 0.2};
    await waitFor(() => poller.batteryFor('cam') == null,
        reason: 'battery cleared when the host omits it');
    expect(poller.levelFor('cam'), 0.2);
    payload = {'level': 0.2, 'battery': {'percent': 40, 'plugged': false}};
    await waitFor(() => poller.batteryFor('cam') != null,
        reason: 'battery back');
    fail = true;
    await waitFor(() => poller.batteryFor('cam') == null,
        reason: 'battery goes stale with the level when polls fail');
  });

  test('start with an empty url is a no-op', () {
    final poller = PeerLevelPoller(fetch: (_, _) async => null);
    poller.start('cam', null);
    poller.start('cam', '');
    expect(poller.levelFor('cam'), isNull);
    poller.stopAll();
  });
}
