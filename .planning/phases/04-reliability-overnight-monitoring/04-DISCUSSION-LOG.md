# Phase 4: Reliability + Overnight Monitoring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 04-reliability-overnight-monitoring
**Areas discussed:** Reconnect strategy, Zombie stream detection, Connection status UI

Initial gray-area selection excluded **Overnight health summary** — it was folded into CONTEXT.md under Claude's Discretion (D-13 through D-17) per the user's explicit choice.

---

## Reconnect strategy

### Backoff curve

| Option | Description | Selected |
|--------|-------------|----------|
| Exponential capped | 1s → 2s → 4s → 8s → 16s → 30s max, with ±20% jitter | ✓ |
| Fixed 5s | Simple, predictable; hits Unifi/router hard during long outage | |
| Aggressive then slow | 3 quick retries (1s each) then 30s periodic | |

**User's choice:** Exponential capped.

### Max retries

| Option | Description | Selected |
|--------|-------------|----------|
| Forever | Never give up; silently surrendering defeats core value | |
| Give up after 1 hour | Stop after ~1h failed attempts, mark ERROR | |
| Forever but alert | Never give up + local push notification after N minutes | ✓ |

**User's choice:** Forever but alert, with N = 5 minutes.
**Notes:** "keep trying forever, but after 5mins of connection down, send a notification so the parent can wake up and check what's down"

### Reconnect triggers

| Option | Description | Selected |
|--------|-------------|----------|
| Player error event | Listen to player.stream.error / completed | ✓ |
| Zombie detection | Forced reconnect from RELY-03 loop | ✓ |
| WiFi reconnect | connectivity_plus; proactively reconnect when WiFi returns | ✓ |

**User's choice:** All three — multi-select.
**Notes:** "identify all possible ways in which RTSP stream could be interrupted, including due to unifi protect, udm pro updates, camera updates, wifi dropouts/ap firmware updates, etc." — research task to enumerate all interruption modes.

### Notification text during retry

| Option | Description | Selected |
|--------|-------------|----------|
| Status-aware text | "Monitoring: Nursery, Bedroom (reconnecting)" during retry | ✓ |
| No change during retry | Keep notification static; status only in app | |
| Error-only | Only update notification when camera has been disconnected long enough | |

**User's choice:** Status-aware text.

### Alert scope (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Per camera | Any camera down >5min → fires its own alert | ✓ |
| Session-wide | Only fire when ALL cameras down >5min simultaneously | |
| Per camera, grouped | Per-camera threshold but coalesce into one notification | |

**User's choice:** Per camera.

### Re-alert policy (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| One-shot | Fire once per outage, don't re-nag | ✓ |
| Repeat every 15min | Re-fire every 15 minutes until reconnect | |
| Escalate | Quiet at 5min, louder heads-up at 15min | |

**User's choice:** One-shot.

---

## Zombie stream detection

### Silence threshold

| Option | Description | Selected |
|--------|-------------|----------|
| 30 seconds | Fast recovery, more churn | |
| 60 seconds | Balanced — past healthy-stream timescales | ✓ |
| 120 seconds | Conservative, fewer false-positive reconnects | |
| User-configurable | Add preset selector to AppSettings | |

**User's choice:** 60 seconds.

### Signals combined

| Option | Description | Selected |
|--------|-------------|----------|
| audio-pts stall | Baseline — existing `_lastAudioPts` tracking | ✓ |
| Buffering flag stuck | player.stream.buffering=true, never flips back | ✓ |
| audio-bitrate dropped to 0 | Poll audio-bitrate; sustained 0 with PTS stall | ✓ |
| No new audioParams events | Track last emission time of player.stream.audioParams | ✓ |

**User's choice:** All four — multi-select (belt-and-suspenders).

### Response

| Option | Description | Selected |
|--------|-------------|----------|
| Force reconnect silently | Status → reconnecting, kick exponential backoff, log event | ✓ |
| Mark error first | Status → error with "zombie detected", require user action | |
| Reconnect with visible toast | Force reconnect + in-app snackbar when screen is on | |

**User's choice:** Force reconnect silently.

### User configurable

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded sensible default | Ship with 60s default; simpler UI | ✓ |
| Settings preset | AppSettings with Aggressive/Balanced/Conservative | |
| Debug-mode only | Show threshold control only when debugMode enabled | |

**User's choice:** Hardcoded sensible default.

---

## Connection status UI

### State model

| Option | Description | Selected |
|--------|-------------|----------|
| Add 'reconnecting' | Expand enum to idle / connecting / playing / reconnecting / error | ✓ |
| Reuse 'connecting' | Keep 4 states; covers first attempt + retry | |
| Two-field | Keep enum, add separate reconnect_attempt counter/flag | |

**User's choice:** Add 'reconnecting'.

### Visual

| Option | Description | Selected |
|--------|-------------|----------|
| Amber + spinner | Amber tint on card + small spinner. Distinct from connecting and error | ✓ |
| Pulse border | Amber pulsing border; no spinner. More subtle | |
| Text-only | Just text in subtitle; no color change | |

**User's choice:** Amber + spinner.

### Detail

| Option | Description | Selected |
|--------|-------------|----------|
| Status only | Just "Reconnecting…" — no attempt count, no countdown | ✓ |
| Attempt count | "Reconnecting… (attempt 5)" | |
| Countdown | "Retrying in 8s…" with live countdown | |

**User's choice:** Status only.

### Global indicator

| Option | Description | Selected |
|--------|-------------|----------|
| None, per-card only | All state lives on camera card | ✓ |
| App bar badge | Small colored dot when any camera reconnecting/alerting | |
| Alert banner | Unmissable strip at top of screen when 5-min alert fires | |

**User's choice:** None, per-card only.

---

## Claude's Discretion

Explicitly deferred by the user:
- **MNTR-01 (Overnight health summary)** — left to Claude's discretion. Sensible defaults recorded in CONTEXT.md D-13 through D-17: session-scoped, in-memory, event-stream based, app-bar icon access, 1,000-event cap.
- Exact reconnect state-machine shape inside `AudioPlayerNotifier`
- Zombie detector timer granularity (piggyback on existing 500ms poll vs dedicated 5s timer)
- `flutter_local_notifications` channel config for the 5-min alert
- `connectivity_plus` subscription / debouncing details
- Quorum vs OR logic across the four zombie signals

## Deferred Ideas

- User-tunable zombie threshold (v1 hardcoded; may expose under debugMode later)
- Cross-session health summary persistence (v1 in-memory only)
- Global app-bar reconnect indicator (considered, rejected for v1)
- Attempt-count / countdown display on card (v1 status-only)
- Alert escalation at 15min (rejected; one-shot at 5min wins)
- Coalesced multi-camera alerts (rejected; per-camera alerts even if both drop)
