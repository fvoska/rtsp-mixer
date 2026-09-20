---
phase: quick-260920-bat
plan: 01
subsystem: peer
status: complete
tags: [peer, host-mode, battery, status-endpoint, camera-card]
requires:
  - phase: quick-260919-p2p
    provides: host mode, `/roomtone/v1/status` poll, PeerLevelPoller
provides:
  - `battery: {percent, plugged}` on the host's status endpoint (optional field, protocol version unchanged)
  - BatterySource abstraction (battery_plus on device, fake in tests) polled every 60 s + on plug/unplug
  - Host battery on the monitor: header chip, details row, low/critical warning line on the camera card
  - Battery line on the host screen's live card
---

# Quick task 260920-bat: host phone battery on the monitor

## What changed

- **Wire**: `PeerHostServer._statusBody` adds `battery` when the host has a
  reading. Older hosts omit it; older monitors ignore it. No protocol bump.
- **Host**: `PeerHostNotifier` reads `BatterySource` (battery_plus) on start,
  every 60 s and on every plug/unplug event, publishes `PeerHostState.battery`,
  clears it on stop. All failures log and degrade to null.
- **Monitor**: `PeerLevelPoller.batteryFor` (stale with the level after 3 s),
  `CameraAudioState.hostBattery` filled by the poll loop for live peer cameras
  and cleared on a successful reconnect. The card shows a `NN%` chip next to
  the source badge, a `Battery` details row, and — when unplugged and ≤20% —
  a warning line ("plug it in"; ≤10%: "may not last the night").
- `plugged` means *on external power*: charging, full, or held at a charge
  limit all count, since the question is whether the phone will die tonight.

## Verification

- `flutter analyze`: clean.
- New/extended tests: battery_status, peer_host_server (present/absent),
  peer_level_poller (parse, omit, stale), peer_host_provider (read → state →
  `/status`, plug event, throwing reader, cleared on stop), player_state
  (copyWith sentinel), camera_audio_card (chip, amber/red warning, charging
  suppresses, hidden when off-air or unknown).
