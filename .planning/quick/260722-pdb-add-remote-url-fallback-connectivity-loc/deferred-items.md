# Deferred Items — 260722-pdb

## Flaky test: per_camera_cancel_test.dart

**Discovered during:** Task 3 verification (full `flutter test` run)
**Test:** `test/features/monitoring/reconnect/per_camera_cancel_test.dart` — "cancels the pending retryTimer for that camera only"
**Symptom:** Intermittent failure (~50% over 4 isolated runs on identical code: pass, fail, pass, fail). When it fails, the log shows the camera's retry being rescheduled with randomized jitter backoff and the forced `StateError('keep failing')` escaping as an uncaught zone error inside `fakeAsync` (`ReconnectSupervisor._attemptReconnect` → `FakeTimer._fire` runGuarded).
**Assessment:** Pre-existing flakiness in the reconnect supervisor's randomized backoff jitter interacting with the test's fixed `elapse(2s)` window / unguarded rethrow inside the fake-async zone. None of the files changed by 260722-pdb (`player_state.dart`, `audio_player_provider.dart`, UI screens) are exercised by this test; `reconnect_supervisor.dart` was not modified.
**Suggested fix (future):** Seed or clamp the jitter in tests, or have the test tolerate attempt timing by elapsing past the max backoff, and swallow the intentional `StateError` via `runZonedGuarded`/expected-error handling.
