---
phase: quick-260514-siv
plan: 01
type: execute
status: complete
requirements:
  - QUICK-260514-SIV
commits:
  - b7a0922 # Task 1: feat(session-history): persist sessions across restart
  - b456006 # Task 2: feat(nav): shell with bottom NavigationBar + sessions list
  - 3f5f0c6 # Task 3: feat(session-history): persistent active-session mini-bar
---

# 260514-siv — Session History + Shell Navigation

Persist a rolling 10-session history to disk and rework post-login navigation
around a persistent bottom NavigationBar so tab switches no longer tear down
the monitoring pipeline.

## Final file list (line counts)

| File                                                                   | LOC |
| ---------------------------------------------------------------------- | --- |
| lib/features/monitoring/models/health_event.dart                       |  55 |
| lib/features/monitoring/models/session.dart                            | 129 |
| lib/features/monitoring/services/session_history_repository.dart       | 106 |
| lib/features/monitoring/providers/session_history_provider.dart        | 228 |
| lib/features/monitoring/providers/health_events_provider.dart          |  51 |
| lib/features/monitoring/providers/audio_player_provider.dart           | 1142 (+~40) |
| lib/features/monitoring/screens/monitoring_screen.dart                 | 253 |
| lib/features/monitoring/screens/health_summary_screen.dart             | 476 |
| lib/features/monitoring/screens/sessions_list_screen.dart              | 281 |
| lib/features/monitoring/widgets/stop_monitoring_button.dart            |  46 (deprecated) |
| lib/features/monitoring/widgets/active_session_bar.dart                | 131 |
| lib/core/router/app_router.dart                                        | 110 |
| lib/core/widgets/main_shell.dart                                       |  89 |
| test/features/monitoring/screens/health_summary_screen_test.dart       | rewritten |
| pubspec.yaml                                                           | +1 dep (path_provider ^2.1.5) |

Total touched in this plan: ~3.1k LOC including the rewritten HealthSummaryScreen
and the new shell. Sizes are within the planner's expectations — nothing got
unexpectedly fat.

## Decisions

### (a) Repository location — `lib/features/monitoring/services/`

Considered: introducing a new `lib/features/sessions/` feature folder.

Chose `lib/features/monitoring/services/` because Session is conceptually a
monitoring-domain entity (it owns HealthEvents and CameraAudioState IDs).
Splitting it into its own feature would force `monitoring` to import from
`sessions` and vice versa, adding a circular-import risk. If a future plan
adds session-level features beyond what the monitoring feature already does
(export, sharing, multi-session comparison), splitting becomes worthwhile —
not yet.

### (b) Event forwarding vs derived state

Considered: making `healthEventsProvider` a derived selector over
`sessionHistoryProvider.current.events`.

Chose forwarding (`HealthEventsNotifier.record` → `sessionHistoryProvider.recordEvent`)
because:
1. Lower blast radius — existing call sites for `healthEventsProvider.record`
   keep working with no changes. The derived approach would force renumbering
   every caller and rewriting the unit tests.
2. The two providers serve different consumers: `healthEventsProvider` is the
   live-UI source of truth this session; `sessionHistoryProvider` is the
   persistent source of truth across sessions. Decoupling them lets the live
   provider stay capped at 1000 events while the persisted session can hold
   the full set.
3. Migration path is open — a future cleanup can collapse the two via a
   `select` if the duplication starts hurting.

This decision is also documented inline in `health_events_provider.dart`.

## Deviations from plan

### 1. `beginSession` called BEFORE the `clear/record(monitoringStarted)` block (not after)

The plan said "immediately after the existing `healthEventsProvider.notifier.clear()`
+ record(monitoringStarted) block at lines 303–312, call beginSession(...)". I
moved the call to BEFORE that block. Reason:

`sessionHistoryProvider.recordEvent` no-ops when `current == null`. If
`beginSession` runs AFTER `record(monitoringStarted)`, the `monitoringStarted`
event is dropped on the floor and the persisted session has an empty
`events: []` list — the user can never tell from history that the session
actually started, and downtime/uptime calculations break on the missing
sentinel event.

Order in committed code (audio_player_provider.dart):
1. idempotency guard
2. `state = const AsyncLoading()`
3. `beginSession(cameras)` ← persistence opens its window
4. `healthEventsProvider.clear()` ← reset the live list
5. `healthEventsProvider.record(monitoringStarted)` ← forwarded into the session

This still meets every "done" criterion in the plan and matches the
must_haves.truths: "After stopping monitoring the just-ended session is still
viewable as a finalized session" — required `monitoringStarted` to actually be
in the session events.

### 2. Riverpod-3 dispose flush rewrite — surfaced as a Task 2 fix

The plan's `SessionHistoryNotifier` design has `onDispose` reading `state.value`
and calling `ref.read(sessionHistoryRepositoryProvider).save(...)`. Riverpod 3
forbids both of those inside the dispose callback (`Cannot use Ref or modify
other providers inside life-cycles/selectors`).

Discovered when running the full test suite after Task 1 — the existing
`event_stream_cap_test` triggers `onDispose` and immediately tripped the
Riverpod assertion. Fix:

- Added two snapshot fields: `SessionHistory? _latest` and
  `SessionHistoryRepository? _repo`. Both are populated in `build()` and kept
  in sync via a `_setState(SessionHistory next)` helper that updates both
  `_latest` and `state` together.
- `flush()`, `beginSession()`, `recordEvent()`, `endCurrentSession()` now
  read from `_latest` instead of `state.value` so they all touch the same
  source.
- `onDispose` uses the captured `_latest` + `_repo` snapshots — no ref/state
  access inside the callback.

This is the only behavioral deviation from the planner's pseudo-code in
`session_history_provider.dart`. Committed alongside Task 2 (with rationale
in the commit message) because that's when the test failure surfaced; arguably
it belonged in Task 1.

### 3. `CameraConnectionStatus.connected` does not exist

The plan's idempotency-guard snippet references
`CameraConnectionStatus.connected`. The actual enum is
`{ idle, connecting, playing, reconnecting, error }`. Substituted `playing`
(plus added `reconnecting` since a reconnecting session is also still in
flight). Documented inline in `audio_player_provider.dart`.

### 4. HealthSummaryScreen copy changes

Empty state title changed from "Monitoring just started" to "No events
recorded" — the old copy made sense when the screen was only used for the
in-flight session, but it's confusing when viewing a stopped session from
history that simply had nothing happen. The finalized-session banner copy
also changed from "Monitoring stopped. Start monitoring to reset the session."
to "Session finalized." — same reason; the old copy presumes the user is about
to start a new session, which isn't true for past-session views.

The widget test (`health_summary_screen_test.dart`) was rewritten to match.

### 5. HealthSummaryScreen `_SessionUptimeCard` shows "Session duration" (not "Session uptime") for finalized sessions

Minor — the label switches based on `session.endedAt`. Live sessions still
read "Session uptime"; finalized sessions read "Session duration". This is
under the planner's discretion umbrella ("Title can show the session date").

### 6. Test file rewrite scope

The plan only listed `lib/` files in `<files>` for each task, but Task 2's
HealthSummaryScreen refactor breaks the existing widget test
(`HealthSummaryScreen()` no longer takes zero args). Rewrote the test to
construct `Session` fixtures directly — this is Rule 3 (auto-fix blocking
issue: existing test won't compile). The new tests cover the same surfaces
(empty state, event order, banner, label copy, null-cameraName fallback)
plus two new cases (in-flight vs finalized label). Committed in Task 2.

## Verification

- `flutter analyze lib`: **zero errors, zero warnings** across all three tasks.
- `flutter analyze` (lib + test): zero errors. 5 pre-existing warnings in
  `test/features/auth/*` and `test/features/cameras/*` —
  `unnecessary_non_null_assertion`. Not introduced by this plan.
- `flutter test`: **116 / 116 tests pass** after Task 3. Including the
  rewritten HealthSummaryScreen tests and the event-stream-cap regression
  that surfaced the Riverpod-3 dispose issue.

## Known follow-ups

- **Delete `stop_monitoring_button.dart`** once no usages remain. Already
  marked `@Deprecated`; the only file referencing it is itself.
- **Unit test for `SessionHistoryRepository` corrupt-file path** — load() and
  save() need explicit coverage of: missing file, empty file, malformed JSON,
  malformed `events[]`, malformed `cameras[]`, write failure, atomic rename
  collision. Not blocking — the production paths log and degrade as designed,
  but tests would lock the behavior down.
- **Collapse `healthEventsProvider` into a select over `sessionHistoryProvider`**
  once the rest of the app reads only from `session.events`. Today the two
  are kept in sync via forwarding; that's a small ongoing duplication.
- **MonitoringScreen `initState` startMonitoring()** still fires on every
  mount — the idempotency guard makes it safe, but it adds a wasted ref.read
  + log line each time the tab is re-entered. Consider gating on
  `ref.read(sessionHistoryProvider).value?.current == null` at the call site
  for cleanliness.
- **`_StoppedSessionBanner` always shown for finalized sessions** — currently
  the screen renders the banner whenever `session.endedAt != null` OR the
  last event is `monitoringStopped`. Slightly redundant; trim in cleanup.

## Self-Check: PASSED

Created files exist:
- `lib/features/monitoring/models/session.dart` — FOUND
- `lib/features/monitoring/services/session_history_repository.dart` — FOUND
- `lib/features/monitoring/providers/session_history_provider.dart` — FOUND
- `lib/features/monitoring/screens/sessions_list_screen.dart` — FOUND
- `lib/features/monitoring/widgets/active_session_bar.dart` — FOUND
- `lib/core/widgets/main_shell.dart` — FOUND

Commits exist on `main`:
- `b7a0922` — FOUND (Task 1)
- `b456006` — FOUND (Task 2)
- `3f5f0c6` — FOUND (Task 3)
