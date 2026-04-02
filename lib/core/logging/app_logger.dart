import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Simple app-wide logger that writes to:
/// 1. debugPrint (visible in `flutter run` terminal output)
/// 2. A file at /tmp/rtsp_audio_mixer.log (readable from disk)
/// 3. An in-memory ring buffer (displayed in the app UI)
///
/// ## How to read logs
///
/// **In the app:** A log panel is shown at the bottom of the login screen.
///
/// **In the terminal:** Logs appear as `flutter:` prefixed lines when running
/// with `flutter run -d macos`. Look for lines starting with the tag.
///
/// **From disk:** `cat /tmp/rtsp_audio_mixer.log` or `tail -f /tmp/rtsp_audio_mixer.log`
/// The file is cleared on each app start.
class AppLogger {
  AppLogger._();
  static final instance = AppLogger._();

  static const _logFile = '/tmp/rtsp_audio_mixer.log';
  static const _maxLines = 50;

  final _buffer = ListQueue<String>();
  final _listeners = <VoidCallback>[];

  List<String> get lines => _buffer.toList();

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  /// Call once at app start to clear the log file.
  void init() {
    try {
      File(_logFile).writeAsStringSync('--- App started ${DateTime.now()} ---\n');
    } catch (_) {}
  }

  /// Log a message with a tag.
  void log(String tag, String message) {
    final ts = DateTime.now().toString().substring(11, 19);
    final line = '$ts [$tag] $message';

    // 1. debugPrint → terminal
    debugPrint(line);

    // 2. File
    try {
      File(_logFile).writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}

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
