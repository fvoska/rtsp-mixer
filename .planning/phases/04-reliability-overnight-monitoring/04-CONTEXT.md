# Phase 4: Reliability + Overnight Monitoring - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Make overnight monitoring *trustworthy*. The app must:
1. Silently auto-reconnect any dropped RTSP stream (RELY-01)
2. Show clear per-camera connection status the parent can interpret at a glance (RELY-02)
3. Detect zombie streams — TCP open but no audio data arriving — and force a reconnect (RELY-03)
4. Surface an overnight health summary (uptime, reconnection count, stream health events) (MNTR-01)

No new listening capabilities. No new audio features. This phase hardens what Phases 1–3 built so the parent can fall asleep trusting the app is still listening.

</domain>

<decisions>
## Implementation Decisions

### Auto-Reconnect (RELY-01)

- **D-01:** Reconnect backoff is **exponential capped** at 30s: 1s → 2s → 4s → 8s → 16s → 30s → 30s … with **±20% jitter** to avoid thundering-herd behavior when two cameras drop simultaneously (e.g., WiFi AP reboot affects both).
- **D-02:** **Retry forever** — the app never gives up on its own. This is a baby monitor; silently surrendering while the parent sleeps defeats the core value. The reconnect loop continues indefinitely until the user stops monitoring.
- **D-03:** Reconnect triggers are combined — the loop must run on **any** of: (a) `Player.stream.error` / `completed` events, (b) zombie detector firing (see D-07), (c) WiFi reconnect event via `connectivity_plus`. Researcher MUST enumerate **all realistic RTSP interruption modes** and verify each path leads to a reconnect attempt. Non-exhaustive: Unifi Protect controller updates, UDM Pro firmware updates, camera firmware/NVR updates, camera power cycles, WiFi access-point reboots/firmware updates, WiFi router reboots, LAN cable disconnects, phone WiFi drops, phone airplane-mode toggles.
- **D-04:** A **local push notification** fires per-camera when a camera has been in a non-`playing` state for **5 continuous minutes**. Purpose: wake the parent so they can investigate. Scope is **per camera** (each camera has its own 5-min timer — if nursery goes down at 01:00 and bedroom at 01:02, two separate notifications fire). Alert is **one-shot per outage cycle** — fires once when threshold crosses, does NOT re-nag during continued outage. The alert-fired flag resets when that camera returns to `playing`.

### Zombie Stream Detection (RELY-03)

- **D-05:** Zombie threshold is **60 seconds** of no audio-pts advance. Rationale: healthy RTSP/RTSPS over TCP should never stall this long during normal operation; 60s is past any reasonable buffering or keepalive window, and it's short enough that the parent only misses up to 60s of audio before forced recovery kicks in.
- **D-06:** Zombie detection uses **four signals combined** (belt-and-suspenders coverage):
  1. `audio-pts` stall — PTS not advancing for 60s (existing `_lastAudioPts` tracking in `audio_player_provider.dart`)
  2. `Player.stream.buffering` stuck `true` for 60s (distinct failure mode — player knows it's starved but can't recover)
  3. `audio-bitrate` sustained at 0 alongside PTS stall
  4. No new `Player.stream.audioParams` events for 60s (catches silent stream reinitialization)
  Any one signal crossing the threshold triggers reconnect; the planner decides whether these are ORed or require a quorum. Planner must pick the approach that minimizes false-positive reconnects without missing real zombies.
- **D-07:** On zombie detection, **force reconnect silently** — set status to `reconnecting`, kick off the exponential backoff loop (D-01). Log the zombie event to the health summary stream (D-12). No user-visible toast or error — failure recovery should not wake the parent unless D-04's 5-min alert fires.
- **D-08:** Zombie threshold is **hardcoded**, not user-configurable for v1. Not exposed in `AppSettings`. Can be promoted to a debug-mode-only control later if field testing shows the 60s default is wrong.

### Connection Status UI (RELY-02)

- **D-09:** Expand `CameraConnectionStatus` enum to: `idle | connecting | playing | reconnecting | error`. Semantic split — `connecting` = first-attempt after `startMonitoring`, `reconnecting` = post-drop retry while player infrastructure persists. Error state is terminal for the current attempt but NOT for the monitoring session (retry loop keeps running).
- **D-10:** Reconnecting state renders as **amber tint + small spinner** on the camera card header. Distinct from `connecting` (currently blue `LinearProgressIndicator`) and `error` (red). Conveys "working on it, don't panic" visually without a jarring color change at 3am when the phone is face-up on the nightstand.
- **D-11:** Card surface is **status only** — no attempt count, no next-retry countdown. "Reconnecting…" is sufficient. Attempt number / countdown may be exposed under `debugMode` in a future iteration, but is NOT part of v1.
- **D-12:** **No global / app-bar indicator** for v1. All state lives on the camera cards. Rationale: monitoring screen has only 1–2 cards visible without scrolling; a global indicator adds noise without adding information.

### Overnight Health Summary (MNTR-01) — Claude's Discretion

The user chose to leave MNTR-01 details to Claude/planner discretion. Sensible defaults for planning:

- **D-13:** **Session-scoped counters** — a "session" begins at `startMonitoring` and ends at `stopMonitoring`. Metrics reset per session. No cross-session persistence for v1.
- **D-14:** **In-memory only** for v1 — no disk persistence of health events. If the app is force-killed overnight, the history is lost; the foreground service (Phase 3) is what prevents that. Persistence across restarts can be added later.
- **D-15:** **Event stream** — the planner defines a lightweight event record (`timestamp`, `cameraId`, `eventType`, `detail?`) for: `stream_started`, `stream_error`, `reconnect_attempt`, `reconnect_success`, `zombie_detected`, `wifi_dropped`, `wifi_reconnected`, `alert_fired`, `monitoring_stopped`. Events append to a per-session list in memory.
- **D-16:** **Access point** — a small icon/button in the app bar of the monitoring screen opens a summary screen (session uptime, per-camera reconnect count, per-camera total downtime, chronological event log). Details (layout, copy) are at planner/UI-phase discretion.
- **D-17:** **Retention** — while monitoring is active, keep the full event list. Cap in-memory list at a sensible max (planner picks — 1,000 events is plenty for a single night even with chatty reconnect loops).

### Claude's Discretion

- Exact AsyncNotifier/state machine shape for the reconnect loop (how to interleave timer, backoff state, and player lifecycle events in `AudioPlayerNotifier`)
- Whether zombie detection runs in the existing `_levelPollTimer` (500ms) or as a separate dedicated timer
- `flutter_local_notifications` channel/category setup for the 5-min alert (priority, sound, importance — must wake the phone)
- `connectivity_plus` integration point — where to subscribe, how to debounce rapid toggle events
- Exact quorum vs OR logic across the four zombie signals (D-06) — whichever minimizes false-positive reconnects
- MNTR-01 summary screen layout, copy, and typography

### Folded Todos

None — no pending todos matched Phase 4 scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements (locked for this phase)
- `.planning/REQUIREMENTS.md` §Reliability — RELY-01, RELY-02, RELY-03
- `.planning/REQUIREMENTS.md` §Monitoring — MNTR-01
- `.planning/ROADMAP.md` §Phase 4 — goal, success criteria, depends-on Phase 3

### Project Conventions (non-negotiable)
- `CLAUDE.md` §Conventions > Defensive error handling — "This is a baby monitor. Parents fall asleep trusting it. No exception may kill a running audio stream." The reconnect loop itself MUST be written defensively (every catch recovers; no unhandled future errors).
- `CLAUDE.md` §Project > Core Value — "Reliable overnight audio from two baby cameras that never silently dies"
- `CLAUDE.md` §Project > Constraints — "Must survive 8+ hours unattended"

### Technology Stack (already recommended in project docs)
- `CLAUDE.md` §Supporting Libraries — `connectivity_plus ^6.1+` for WiFi reconnect detection
- `CLAUDE.md` §Supporting Libraries — `flutter_local_notifications ^18.0+` for the 5-min per-camera push alert (D-04)
- `CLAUDE.md` §Supporting Libraries — `logging ^1.3+` already in use via `appLog()`
- `CLAUDE.md` §media_kit FFmpeg build limitations — some mpv properties behave differently than documented; test all new `NativePlayer.setProperty` calls before relying on them

### Existing Code (phase builds on / modifies these)
- `lib/features/monitoring/providers/audio_player_provider.dart` — `AudioPlayerNotifier` (686 lines). Contains the existing state machine, per-player error stream subscriptions, `_lastAudioPts` tracking, `_levelPollTimer` at 500ms, `silenceDuration` accounting, notification update calls. The reconnect loop integrates HERE.
- `lib/features/monitoring/models/player_state.dart` — `CameraConnectionStatus` enum (expand per D-09), `CameraAudioState` (`silenceDuration`, `isSuspiciouslySilent` already exist), `MonitoringState`.
- `lib/features/monitoring/widgets/camera_audio_card.dart` — existing per-camera card. Surface new `reconnecting` state here (D-10, D-11).
- `lib/core/services/foreground_service.dart` — `ForegroundServiceManager.updateNotification` pattern. Status-aware notification text (D-04 wording) plugs in here.
- `lib/core/providers/settings_provider.dart` — `AppSettings` pattern for reference only (zombie threshold is NOT added, per D-08).
- `lib/core/logging/app_logger.dart` — `appLog(tag, message)` — use for debug logging during reconnect. Health summary event stream (D-15) is a new, separate structure from the log.
- `lib/features/monitoring/screens/log_screen.dart` — existing debug log screen; useful reference for list-rendering + session-scoped data patterns (MNTR-01 summary may follow similar UX).

### External References
- `connectivity_plus` on pub.dev — Stream-based connectivity change events; caveats around Android rapid-toggle debouncing
- `flutter_local_notifications` on pub.dev — `AndroidNotificationDetails` priority/importance config for wake-up alerts; channel setup
- [mpv manual — audio-pts / audio-bitrate properties] — verify property semantics for the zombie detector signals (D-06)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`AudioPlayerNotifier`** — all reconnect logic lives as new methods on this notifier; don't create a parallel notifier. The existing `_subscriptions` list pattern cleanly handles new stream subscriptions (connectivity, per-player error-reconnect bridge).
- **`_lastAudioPts` tracking** — already in place; the zombie detector extends this by tracking age of last advance rather than just the value.
- **`_levelPollTimer` (500ms)** — zombie detection can piggyback on this timer (no new timer needed) OR run on its own longer-interval timer (5s) — planner's choice, with D-06 signals feeding into it.
- **`ForegroundServiceManager.updateNotification`** — status-aware notification text (D-04) plugs into existing pattern; just extend the text-building helper in `startMonitoring` / `_pollAudioLevels`.
- **`StorageService` + `AppSettings`** — settings pattern is for reference only; zombie threshold is hardcoded (D-08). No changes to settings schema for this phase.
- **`CameraAudioState.copyWith`** — immutable state update pattern used for all status transitions. Add reconnect-specific fields (e.g., `reconnectAttempt`, `lastDropAt`, `alertFiredAt`) via the same pattern.

### Established Patterns
- **Riverpod `AsyncNotifier`** — the reconnect loop extends the existing async state machine; no new providers needed beyond what's used for health summary UI.
- **Defensive try/catch** around ALL non-critical operations (see `_tryGetProperty`, `_pollAudioLevels`). The reconnect loop MUST follow this; an exception inside the retry timer must NOT kill the loop.
- **Feature-first folder structure** — new reconnect logic belongs in `lib/features/monitoring/` (provider, models, services/). Health summary screen belongs in `lib/features/monitoring/screens/`.
- **`appLog(tag, message)`** structured logging — reconnect/zombie events both log here AND append to the health summary event stream (two different consumers).
- **`NativePlayer.setProperty` / `getProperty`** for mpv property access — already wrapped in try/catch helpers.

### Integration Points
- `AudioPlayerNotifier.startMonitoring()` — wire the reconnect loop, zombie detector, WiFi listener, and health event stream setup here.
- `AudioPlayerNotifier.stopMonitoring()` — tear down all retry timers, cancel alert-pending timers, flush health event stream.
- `_listenToPlayer` (player subscriptions) — extend the `error` / `completed` listeners to enqueue reconnect (D-03 trigger a).
- `_pollAudioLevels` — extend with zombie signal tracking (D-06), or split into a separate timer that runs the zombie detector.
- `MonitoringScreen` — handle the new `reconnecting` status for card rendering (D-10); add app-bar button to open health summary (D-16).
- `CameraAudioCard` — render amber tint + spinner for `reconnecting` status.
- Notification permission flow (Android 13+ POST_NOTIFICATIONS) — already handled in `MonitoringScreen.initState` for the foreground service notification; may need extension for `flutter_local_notifications` alert channel (D-04).

</code_context>

<specifics>
## Specific Ideas

- User emphasized that interruption modes must be **enumerated thoroughly** during research: "identify all possible ways in which RTSP stream could be interrupted, including due to unifi protect, udm pro updates, camera updates, wifi dropouts/ap firmware updates, etc." This drives the research-phase scope for D-03.
- Retry-forever is emotionally load-bearing: the parent must be able to trust that the app will NOT silently give up at any point during the night. This is not negotiable.
- One-shot alert policy (D-04) was explicitly chosen over repeat/escalate — respect for parent's sleep won over redundancy.

</specifics>

<deferred>
## Deferred Ideas

- **User-tunable zombie threshold** — deferred. Hardcoded 60s for v1; may expose under `debugMode` once field-tested.
- **Cross-session health summary persistence** — deferred. v1 is session-scoped, in-memory only. Persistence + multi-night trends can be a future phase or v2 enhancement.
- **Global app-bar reconnect indicator** — considered and rejected for v1; per-card-only. Can be revisited if screen layout expands.
- **Attempt-count / countdown display on card** — deferred for v1. May expose under `debugMode` or in health summary later.
- **Alert escalation (louder at 15min)** — explicitly rejected for v1; one-shot at 5min is the chosen policy.
- **Coalesced multi-camera alert** — rejected for v1; per-camera alerts even if both drop simultaneously (parent gets two notifications).

</deferred>

---

*Phase: 04-reliability-overnight-monitoring*
*Context gathered: 2026-04-23*
