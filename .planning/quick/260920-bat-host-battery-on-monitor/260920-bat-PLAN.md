---
phase: quick-260920-bat
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pubspec.yaml
  - lib/features/peer/models/battery_status.dart
  - lib/features/peer/services/battery_monitor.dart
  - lib/features/peer/widgets/battery_icon.dart
  - lib/features/peer/services/peer_host_server.dart
  - lib/features/peer/models/peer_host_state.dart
  - lib/features/peer/providers/peer_host_provider.dart
  - lib/features/peer/screens/host_screen.dart
  - lib/features/peer/services/peer_level_poller.dart
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - test/features/peer/battery_status_test.dart
  - test/features/peer/peer_host_server_test.dart
  - test/features/peer/peer_level_poller_test.dart
  - test/features/peer/peer_host_provider_test.dart
  - test/features/monitoring/models/player_state_test.dart
  - test/features/monitoring/widgets/camera_audio_card_test.dart
  - README.md
  - CLAUDE.md
autonomous: true
must_haves:
  truths:
    - "A monitor listening to a paired phone can see that phone's battery percentage and whether it is plugged in, on the camera's card"
    - "A host that is unplugged and low (≤20%) is called out on the monitor as an action ('plug it in'), escalating at ≤10%"
    - "Hosts from an older build, or platforms without a battery, simply omit the field — pairing and streaming are unaffected"
    - "Nothing in the battery path can stop the host server, the microphone, or the monitor's stream: every read is caught and degrades to 'unknown'"
  artifacts:
    - path: lib/features/peer/models/battery_status.dart
      provides: wire model `{percent, plugged}` with tolerant parse and low/critical thresholds
    - path: lib/features/peer/services/battery_monitor.dart
      provides: BatterySource abstraction + battery_plus implementation, injectable via batterySourceProvider
  key_links:
    - from: PeerHostNotifier._refreshBattery
      to: PeerHostServer.currentBattery
      via: PeerHostState.battery (60 s poll + plug/unplug events)
    - from: PeerLevelPoller.batteryFor
      to: CameraAudioState.hostBattery
      via: the 250 ms poll loop in AudioPlayerNotifier, live peer cameras only
---

<objective>
Let the monitoring phone see the battery level of the host phone (the spare
phone in the nursery running host mode).

Purpose: a host phone that runs flat overnight is the one failure the
reconnect loop cannot recover from, and it fails silently. Surfacing the
battery — and a plain "plug it in" warning — on the monitor's card lets the
parent fix it before falling asleep.

Output: `/roomtone/v1/status` carries `battery: {percent, plugged}`; the
monitor's card shows a battery chip in the header, a `Battery` row in the
details panel and a low-battery warning line; the host screen shows the same
reading.
</objective>

<tasks>
1. Wire model + reader on the host (battery_plus, injectable, never throws).
2. Serve it over `/status`; publish into PeerHostState; show on the host screen.
3. Parse it in PeerLevelPoller; carry it into CameraAudioState; render on the card.
4. Tests at every seam; README + CLAUDE.md notes.
</tasks>
