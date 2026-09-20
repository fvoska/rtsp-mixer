import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

import '../../../core/logging/app_logger.dart';
import '../models/battery_status.dart';

/// Where the host phone's battery reading comes from. Abstract so tests
/// (and platforms without a battery) can substitute a fake.
abstract class BatterySource {
  /// The current reading, or null when the platform cannot say. Must never
  /// throw: the host publishes whatever it gets and carries on serving.
  Future<BatteryStatus?> read();

  /// Fires when the power state changes (plugged in / unplugged), so the
  /// host can refresh sooner than its periodic poll. May never fire.
  Stream<void> get changes;

  Future<void> dispose();
}

/// A source that always reports nothing — used when the platform has no
/// battery plugin (tests, desktops) or the plugin failed.
class NoBatterySource implements BatterySource {
  const NoBatterySource();

  @override
  Future<BatteryStatus?> read() async => null;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// Reads the device battery through `battery_plus`.
///
/// Every call is wrapped: a missing platform implementation, a plugin
/// exception, or a nonsensical level degrades to null. Hosting is the
/// feature; the battery readout is a courtesy.
class DeviceBatterySource implements BatterySource {
  DeviceBatterySource({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<BatteryStatus?> read() async {
    try {
      final level = await _battery.batteryLevel;
      if (level < 0 || level > 100) return null;
      BatteryState state;
      try {
        state = await _battery.batteryState;
      } catch (e) {
        appLog('PEER_HOST', 'battery state unavailable ($e); assuming unplugged');
        state = BatteryState.unknown;
      }
      final plugged = switch (state) {
        BatteryState.charging ||
        BatteryState.full ||
        BatteryState.connectedNotCharging =>
          true,
        BatteryState.discharging || BatteryState.unknown => false,
      };
      return BatteryStatus(percent: level, plugged: plugged);
    } catch (e) {
      appLog('PEER_HOST', 'battery level unavailable: $e');
      return null;
    }
  }

  @override
  Stream<void> get changes {
    try {
      return _battery.onBatteryStateChanged
          .map<void>((_) {})
          .handleError((Object e) {
        appLog('PEER_HOST', 'battery state stream error (ignored): $e');
      });
    } catch (e) {
      appLog('PEER_HOST', 'battery state stream unavailable: $e');
      return const Stream.empty();
    }
  }

  @override
  Future<void> dispose() async {}
}
