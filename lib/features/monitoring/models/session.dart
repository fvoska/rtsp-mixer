import 'dart:math';

import '../../../core/logging/app_logger.dart';
import 'health_event.dart';

/// A monitoring session — one entry per Start→Stop cycle.
///
/// Persisted as a row in `<appDocumentsDir>/sessions.json` (see
/// [SessionHistoryRepository]). Immutable; use [withEventAppended] / [ended]
/// to produce derived copies.
///
/// Per CLAUDE.md: fromJson is tolerant of corrupt data — missing list fields
/// default to [], malformed events are dropped silently with an `appLog('SESSION', ...)`
/// breadcrumb. We never throw out of this code path because that would kill
/// the audio pipeline when the provider rebuilds.
class Session {
  /// Stable id, base36 derived from [Random.secure]. 12 chars, ~62 bits of entropy.
  final String id;
  final DateTime startedAt;

  /// Null while in-flight; set when the user taps Stop or when the next session begins.
  final DateTime? endedAt;
  final List<HealthEvent> events;

  /// Snapshot of (id, name) for the cameras involved in this session. Stored as
  /// a record so we don't pull CameraAudioState into the persistence layer.
  final List<({String id, String name})> cameras;

  const Session({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.events,
    required this.cameras,
  });

  /// Begin a fresh session. Generates a new id and stamps `startedAt = now()`.
  factory Session.start({required List<({String id, String name})> cameras}) {
    return Session(
      id: _newId(),
      startedAt: DateTime.now(),
      endedAt: null,
      events: const [],
      cameras: List.unmodifiable(cameras),
    );
  }

  /// Return a copy with [endedAt] set. Defaults to `DateTime.now()`.
  Session ended({DateTime? at}) => Session(
        id: id,
        startedAt: startedAt,
        endedAt: at ?? DateTime.now(),
        events: events,
        cameras: cameras,
      );

  /// Return a copy with [e] appended to [events]. Does not cap — caller decides.
  Session withEventAppended(HealthEvent e) => Session(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        events: [...events, e],
        cameras: cameras,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
        'cameras': cameras.map((c) => {'id': c.id, 'name': c.name}).toList(),
      };

  /// Tolerant parser. Skips malformed events. Defaults missing list fields to [].
  /// Throws only if `id` or `startedAt` are absent — those are load-bearing.
  factory Session.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final startedAt = DateTime.parse(json['startedAt'] as String);
    final endedAtRaw = json['endedAt'];
    DateTime? endedAt;
    if (endedAtRaw is String) {
      try {
        endedAt = DateTime.parse(endedAtRaw);
      } catch (e) {
        appLog('SESSION', 'session $id: malformed endedAt "$endedAtRaw" — treating as in-flight ($e)');
      }
    }

    final rawEvents = (json['events'] as List<dynamic>?) ?? const [];
    final events = <HealthEvent>[];
    for (final raw in rawEvents) {
      try {
        events.add(HealthEvent.fromJson(raw as Map<String, dynamic>));
      } catch (e) {
        appLog('SESSION', 'session $id: dropped malformed event ($e)');
      }
    }

    final rawCameras = (json['cameras'] as List<dynamic>?) ?? const [];
    final cameras = <({String id, String name})>[];
    for (final raw in rawCameras) {
      try {
        final m = raw as Map<String, dynamic>;
        cameras.add((id: m['id'] as String, name: m['name'] as String));
      } catch (e) {
        appLog('SESSION', 'session $id: dropped malformed camera entry ($e)');
      }
    }

    return Session(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      events: events,
      cameras: cameras,
    );
  }

  /// 12-char base36 random id (~62 bits entropy). No external dep needed.
  static String _newId() {
    final r = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 12; i++) {
      // 0-9a-z = 36 possible chars per slot.
      sb.write(r.nextInt(36).toRadixString(36));
    }
    return sb.toString();
  }
}
