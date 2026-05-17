import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../models/health_event.dart';
import '../models/session.dart';
import '../services/session_history_repository.dart';

/// Immutable snapshot of session history.
///
/// `current` is the in-flight session (or null if no session is running).
/// `past` is the list of finalized sessions, most-recent first, max length 100.
class SessionHistory {
  final Session? current;
  final List<Session> past;

  const SessionHistory({this.current, this.past = const []});

  SessionHistory copyWith({
    Object? current = _sentinel,
    List<Session>? past,
  }) =>
      SessionHistory(
        current: current == _sentinel ? this.current : current as Session?,
        past: past ?? this.past,
      );

  static const Object _sentinel = Object();
}

/// Injectable repository — overridden in tests.
final sessionHistoryRepositoryProvider =
    Provider<SessionHistoryRepository>((_) => SessionHistoryRepository());

/// Provider for the persistent session history.
///
/// Responsibilities:
/// - load from disk on first build
/// - expose [beginSession] / [recordEvent] / [endCurrentSession]
/// - debounce disk writes by 1s
/// - flush on `AppLifecycleState.paused` / `detached`
/// - flush on dispose
///
/// All disk operations are wrapped — failures log via `appLog('SESSION', ...)`
/// and degrade silently. The audio pipeline must never see an exception bubble
/// up from this provider (CLAUDE.md "no exception may kill a running audio stream").
class SessionHistoryNotifier extends AsyncNotifier<SessionHistory> {
  Timer? _debounce;
  _LifecycleListener? _lifecycleListener;

  /// Snapshot kept in sync with [state] so we can flush from `onDispose`,
  /// where Riverpod 3 forbids reading `state` or other providers.
  SessionHistory? _latest;

  /// Captured at build() time so onDispose doesn't need to call ref.read.
  SessionHistoryRepository? _repo;

  static const _debounceDuration = Duration(seconds: 1);

  @override
  Future<SessionHistory> build() async {
    final repo = ref.read(sessionHistoryRepositoryProvider);
    _repo = repo;
    final loaded = await repo.load();
    appLog('SESSION',
        'build: loaded current=${loaded.current?.id ?? 'null'} past=${loaded.past.length}');

    // Register a lifecycle observer so we flush before the OS kills us.
    final listener = _LifecycleListener((s) {
      if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) {
        appLog('SESSION', 'lifecycle=$s — flushing');
        // Fire and forget; flush itself never throws.
        flush();
      }
    });
    _lifecycleListener = listener;
    try {
      WidgetsBinding.instance.addObserver(listener);
    } catch (e) {
      appLog('SESSION', 'addObserver failed (test env?): $e');
    }

    ref.onDispose(() {
      _debounce?.cancel();
      try {
        if (_lifecycleListener != null) {
          WidgetsBinding.instance.removeObserver(_lifecycleListener!);
        }
      } catch (e) {
        appLog('SESSION', 'removeObserver failed: $e');
      }
      // Best-effort flush on dispose. Uses captured _latest + _repo because
      // Riverpod 3 disallows touching state or ref.read inside onDispose.
      final s = _latest;
      final r = _repo;
      if (s != null && r != null) {
        // Fire and forget — provider is being torn down.
        r.save(current: s.current, past: s.past);
      }
    });

    final initial = SessionHistory(current: loaded.current, past: loaded.past);
    _latest = initial;
    return initial;
  }

  /// Update both [state] and the [_latest] snapshot in one place so they
  /// don't drift.
  void _setState(SessionHistory next) {
    _latest = next;
    state = AsyncData(next);
  }

  /// Begin a new session for [cameras]. If a session is already in flight,
  /// this is a no-op with a warning log (defense in depth — the canonical
  /// idempotency guard lives in `audio_player_provider.startMonitoring`).
  Future<void> beginSession(List<({String id, String name})> cameras) async {
    try {
      final cur = _latest;
      if (cur?.current != null) {
        appLog('SESSION',
            'beginSession called while session ${cur!.current!.id} is in flight — noop');
        return;
      }
      final session = Session.start(cameras: cameras);
      appLog('SESSION',
          'beginSession id=${session.id} cameras=${cameras.length}');
      _setState(SessionHistory(
        current: session,
        past: cur?.past ?? const [],
      ));
      _scheduleFlush();
    } catch (e, st) {
      appLog('SESSION', 'beginSession failed: $e; stack=$st');
    }
  }

  /// Append [e] to the current session. No-op if no session is running.
  void recordEvent(HealthEvent e) {
    try {
      final cur = _latest;
      final session = cur?.current;
      if (session == null) {
        // Pre-session events (e.g., from a notifier wired before startMonitoring)
        // are dropped by design — they have no session to belong to.
        return;
      }
      _setState(cur!.copyWith(
        current: session.withEventAppended(e),
      ));
      _scheduleFlush();
    } catch (err, st) {
      appLog('SESSION', 'recordEvent failed: $err; stack=$st');
    }
  }

  /// Move the current session into `past` (trimmed to [SessionHistoryRepository.maxPast])
  /// and clear `current`.
  /// Awaits a synchronous flush so the freshly-ended session is on disk before
  /// the caller proceeds (Stop button + restart-and-see-history flow).
  Future<void> endCurrentSession() async {
    try {
      final cur = _latest;
      final session = cur?.current;
      if (session == null) {
        appLog('SESSION', 'endCurrentSession: no current session — noop');
        return;
      }
      final ended = session.ended();
      final newPast = [ended, ...(cur!.past)];
      final trimmed = newPast.length > SessionHistoryRepository.maxPast
          ? newPast.sublist(0, SessionHistoryRepository.maxPast)
          : newPast;
      appLog('SESSION',
          'endCurrentSession id=${ended.id} events=${ended.events.length}');
      _setState(SessionHistory(
        current: null,
        past: trimmed,
      ));
      // Cancel any pending debounce and write through immediately.
      _debounce?.cancel();
      _debounce = null;
      await flush();
    } catch (e, st) {
      appLog('SESSION', 'endCurrentSession failed: $e; stack=$st');
    }
  }

  /// Cancel any pending debounce and write the current state to disk.
  /// Never throws — repository swallows IO errors and logs them.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    final s = _latest;
    final r = _repo;
    if (s == null || r == null) return;
    try {
      await r.save(current: s.current, past: s.past);
    } catch (e, st) {
      appLog('SESSION', 'flush: unexpected error ($e); stack=$st');
    }
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      flush();
    });
  }
}

/// Internal helper: AsyncNotifier can't be a WidgetsBindingObserver directly
/// (per the plan's critical constraint #5 — mixin needs a class).
class _LifecycleListener with WidgetsBindingObserver {
  _LifecycleListener(this._onLifecycle);
  final void Function(AppLifecycleState) _onLifecycle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onLifecycle(state);
  }
}

final sessionHistoryProvider =
    AsyncNotifierProvider<SessionHistoryNotifier, SessionHistory>(
  SessionHistoryNotifier.new,
);
