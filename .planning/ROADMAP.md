# Roadmap: RTSP Audio Mixer

## Overview

This roadmap delivers a reliable overnight baby monitor in four phases. We start by proving the Unifi Protect integration (auth, camera discovery, credentials) on macOS for fast iteration. Then we add the core audio pipeline -- dual RTSP streams with volume mixing. Phase 3 moves everything to Android with a foreground service that survives screen-off overnight. Phase 4 hardens reliability with auto-reconnect, watchdog monitoring, and an overnight health summary so the parent can trust the app while sleeping.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Protect API + Project Foundation** - Authenticate with Unifi Protect, discover cameras, persist credentials, establish macOS dev target
- [ ] **Phase 2: RTSP Audio Streaming** - Extract audio-only from two RTSP streams simultaneously with per-camera volume control
- [ ] **Phase 3: Android Background Operation** - Run as foreground service on physical Android device with screen off overnight
- [ ] **Phase 4: Reliability + Overnight Monitoring** - Auto-reconnect on stream drops, connection status UI, watchdog, and overnight health summary

## Phase Details

### Phase 1: Protect API + Project Foundation
**Goal**: User can connect to their Unifi Protect console, see their cameras, and the app remembers credentials across launches
**Depends on**: Nothing (first phase)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, PLAT-01
**Success Criteria** (what must be TRUE):
  1. User can enter Protect console IP and credentials, and the app authenticates successfully
  2. User can see a list of discovered cameras and select 2 for monitoring
  3. App remembers credentials and auto-connects on next launch without re-entering them
  4. App builds and runs on macOS desktop for development iteration
**Plans**: 3 plans
Plans:
- [x] 01-01-PLAN.md -- Flutter project scaffolding, dependencies, macOS config, Wave 0 test stubs
- [ ] 01-02-PLAN.md -- Protect API client (auth + bootstrap), camera data models, login screen UI
- [ ] 01-03-PLAN.md -- Secure storage, auth/camera providers, camera list screen, GoRouter, full wiring
**UI hint**: yes

### Phase 2: RTSP Audio Streaming
**Goal**: User can hear audio from two baby rooms simultaneously with independent volume control
**Depends on**: Phase 1
**Requirements**: STRM-01, STRM-02
**Success Criteria** (what must be TRUE):
  1. User hears audio from both selected cameras playing simultaneously through phone speaker
  2. User can adjust volume independently per camera using sliders, including muting one while the other plays
  3. No video is decoded -- only audio data is processed (verifiable via CPU/battery usage staying low)
**Plans**: TBD
**UI hint**: yes

### Phase 3: Android Background Operation
**Goal**: App runs reliably on a physical Android device overnight with the screen off and phone charging
**Depends on**: Phase 2
**Requirements**: BGND-01, BGND-02, BGND-03, PLAT-02
**Success Criteria** (what must be TRUE):
  1. App shows a persistent notification indicating monitoring is active
  2. Audio continues playing uninterrupted when the screen turns off and the phone sits on a nightstand charging
  3. Android OS does not kill the app during an overnight session (8+ hours)
  4. App builds, installs, and runs correctly on a physical Android device
**Plans**: TBD

### Phase 4: Reliability + Overnight Monitoring
**Goal**: Parent can trust the app is still listening when they fall asleep -- it recovers from failures and reports overnight health
**Depends on**: Phase 3
**Requirements**: RELY-01, RELY-02, RELY-03, MNTR-01
**Success Criteria** (what must be TRUE):
  1. App automatically reconnects when a stream drops (camera reboot, WiFi blip) without user intervention
  2. User can see per-camera connection status at a glance (connecting, live, reconnecting, error)
  3. App detects and recovers from zombie streams where the TCP connection is open but no audio data arrives
  4. User can view an overnight health summary showing uptime, reconnection count, and stream health events
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Protect API + Project Foundation | 0/3 | Planned | - |
| 2. RTSP Audio Streaming | 0/TBD | Not started | - |
| 3. Android Background Operation | 0/TBD | Not started | - |
| 4. Reliability + Overnight Monitoring | 0/TBD | Not started | - |
