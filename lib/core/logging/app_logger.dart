import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Simple app-wide logger that writes to:
/// 1. debugPrint (visible in `flutter run` terminal output)
/// 2. A file at /tmp/rtsp_mixer.log (readable from disk)
/// 3. An in-memory ring buffer (displayed in the app UI)
///
/// ## How to read logs
///
/// **In the app:** A log panel is shown at the bottom of the login screen.
///
/// **In the terminal:** Logs appear as `flutter:` prefixed lines when running
/// with `flutter run -d macos`. Look for lines starting with the tag.
///
/// **From disk:** `cat /tmp/rtsp_mixer.log` or `tail -f /tmp/rtsp_mixer.log`
/// The file is cleared on each app start.
class AppLogger {
  AppLogger._();
  static final instance = AppLogger._();

  static const _logFile = '/tmp/rtsp_mixer.log';
  static const _maxLines = 500;

  /// Whether [log] appends to [_logFile].
  ///
  /// Off under `flutter test`. Every logged line is a synchronous append, and
  /// the path is a fixed one shared by every test process — `flutter test` runs
  /// test files concurrently, so the whole suite was serialising on one file
  /// and any assertion on [exportFromDisk] would see other files' lines.
  /// Disabling the sink keeps the in-memory buffer (which the UI and tests
  /// actually read) and drops only the side effect.
  static bool fileSinkEnabled =
      !Platform.environment.containsKey('FLUTTER_TEST');

  final _buffer = ListQueue<String>();
  final _listeners = <VoidCallback>[];

  List<String> get lines => _buffer.toList();

  /// Full log content for export.
  String get exportText => _buffer.join('\n');

  /// Full log from disk (includes lines that may have rotated out of memory).
  /// Falls back to [exportText] when the file sink is disabled or unreadable.
  String get exportFromDisk {
    if (!fileSinkEnabled) return exportText;
    try {
      return File(_logFile).readAsStringSync();
    } catch (_) {
      return exportText;
    }
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  /// Call once at app start to clear the log file.
  void init() {
    if (!fileSinkEnabled) return;
    try {
      File(_logFile).writeAsStringSync('--- App started ${DateTime.now()} ---\n');
    } catch (_) {}
  }

  /// Test-only: drop the buffered lines and any registered listeners.
  ///
  /// This is a process-global singleton, so without a reset the ring buffer
  /// carries one test's lines into the next, and a widget that registers a
  /// listener but is never disposed leaks it into every later test in the file.
  @visibleForTesting
  void resetForTest() {
    _buffer.clear();
    _listeners.clear();
  }

  /// Log a message with a tag.
  void log(String tag, String message) {
    final ts = DateTime.now().toString().substring(11, 19);
    final line = '$ts [$tag] $message';

    // 1. debugPrint → terminal
    debugPrint(line);

    // 2. File
    if (fileSinkEnabled) {
      try {
        File(_logFile).writeAsStringSync('$line\n', mode: FileMode.append);
      } catch (_) {}
    }

    // 3. Ring buffer → UI
    _buffer.addLast(line);
    while (_buffer.length > _maxLines) {
      _buffer.removeFirst();
    }
    _notify();
  }
}

/// Shortcut for quick logging.
void appLog(String tag, String message) => AppLogger.instance.log(tag, message);
