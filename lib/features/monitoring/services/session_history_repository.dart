import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../models/session.dart';

/// Persists session history to `<appDocumentsDir>/sessions.json`.
///
/// Per CLAUDE.md ("no exception may kill a running audio stream"):
/// - All IO is wrapped in try/catch.
/// - Corrupt files → log + return empty state.
/// - Write failures are logged and swallowed (the next debounced write will retry).
///
/// File schema:
/// ```
/// { "current": Session|null, "past": [Session, ...] }
/// ```
/// `past` is trimmed to the 100 most recent finalized sessions.
class SessionHistoryRepository {
  static const _filename = 'sessions.json';
  static const _tmpSuffix = '.tmp';
  static const maxPast = 100;

  /// Load `(current, past)` from disk. Returns an empty pair on any failure
  /// (missing file, corrupt JSON, IO error). Never throws.
  Future<({Session? current, List<Session> past})> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return (current: null, past: const <Session>[]);
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return (current: null, past: const <Session>[]);
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      Session? current;
      final currentRaw = decoded['current'];
      if (currentRaw is Map<String, dynamic>) {
        try {
          current = Session.fromJson(currentRaw);
        } catch (e) {
          appLog('SESSION', 'load: dropped corrupt current session ($e)');
        }
      }

      final past = <Session>[];
      final pastRaw = decoded['past'];
      if (pastRaw is List<dynamic>) {
        for (final entry in pastRaw) {
          try {
            past.add(Session.fromJson(entry as Map<String, dynamic>));
          } catch (e) {
            appLog('SESSION', 'load: dropped corrupt past session ($e)');
          }
        }
      }

      // Defense in depth — even if disk had >maxPast, trim on the way in.
      final trimmed = past.length > maxPast ? past.sublist(0, maxPast) : past;
      return (current: current, past: trimmed);
    } on FormatException catch (e) {
      appLog('SESSION', 'load: corrupt JSON, returning empty ($e)');
      return (current: null, past: const <Session>[]);
    } on FileSystemException catch (e) {
      appLog('SESSION', 'load: filesystem error, returning empty ($e)');
      return (current: null, past: const <Session>[]);
    } catch (e, st) {
      appLog('SESSION', 'load: unexpected error ($e); stack=$st');
      return (current: null, past: const <Session>[]);
    }
  }

  /// Atomic write: serialize to `sessions.json.tmp`, then rename over the
  /// target so a half-written file is never observed. Trims `past` to [maxPast]
  /// before writing.
  ///
  /// On any failure logs and returns silently — must NOT propagate per CLAUDE.md.
  Future<void> save({Session? current, required List<Session> past}) async {
    try {
      final trimmed = past.length > maxPast ? past.sublist(0, maxPast) : past;
      final payload = jsonEncode({
        'current': current?.toJson(),
        'past': trimmed.map((s) => s.toJson()).toList(),
      });

      final target = await _file();
      final tmp = File('${target.path}$_tmpSuffix');
      await tmp.writeAsString(payload, flush: true);
      // Rename is atomic on POSIX and Windows when source/target share a volume.
      await tmp.rename(target.path);
    } catch (e, st) {
      appLog('SESSION', 'save: failed ($e); stack=$st');
      // swallow — next debounced flush will retry
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_filename');
  }
}
