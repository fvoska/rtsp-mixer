# Test coverage analysis

**Measured:** 2026-07-25, against `1dcd015` (baseline) on Flutter 3.44.7 / Dart 3.12.2.
**How to reproduce:** `flutter test --coverage`, then read `coverage/lcov.info`.

This is a snapshot, not a policy. It exists so the next round of test work is
chosen from data instead of from whichever file someone happened to open.

---

## Baseline

| | Baseline (`1dcd015`) | After this round |
|---|---|---|
| Tests | 315, all passing | 336, all passing |
| Wall time | ~76s | ~86s |
| Line coverage | **46.3%** (1455 / 3145) | **48.3%** (1525 / 3158) |
| Lib source | 10,597 LOC across 48 files | |
| Test source | 3,924 LOC across 35 files | |

The +2pp is almost entirely `protect_api_client.dart` going 7.2% → 93.2%; the
rest of this round was flakiness work, which moves reliability without moving
the percentage. The gaps below are unchanged.

**46.3% overstates it.** lcov only reports files a test actually loaded. Nine
files totalling **1,915 LOC never load at all**, so they contribute nothing to
the denominator:

| File | LOC |
|---|---|
| `features/settings/screens/settings_screen.dart` | 385 |
| `features/help/screens/help_screen.dart` | 380 |
| `features/about/screens/about_screen.dart` | 373 |
| `features/monitoring/screens/sessions_list_screen.dart` | 281 |
| `features/auth/screens/login_screen.dart` | 216 |
| `core/router/app_router.dart` | 155 |
| `app.dart` | 98 |
| `main.dart` | 27 |
| `core/theme/spacing.dart` | 8 |

Counting those as zero puts real line coverage closer to **~38%**.

---

## Where the coverage is

Strong (≥90%), and these are the right things to have covered — they are the
reliability core:

| File | Coverage |
|---|---|
| `helpers/` (rtsp_url, stream_candidates, stream_liveness, audio_level_meter, pan_filter) | 73–100% |
| `services/reconnect_supervisor.dart` | 92.9% |
| `services/drift_watchdog.dart` | 95.2% |
| `services/alert_policy.dart` | 94.7% |
| `services/zombie_watchdog.dart` | 83.7% |
| `models/protect_camera.dart` | 100% |
| `about/changelog.dart` | 100% |

The reconnect/watchdog tests are also the best-written in the suite: they drive
`fake_async` rather than sleeping, so they assert on backoff schedules and
timer cancellation deterministically. **They are the model the rest of the
suite should follow.**

---

## Gaps, ranked

### 1. `providers/audio_player_provider.dart` — 0.6% (4 / 716 lines)

The single largest gap and the highest-stakes one. 1,917 LOC containing
`AudioPlayerNotifier`: player lifecycle, candidate-URL fallback, liveness
confirmation, the reconnect/watchdog wiring, quality switching, add/remove
camera, mix-state persistence. **This is the part of the app that must survive
eight hours unattended, and essentially none of it is tested.**

The existing `audio_player_provider_test.dart` covers only the value objects
(`CameraAudioState` / `MonitoringState` `copyWith`, `effectiveVolume`,
`addableCameras`). Those are worth having but they are not the notifier.

Why it is untested: `_createPlayer()` constructs `media_kit`'s `Player`
directly, which needs native libraries, so no unit test can enter
`startMonitoring`. The fix is a seam, not more tests:

- Extract a narrow interface over the handful of `Player` members actually used
  (`open`, `stop`, `dispose`, `setVolume`, the state streams, and the
  `NativePlayer.setProperty`/`getProperty` calls).
- Inject a factory (`Player Function()`) via a Riverpod provider so tests can
  override it with a fake.
- Then test, in order of value: candidate fallback ordering, liveness
  confirmation accept/reject, reconnect status transitions,
  `stopMonitoring` teardown completeness, `removeCamera` mid-session index
  handling, and the "no exception may kill a stream" contract — assert that a
  throwing `setProperty` leaves audio playing.

That last one is a direct test of the invariant CLAUDE.md is built around and
there is currently nothing enforcing it.

### 2. Nothing ran the tests

Until this round there was **no CI workflow invoking `flutter test`**. The repo
had `conventional-commits.yml`, `release.yml` and `setup-signing-key.yml` — a
red suite could reach `main` unnoticed. Fixed by `.github/workflows/tests.yml`;
it still needs to be added as a **required status check** on the `main` branch
protection rule to actually block a merge.

### 3. Session persistence — `session_history_provider.dart` 33.7%, `session_history_repository.dart` 37.1%

What the parent looks at in the morning to see whether the night went cleanly.
`sessionHistoryRepositoryProvider` is already injectable and documented
"overridden in tests" — but **no test overrides it**. The percentages come
purely from incidental loading by widget tests.

Untested and worth testing (all cheap, the seam exists):

- `beginSession` / `recordEvent` / `endCurrentSession` state transitions.
- The 1s write debounce, and the flush on `AppLifecycleState.paused|detached` —
  the mechanism that stops a session record being lost when Android kills the
  app. This is exactly what `fake_async` is for.
- `past` trimming to `maxPast = 100`.
- Corrupt-file recovery: the repository promises that malformed JSON, a
  malformed `endedAt`, and malformed event/camera entries degrade to empty or
  get dropped with a log rather than throwing. That promise has no test.
- The atomic `.tmp` + rename write.

### 4. `models/session.dart` — 25%

`Session.fromJson` is deliberately tolerant (drops malformed events, keeps
going) and that tolerance is entirely untested. Pure functions, no seam
needed — this is the cheapest real coverage available in the repo.

### 5. Platform services — 0%

`services/audio_handler.dart` (41 lines), `core/services/foreground_service.dart`
(38), `core/services/local_notifications.dart` (21). Each wraps a plugin, so
testing means mocking platform channels. Lower value per line than the above,
but `foreground_service` is what keeps the app alive overnight, so at minimum
the notification-text construction and the start/stop guards are worth pulling
into pure functions that can be tested without a channel.

### 6. Screens with zero coverage

`settings` (385), `help` (380), `about` (373), `sessions_list` (281),
`login` (216). `monitoring_screen.dart` (39.3%) and
`health_summary_screen.dart` (76.1%) show the pattern that works here — a
`_pump…` helper with faked notifiers. Extracting that harness into
`test/support/` would make the remaining screens cheap to smoke-test
(renders without throwing, at 360dp and 800dp, no `ErrorWidget`).

`app_router.dart` (0%) is worth one test on its own: the redirect logic that
decides login-vs-shell is the first thing a user hits.

---

## Flakiness and timing hazards

Most of the below is not a currently-observed failure — the suite was green on 5
consecutive full runs and stayed green under CPU contention (16 busy loops on 4
cores). They are hazards that pass on timing rather than on state.

**One was a real, reproducible flake, and CI found it on the very first run of
the new workflow.** `per_camera_cancel_test.dart` asserted
`expect(attempts, ['cam1', 'cam2'])` after elapsing past the first backoff for
two cameras. `computeBackoff` applies ±20% jitter and the supervisor was built
without a seed, so each camera's first retry landed anywhere in 800–1200ms and
whichever drew the smaller jitter fired first — the CI log showed cam1 at 1178ms
against cam2 at 1058ms. Measured **3 failures in 24 runs (~12.5%)**; at that
rate a full suite passes ~45% of the time across six runs, which is exactly why
six consecutive green local runs never surfaced it. 0 failures in 30 runs after
seeding the `Random` and making the precondition order-insensitive.

Worth noting for anyone tempted by affected-test selection: that test imports
only `reconnect_supervisor.dart`, a file the branch that found it never touched.
Any change-graph-based test selection would have skipped it.

### Fixed — this round

| Hazard | Was | Now |
|---|---|---|
| `auth_provider_test` waiting on background validation | `await Future.delayed(Duration(seconds: 3))` ×2, for a hard-coded 2s timer — 1s of slack, 6s of suite time | `AuthNotifier.backgroundValidationDelay` is injectable; tests set it to zero and wait on the state transition |
| `camera_provider_test:169` asserting a fire-and-forget write | `Future.delayed(50ms)` then read storage | `waitForAsyncValue` polls until the write lands |
| Hand-rolled poll loops (4 sites) | `for (i < 100) { …; await Future.delayed(10ms) }`, expiring silently so the *next* assertion failed with `Expected: 4 Actual: 1` | `waitFor(predicate, reason:)` throws naming the condition that never came true |
| `active_session_bar_test` uptime fixture | `DateTime.now() - 7min` asserted against exactly `"Monitoring · 7m"` — on the bucket edge, zero slack | anchored 7m30s back; `inMinutes` floors, so ±30s of drift still reads `7m` |
| `AppLogger` file sink during tests | every log line a synchronous append to the fixed path `/tmp/rtsp_mixer.log`, shared by concurrently-running test processes | sink off under `FLUTTER_TEST`; `resetForTest()` + `installAppLoggerTestIsolation()` for the global buffer and listener list |
| `ProtectApiClient.setDioForTest` | `late final Dio _dio` assigned in the constructor → `LateInitializationError` on every call. The only seam was dead by construction | fixed to `late Dio`; client coverage 7.2% → 93.2% |
| `per_camera_cancel_test` attempt order | `expect(attempts, ['cam1', 'cam2'])` against a jitter-decided firing order, unseeded `Random` — ~12.5% failure rate, found by CI | seeded `Random(42)` + `unorderedEquals`; the two other unseeded supervisor constructions seeded prophylactically |

One note on method, because it cost a round trip: collapsing
`backgroundValidationDelay` to zero *by itself* made the revoke test flaky in
the opposite direction — validation could now land before the test observed the
cached-authenticated state, so `expect(state.isAuthenticated, true)` failed
under a full-suite run while passing in isolation. Removing a sleep is not
enough; the ordering the test depends on has to be made explicit. The fake API
client now gates `verifyConnection` on a `Completer` the test releases after
asserting, which pins the order without any wall clock.

### Open — not fixed here

**`pumpAndSettle` is a trap on any tree containing a connecting camera card.**
`camera_audio_card.dart` renders `CircularProgressIndicator` /
`LinearProgressIndicator` with no `value` for the connecting and reconnecting
states. Those animate forever, so `pumpAndSettle` spins to its 10-minute
timeout instead of settling. The existing tests dodge it with
`await tester.pump(const Duration(milliseconds: 50))` and a comment
(`camera_audio_card_test.dart:30`), which works but is folklore — the next test
that reaches for `pumpAndSettle` on a connecting card will appear to hang.
Worth either a shared `pumpCard(tester)` helper in `test/support/` or driving
the indicators from a bounded animation.

**`ActiveSessionBar` runs an unconditional `Timer.periodic(1s)`** for its pulse
dot, started in `initState` even when the bar renders as
`SizedBox.shrink()`. Combined with an 800ms `AnimatedOpacity`, whether a
`pumpAndSettle` on a tree containing `MainShell` terminates depends on where
the accumulated virtual clock happens to fall relative to the 1s tick.
`main_shell_test` works today; it is not robust by construction. Gating the
timer on actual visibility would remove the hazard outright.

**`StorageService` tests depend on an implicit failure path.** They pass because
`FlutterSecureStorage` throws without a binding, so every call silently falls
back to a per-instance in-memory map. That means the tests never exercise the
secure path, and "returns null when nothing saved" is really asserting that a
fresh fallback map is empty. Worth an explicit fake instead of relying on the
plugin failing.

**`test/features/monitoring/rtsp_url_test.dart` and
`test/features/monitoring/helpers/rtsp_url_test.dart`** are two different files
with the same basename testing the same library (likewise
`test/features/cameras/camera_model_test.dart` and
`.../cameras/models/camera_model_test.dart`). Not a bug — the contents differ
and both are real — but it makes "where is this tested" ambiguous. Consolidate
into the `helpers/` and `models/` paths.

---

## Suggested order

1. Add `tests.yml` as a required status check — the rest is unenforced without it.
2. `Session.fromJson` tolerance tests. Pure, cheap, currently 25%.
3. Session history provider + repository through the existing injectable seam, with `fake_async` for the debounce and lifecycle flush.
4. Extract the `Player` seam in `audio_player_provider.dart` and start with the reconnect/liveness paths. Biggest effort, biggest risk reduction.
5. A shared screen-pump harness in `test/support/`, then smoke tests for the five uncovered screens and the router redirect.
6. Close out the two open `pumpAndSettle` hazards above.
