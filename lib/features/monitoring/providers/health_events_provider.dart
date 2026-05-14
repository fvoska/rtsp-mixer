import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../models/health_event.dart';
import 'session_history_provider.dart';

/// In-memory session-scoped health event recorder (D-13, D-14).
/// Capped at 1000 events (D-17) — drops oldest when full.
///
/// Forwarding strategy (planner decision in 260514-siv-PLAN.md, §output):
///   `record()` also forwards every event into [sessionHistoryProvider] so
///   the persistence layer is the source of truth across restarts.
///   `healthEventsProvider` remains the in-memory UI source of truth this
///   session — keeps blast radius small versus deriving healthEventsProvider
///   from sessionHistory. A future cleanup may collapse the two via `select`.
class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
  static const _maxEvents = 1000; // D-17

  @override
  List<HealthEvent> build() => const [];

  /// Append an event. Drops the oldest when the cap is exceeded.
  /// Also logs via appLog('HEALTH', ...) so LogScreen sees it (two consumers)
  /// AND forwards to sessionHistoryProvider for disk persistence.
  void record(HealthEvent event) {
    final updated = [...state, event];
    if (updated.length > _maxEvents) {
      updated.removeRange(0, updated.length - _maxEvents);
    }
    state = updated;
    appLog('HEALTH',
        '${event.type.name} ${event.cameraName ?? 'session'} ${event.detail ?? ''}');

    // Forward to persistence. Wrapped in try/catch so an exception here can
    // never propagate to whatever code path is recording the event (CLAUDE.md:
    // no exception may kill a running audio stream).
    try {
      ref.read(sessionHistoryProvider.notifier).recordEvent(event);
    } catch (e) {
      appLog('SESSION', 'forward failed: $e');
    }
  }

  /// Reset the list (called on startMonitoring per D-13).
  void clear() => state = const [];
}

final healthEventsProvider =
    NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(
  HealthEventsNotifier.new,
);
