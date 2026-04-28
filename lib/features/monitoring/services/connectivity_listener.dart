import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/logging/app_logger.dart';

/// Wraps connectivity_plus with a 1-second debounce + WiFi/Ethernet vs mobile logic.
/// Emits edge-triggered callbacks:
///   - onDropped: LAN reachability lost (was on, now off)
///   - onReconnected: LAN reachability restored (was off, now on)
///
/// Rationale (RESEARCH §Section 3):
///   - connectivity_plus docs: "doesn't filter events, nor ensures distinct values"
///     — rapid flaps can fire 3–5 events. Debounce to avoid thundering-herd reconnects.
///   - Cameras are on LAN. Mobile-only is useless for reaching them — suppress those edges.
class ConnectivityListener {
  ConnectivityListener({
    required this.onDropped,
    required this.onReconnected,
    this.debounce = const Duration(seconds: 1),
    Stream<List<ConnectivityResult>>? stream,
  }) : _stream = stream ?? Connectivity().onConnectivityChanged;

  final void Function() onDropped;
  final void Function() onReconnected;
  final Duration debounce;
  final Stream<List<ConnectivityResult>> _stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounceTimer;
  bool? _lastKnownHasLan; // null = never evaluated

  /// Start listening. Must pair with cancel().
  ///
  /// Subscribes synchronously (no `await` before `listen`) so callers do not
  /// race the first emitted event. Seeds `_lastKnownHasLan` from
  /// `Connectivity().checkConnectivity()` in the background (WR-02 fix) so
  /// the first debounced edge compares against truth rather than the
  /// default-true fallback. Race window between subscription and snapshot
  /// is tolerable because the 1-second debounce typically dominates the
  /// snapshot latency on a real device.
  void start() {
    _sub?.cancel();
    _sub = _stream.listen((results) {
      try {
        final hasWifi = results.contains(ConnectivityResult.wifi);
        final hasEthernet = results.contains(ConnectivityResult.ethernet);
        final lanReachable = hasWifi || hasEthernet;
        _scheduleDebounce(lanReachable);
      } catch (e) {
        appLog('CONN', 'Listener error (non-fatal): $e');
      }
    });
    // Seed initial state asynchronously — fire and forget.
    Connectivity().checkConnectivity().then((initial) {
      // Only seed if no event has already established the state, otherwise
      // we'd clobber a real edge.
      if (_lastKnownHasLan == null) {
        _lastKnownHasLan = initial.contains(ConnectivityResult.wifi) ||
            initial.contains(ConnectivityResult.ethernet);
        appLog('CONN',
            'Seeded initial connectivity: lanReachable=$_lastKnownHasLan ($initial)');
      }
    }).catchError((Object e) {
      // checkConnectivity is unavailable in pure-Dart unit tests (no platform
      // bindings). Leave `_lastKnownHasLan` as null — first event will use
      // wasOn=true (existing behavior).
      appLog('CONN', 'Initial connectivity snapshot failed (non-fatal): $e');
    });
    appLog('CONN',
        'ConnectivityListener started (debounce=${debounce.inMilliseconds}ms)');
  }

  void _scheduleDebounce(bool lanReachable) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      try {
        if (_lastKnownHasLan == lanReachable) return;
        final wasOn = _lastKnownHasLan ?? true;
        _lastKnownHasLan = lanReachable;
        if (!lanReachable && wasOn) {
          appLog('CONN', 'LAN dropped');
          onDropped();
        } else if (lanReachable && !wasOn) {
          appLog('CONN', 'LAN reconnected');
          onReconnected();
        }
      } catch (e) {
        appLog('CONN', 'Debounce callback crashed: $e');
      }
    });
  }

  /// Cancel the subscription + any pending debounce timer.
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sub?.cancel();
    _sub = null;
    appLog('CONN', 'ConnectivityListener cancelled');
  }
}
