import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/logging/app_logger.dart';

/// Isolate the process-global [AppLogger] between tests in the current file.
///
/// [AppLogger.instance] is a singleton holding a ring buffer and a listener
/// list that outlive any single test. Suites that render the log UI — or that
/// assert on logged output — otherwise see lines produced by earlier tests in
/// the same file, and leak a listener for every widget that registered one
/// without being disposed.
///
/// Call once at the top of `main()`:
///
/// ```dart
/// void main() {
///   installAppLoggerTestIsolation();
///   ...
/// }
/// ```
void installAppLoggerTestIsolation() {
  setUp(AppLogger.instance.resetForTest);
  tearDown(AppLogger.instance.resetForTest);
}
