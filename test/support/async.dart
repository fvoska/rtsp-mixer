import 'dart:async';

/// Deadline-based waiting for asynchronous test conditions.
///
/// Replaces two patterns that were spread across the provider tests:
///
///   1. `await Future.delayed(const Duration(milliseconds: 50));` followed by
///      an assertion on state produced by an un-awaited future. That passes
///      only while the machine is fast enough — it is a race, not a wait.
///
///   2. Hand-rolled `for (var i = 0; i < 100; i++) { ...; await
///      Future.delayed(10ms); }` loops. These do poll, but they expire
///      silently: the loop just ends and the *next* assertion fails with
///      something like `Expected: <4> Actual: <1>`, which says nothing about
///      the fact that the wait timed out.
///
/// Both are replaced by [waitFor], which polls a predicate until a deadline
/// and then throws a [TimeoutException] naming the condition that never came
/// true.
const _defaultTimeout = Duration(seconds: 5);
const _defaultPollInterval = Duration(milliseconds: 5);

/// Poll [predicate] until it returns true, or throw after [timeout].
///
/// [reason] describes the condition in the present tense ("cameras have RTSPS
/// URLs") and is quoted verbatim in the timeout message, so a failure says
/// what never happened instead of just surfacing the downstream assertion.
///
/// The timeout defaults to 5s — generously above what any of these
/// in-memory-fake tests need, because the point of a deadline is to fail with
/// a good message eventually, not to be a tight timing assertion. Anything
/// that legitimately takes longer wants a fake clock, not a longer deadline.
Future<void> waitFor(
  bool Function() predicate, {
  required String reason,
  Duration timeout = _defaultTimeout,
  Duration pollInterval = _defaultPollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (predicate()) return;
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException(
        'Timed out after ${timeout.inMilliseconds}ms waiting until: $reason',
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// [waitFor] for a value: poll [read] until it returns a non-null value and
/// return it, or throw after [timeout].
///
/// Use this when the assertion needs the value that arrived, not just the fact
/// that it did — it saves re-reading the source after the wait.
Future<T> waitForValue<T extends Object>(
  T? Function() read, {
  required String reason,
  Duration timeout = _defaultTimeout,
  Duration pollInterval = _defaultPollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = read();
    if (value != null) return value;
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException(
        'Timed out after ${timeout.inMilliseconds}ms waiting for: $reason',
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// [waitForValue] over an async read — for conditions that live behind a
/// `Future`, e.g. "the fire-and-forget write reached secure storage".
Future<T> waitForAsyncValue<T extends Object>(
  Future<T?> Function() read, {
  required String reason,
  Duration timeout = _defaultTimeout,
  Duration pollInterval = _defaultPollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException(
        'Timed out after ${timeout.inMilliseconds}ms waiting for: $reason',
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}
