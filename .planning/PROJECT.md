# RTSP Audio Mixer

## What This Is

A baby monitor app that connects to Unifi Protect cameras, extracts audio-only from RTSP streams, and lets a parent listen to two rooms simultaneously with per-camera volume mixing. Designed to run reliably overnight on Android with the screen off — something the Unifi app and VLC can't do.

## Core Value

Reliable overnight audio from two baby cameras that never silently dies — the parent must be able to trust it's still listening when they fall asleep.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Authenticate with Unifi Protect API (console IP + credentials)
- [ ] Persist credentials securely, auto-connect on launch
- [ ] Discover and list cameras from Protect API
- [ ] Let user pick 2 cameras from discovered list
- [ ] Extract audio-only from RTSP streams (no video decoding)
- [ ] Stream 2 RTSP audio sources simultaneously
- [ ] Per-camera volume slider (mix two streams into single audio output)
- [ ] Per-camera mode: continuous, cry-triggered, or off
- [ ] Audio level meters per camera (visual feedback of room activity)
- [ ] Cry detection via Unifi Protect AI smart detection events
- [ ] Cry-triggered mode: auto-start audio stream + push notification on detection
- [ ] Android foreground service to prevent OS from killing the app overnight
- [ ] Auto-reconnect on stream drop (camera reboot, WiFi blip, power outage, Unifi update)
- [ ] Run with screen off, phone charging on nightstand

### Out of Scope

- Video display — audio only, no video decoding
- Remote access — LAN only, cameras and phone on same WiFi
- More than 2 cameras — exactly 2 baby rooms
- Cry detection ML — use Unifi's built-in AI, don't build our own
- iOS-first — Android primary, cross-platform is nice-to-have

## Context

- Parent has 2 Unifi Protect cameras in baby rooms (one newborn)
- Cameras have RTSP enabled, Protect console IP is known
- Current pain: Unifi app requires screen on; VLC only handles one stream and drops randomly overnight
- Phone sits on nightstand playing through built-in speaker
- Unifi Protect has AI smart detection including baby crying events
- Protect API provides camera discovery, RTSP URLs, and smart detection event webhooks/polling
- Flutter mentioned as candidate framework for cross-platform (Android + web)

## Constraints

- **Platform**: Android primary, web nice-to-have — Flutter is the candidate framework
- **Network**: Same LAN only — no need for cloud relay or remote tunneling
- **Audio only**: Must not decode video — minimize battery and CPU usage overnight
- **Reliability**: Must survive 8+ hours unattended — auto-reconnect is non-negotiable
- **Background**: Android must not kill the app — foreground service with persistent notification

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Unifi Protect API for camera discovery | Avoid manual RTSP URL entry, better UX | -- Pending |
| Use Unifi AI cry detection, not custom ML | Already built-in, accurate, no extra processing | -- Pending |
| Flutter as framework candidate | Cross-platform (Android + web), need to validate RTSP/audio library ecosystem | -- Pending |
| Exactly 2 cameras | Matches current need, simplifies UI and mixing | -- Pending |
| LAN only | Simplifies architecture, no auth/relay complexity | -- Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-01 after initialization*
