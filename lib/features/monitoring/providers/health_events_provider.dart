import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../models/health_event.dart';

/// In-memory session-scoped health event recorder (D-13, D-14).
/// Capped at 1000 events (D-17) — drops oldest when full.
class HealthEventsNotifier extends Notifier<List<HealthEvent>> {
  static const _maxEvents = 1000; // D-17

  @override
  List<HealthEvent> build() => const [];

  /// Append an event. Drops the oldest when the cap is exceeded.
  /// Also logs via appLog('HEALTH', ...) so LogScreen sees it (two consumers).
  void record(HealthEvent event) {
    final updated = [...state, event];
    if (updated.length > _maxEvents) {
      updated.removeRange(0, updated.length - _maxEvents);
    }
    state = updated;
    appLog('HEALTH',
        '${event.type.name} ${event.cameraName ?? 'session'} ${event.detail ?? ''}');
  }

  /// Reset the list (called on startMonitoring per D-13).
  void clear() => state = const [];
}

final healthEventsProvider =
    NotifierProvider<HealthEventsNotifier, List<HealthEvent>>(
  HealthEventsNotifier.new,
);
