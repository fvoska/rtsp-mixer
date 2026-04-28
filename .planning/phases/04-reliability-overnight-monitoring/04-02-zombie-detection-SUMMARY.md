---
phase: 04-reliability-overnight-monitoring
plan: 02
status: complete
requirements: [RELY-03]
type: summary
---

# Plan 04-02 — Zombie Stream Detection (RELY-03)

## What was built

A four-signal quorum watchdog (`ZombieWatchdog`) that detects the
TCP-open-but-no-audio failure mode where `player.stream.error` never
fires but audio data has stopped flowing. When ≥2 of the 4 signals
cross a hardcoded 60s threshold, it forces a reconnect via the
Wave-1 `ReconnectSupervisor` — silently, with no user-visible toast.

## Signal feed sites (4 wiring locations in `audio_player_provider.dart`)

| Signal | Site | Positive feeder |
|--------|------|-----------------|
| audio-pts stall (weight 2) | `_pollAudioLevels` after `flowing` is computed | `recordPtsAdvance` when `flowing` |
| buffering stuck (weight 1) | `player.stream.buffering` listener | `recordBufferingFalse` on `!buffering` |
| bitrate=0 (weight 1) | `_pollAudioLevels` after `audioBitrate` parse | `recordBitrateNonZero` when `audioBitrate > 0` |
| no audioParams (weight 1) | `player.stream.audioParams` listener | `recordAudioParams` every event |

All four positive feeders run **before** `tick(cam.cameraId, 500)`,
which executes once per camera per poll pass at the end of the
`_pollAudioLevels` per-camera try block.

## Quorum weighting

Per RESEARCH.md §Section 5 + D-06:
- PTS stall: weight **2** (advances even during legitimate silence — hard signal)
- buffering / bitrate=0 / no audioParams: weight **1** each
- Fire threshold: score **≥ 2**

This means PTS-stall **alone** triggers, OR any two of the weak
signals combined. `bitrate=0` alone (legitimate at stream start) does
NOT fire — confirmed by unit test 3.

## Latch behaviour

`_fired[cameraId]` prevents the watchdog from re-firing every 500ms
tick while the zombie condition persists. Fire-latch clears
automatically when `zombieScore` drops back below 2 (typically after
a successful reconnect resumes positive signals). Unit test 9 asserts
exactly one fire per zombie episode, even after 125 ticks.

## Reset ordering

| Trigger | Where | Why |
|---------|-------|-----|
| Successful reconnect | `_applyReconnectStatus` when status becomes `playing` | Zero counters so the next zombie can fire fresh |
| `stopMonitoring()` | After `_reconnectSupervisor.cancelAll()` | Match supervisor teardown ordering (T-04-08) |
| `ref.onDispose()` | Alongside `_reconnectSupervisor.cancelAll()` | Clean shutdown when notifier disposes |

`reconnecting` status keeps counters running so a wedged reconnect
doesn't re-fire prematurely.

## Defensive error handling

Per CLAUDE.md §Conventions: every watchdog call site
(`recordBufferingFalse`, `recordAudioParams`, `recordPtsAdvance`,
`recordBitrateNonZero`, `tick`, `reset`, `resetAll`) is individually
wrapped in try/catch with `appLog('ZOMBIE', ...)` + continue. The
outer per-camera `try/catch` in `_pollAudioLevels` is the safety net.
The `onFire` callback inside the watchdog also wraps the user-supplied
function in try/catch — no exception path can tear down the audio
stream.

## Key files

| File | Status | Purpose |
|------|--------|---------|
| `lib/features/monitoring/services/zombie_watchdog.dart` | created | 4-signal tracker + quorum logic |
| `lib/features/monitoring/providers/audio_player_provider.dart` | modified | 8 wiring edits (field + 7 sites) |
| `test/features/monitoring/zombie/quorum_test.dart` | created | 9 unit tests (Task 1) |

## Verification

- `flutter analyze --no-preamble lib test` → 0 new issues (5 pre-existing warnings unchanged)
- `flutter test test/features/monitoring/zombie/quorum_test.dart` → 9/9 pass
- `flutter test` → 100/100 pass (no regressions)

## Commits

- `3b86e0f` — feat(04-02): add ZombieWatchdog service with quorum signal detection (Task 1, in worktree, merged via `5f30009`)
- `5f30009` — chore: merge executor worktree (worktree-agent-aa03ab63) — plan 04-02 task 1
- `02388e9` — feat(04-02): wire ZombieWatchdog into AudioPlayerNotifier (Task 2, finished inline on main after worktree was blocked by a Read-before-Edit hook race)

## Self-Check: PASSED

All `<acceptance_criteria>` predicates from the plan satisfy. No new
analyze warnings, no test regressions, all 9 zombie unit tests + the
full 100-test suite pass.

## Notable deviations

- **Worktree execution interrupted.** The Wave 2 parallel executor for
  04-02 hit a stateful Read-before-Edit hook on
  `audio_player_provider.dart` after Task 1 completed. Task 1 (service
  + tests) committed cleanly in the worktree. Task 2 (provider wiring)
  was finished by the orchestrator inline on main after merging the
  worktree. The wiring matches the plan's Step A–H exactly; the
  divergence is purely about *who* applied the edits.
