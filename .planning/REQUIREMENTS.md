# Requirements: RTSP Audio Mixer

**Defined:** 2026-04-01
**Core Value:** Reliable overnight audio from two baby cameras that never silently dies

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Authentication

- [x] **AUTH-01**: User can authenticate with Unifi Protect console using IP address and credentials
- [x] **AUTH-02**: User can discover and select 2 cameras from Protect API camera list
- [ ] **AUTH-03**: App persists credentials securely and auto-connects on launch

### Streaming

- [x] **STRM-01**: App extracts and plays audio-only from 2 RTSP streams simultaneously (no video decoding)
- [x] **STRM-02**: User can adjust volume independently per camera via sliders
- [x] **STRM-03**: User can pan each camera's audio between left/right stereo channels (e.g. nursery in left ear, bedroom in right ear). Works together with volume control.

### Background

- [ ] **BGND-01**: App runs as Android foreground service with persistent notification showing monitoring status
- [ ] **BGND-02**: App acquires partial wake lock and high-performance WiFi lock to prevent OS throttling
- [ ] **BGND-03**: Audio continues playing with screen off and phone charging

### Reliability

- [ ] **RELY-01**: App auto-reconnects dropped RTSP streams with exponential backoff (handles camera reboot, WiFi blip, power outage)
- [ ] **RELY-02**: App shows per-camera connection status (connecting, live, reconnecting, error)
- [ ] **RELY-03**: Stream health watchdog detects zombie streams (TCP open but no audio data) and forces reconnect

### Monitoring

- [ ] **MNTR-01**: App shows overnight health summary (uptime, reconnection count, stream health events)

### Platform

- [x] **PLAT-01**: App builds and runs on macOS desktop for development and rapid iteration
- [ ] **PLAT-02**: App builds and runs on physical Android device for real-world overnight testing

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Visual Feedback

- **VSFB-01**: Audio level meters per camera showing real-time audio activity

### Cry Detection

- **CRYD-01**: Subscribe to Unifi Protect websocket for smart detection events
- **CRYD-02**: Local push notification when Unifi AI detects baby crying
- **CRYD-03**: Per-camera listening mode: continuous, cry-triggered, or off

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Video display | Massive battery drain; audio-only is the core value |
| Custom cry detection ML | Use Unifi's built-in AI; zero phone battery cost |
| Remote/cloud access | LAN only; simplifies architecture |
| Two-way audio / talk-back | Walk to the room |
| 3+ cameras | Exactly 2 baby rooms |
| EQ / noise filtering | Volume control sufficient; Unifi handles cry vs noise |
| Sleep/wake scheduling | Manual start/stop; 2-tap interaction |
| Smartwatch companion | Standard notification bridging is enough |
| iOS build | Android primary; macOS for dev only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Complete |
| AUTH-02 | Phase 1 | Complete |
| AUTH-03 | Phase 1 | Pending |
| PLAT-01 | Phase 1 | Complete |
| STRM-01 | Phase 2 | Complete |
| STRM-02 | Phase 2 | Complete |
| STRM-03 | Phase 2 | Complete |
| BGND-01 | Phase 3 | Pending |
| BGND-02 | Phase 3 | Pending |
| BGND-03 | Phase 3 | Pending |
| PLAT-02 | Phase 3 | Pending |
| RELY-01 | Phase 4 | Pending |
| RELY-02 | Phase 4 | Pending |
| RELY-03 | Phase 4 | Pending |
| MNTR-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-01 after roadmap creation*
