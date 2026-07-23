---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Phase 4 UI-SPEC approved
last_updated: "2026-04-24T10:25:55.850Z"
last_activity: 2026-07-22 -- Quick task 260722-pdb (remote URL fallback connectivity for console + manual cameras)
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 12
  completed_plans: 7
  percent: 58
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** Reliable overnight audio from two baby cameras that never silently dies
**Current focus:** Phase 04 — reliability-overnight-monitoring

## Current Position

Phase: 04 (reliability-overnight-monitoring) — EXECUTING
Plan: 1 of 5
Status: Executing Phase 04
Last activity: 2026-07-23 -- Completed quick task 260723-sph: Redesign SPL indicator (absolute level bar, variation-driven outline, 10s waveform chart)

Progress: [█████░░░░░] 50%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: --
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: --
- Trend: --

*Updated after each plan completion*
| Phase 01 P01 | 4min | 2 tasks | 75 files |
| Phase 01 P02 | 5min | 2 tasks | 14 files |
| Phase 02 P01 | 5min | 2 tasks | 8 files |
| Phase 02 P02 | 3min | 2 tasks | 5 files |
| Phase 03 P01 | 3min | 2 tasks | 6 files |
| Phase 03 P02 | 4min | 3 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 4 phases derived from requirements -- Foundation/Auth, Streaming, Android Background, Reliability
- [Roadmap]: macOS desktop (PLAT-01) in Phase 1 for rapid dev iteration; Android device (PLAT-02) deferred to Phase 3 with foreground service work
- [Roadmap]: Cry detection, audio level meters, and per-camera listening modes confirmed as v2 scope
- [Phase 01]: Skipped riverpod_generator/riverpod_lint due to Dart 3.9.2 analyzer conflicts; manual providers until ecosystem catches up
- [Phase 01]: Used ThemeData.dark(useMaterial3: true) constructor per Flutter 3.35 deprecation
- [Phase 01]: Used validateStatus in Dio for cleaner CSRF retry control flow
- [Phase 01]: LoginScreen uses callback parameter for auth, to be wired to Riverpod in Plan 03
- [Phase 01]: Used manual Riverpod providers (AsyncNotifier) due to riverpod_generator Dart 3.9.2 incompatibility
- [Phase 01]: GoRouter-Riverpod bridge via _AuthChangeNotifier with ref.listen for refreshListenable
- [Phase 02]: Used audio-only media_kit_libs variants to minimize binary size and CPU usage
- [Phase 02]: Pan filter uses mono-to-stereo lavfi format compatible with mpv af property
- [Phase 02]: Used ConsumerStatefulWidget for MonitoringScreen to trigger startMonitoring in initState
- [Phase 02]: Sliders disabled when camera is not playing, LinearProgressIndicator during connecting state
- [Phase 03]: Removed isSticky from AndroidNotificationOptions -- not in flutter_foreground_task 9.2.2 API
- [Phase 03]: eventAction set to nothing() -- monitoring uses no periodic TaskHandler polling
- [Phase 03]: Renamed updateMediaItem to setCameraNames to avoid BaseAudioHandler signature conflict
- [Phase 03]: audio_service configured with androidStopForegroundOnPause to minimize dual-notification issue

### Pending Todos

None yet.

### Quick Tasks Completed

| ID | Date | Slug | Summary | Plan |
|----|------|------|---------|------|
| 260514-siv | 2026-05-14 | session-history | Persist last 10 sessions to `sessions.json`; shell-based bottom NavigationBar with IndexedStack (Monitor/Sessions/Logs) keeps audio running across tabs; ActiveSessionBar mini-player; Stop moved to FAB; `startMonitoring` made idempotent | [PLAN](quick/260514-siv-session-history/260514-siv-PLAN.md) · [SUMMARY](quick/260514-siv-session-history/260514-siv-SUMMARY.md) |
| 260516-vgb | 2026-05-17 | allow-more-than-2-cameras-with-performan | Drop hard 2-camera cap (`canStartMonitoring` now requires only `selectedIds.isNotEmpty`); add `hasPerformanceRisk` getter; remove `toggleCamera` silent-reject branch; idle picker shows tertiary-container warning banner when selection > 2; live monitoring toolbar shows compact warning Chip when active count > 2 | [PLAN](quick/260516-vgb-allow-more-than-2-cameras-with-performan/260516-vgb-PLAN.md) · [SUMMARY](quick/260516-vgb-allow-more-than-2-cameras-with-performan/260516-vgb-SUMMARY.md) |
| 260524-ffx | 2026-05-24 | guard-android-only-call-sites-for-window | Add `!kIsWeb && Platform.isAndroid` guards so `flutter build windows` compiles; two-layer guarding — `ForegroundServiceManager` and `audioHandlerProvider` are internal no-ops on non-Android, and direct `FlutterForegroundTask.*` call sites in `main.dart`/`app.dart`/`monitoring_screen.dart` are gated explicitly; Android behavior unchanged | [PLAN](quick/260524-ffx-guard-android-only-call-sites-for-window/260524-ffx-PLAN.md) · [SUMMARY](quick/260524-ffx-guard-android-only-call-sites-for-window/260524-ffx-SUMMARY.md) |
| 260720-mrc | 2026-07-20 | manual-rtsp-cameras | Open the app to non-Unifi users: `CameraSource {unifi, manual}` + `ProtectCamera.manual()`; manual RTSP cameras persisted locally (`manual_cameras`) and composed with Unifi cameras in `CameraNotifier`; `AuthMode {unifi, manual}` + `skipUnifi()` + persisted `auth_mode`; login-screen skip action; idle-picker Add-RTSP-camera dialog, delete, and `CameraSourceBadge` shown only when sources are mixed; manual URLs played verbatim (skip Unifi RTSPS↔RTSP rewrite) | [PLAN](quick/260720-mrc-manual-rtsp-cameras/260720-mrc-PLAN.md) · [SUMMARY](quick/260720-mrc-manual-rtsp-cameras/260720-mrc-SUMMARY.md) |
| 260722-pdb | 2026-07-22 | add-remote-url-fallback-connectivity-loc | Local-preferred/remote-fallback (VPN/Tailscale) connectivity: console + manual cameras carry an optional remote address; auth verify, camera refresh, stream open, reconnect, and quality switch iterate ordered [local, remote] candidates with per-candidate timeouts, failing only when both fail; Settings Connection section (edit/clear all addresses), add-camera Remote URL field, Help "Remote access" section; `replaceUrlHost` helper + `remote_host` storage + `ProtectCamera.remoteUrl` | [PLAN](quick/260722-pdb-add-remote-url-fallback-connectivity-loc/260722-pdb-PLAN.md) · [SUMMARY](quick/260722-pdb-add-remote-url-fallback-connectivity-loc/260722-pdb-SUMMARY.md) |
| 260723-hk2 | 2026-07-23 | card-redesign | Hybrid A+B camera card redesign: edge-to-edge tinted status banner for problem states (amber reconnecting / red error), identity-only header, full-width status line for Live/Connecting…, "Muted" in volume row; fixes "Re…" truncation and inconsistent header tint | [PLAN](quick/260723-hk2-redesign-camera-card-on-monitoring-scree/260723-hk2-PLAN.md) · [SUMMARY](quick/260723-hk2-redesign-camera-card-on-monitoring-scree/260723-hk2-SUMMARY.md) |
| 260723-mkn | 2026-07-23 | card-polish-animations | Camera card polish: spinner/icon optically centered with status label (`_StatusLine` center-aligned; `_StatusBanner` icon centered on first text line); banner, status line, volume Muted↔% text, and connecting↔slider swaps animate via `AnimatedSize` + fade-only `AnimatedSwitcher` (~200–250ms) so state changes no longer pop | [PLAN](quick/260723-mkn-polish-camera-card-fix-spinner-text-alig/260723-mkn-PLAN.md) · [SUMMARY](quick/260723-mkn-polish-camera-card-fix-spinner-text-alig/260723-mkn-SUMMARY.md) |
| 260723-oj0 | 2026-07-23 | add-quick-camera-add-to-session | Quick-add cameras to a live session (inverse of quick-remove): `AudioPlayerNotifier.addCameraToSession` appends one camera to the running mix without touching other streams (no AsyncLoading/stopMonitoring); per-camera connect logic single-sourced into `_connectCamera`; toolbar "Add camera" control opens picker (`_AddCameraSheet`) listing only out-of-session cameras via pure `addableCameras` helper; restores saved volume/mute and persists selection | [PLAN](quick/260723-oj0-add-quick-camera-add-to-session/260723-oj0-PLAN.md) · [SUMMARY](quick/260723-oj0-add-quick-camera-add-to-session/260723-oj0-SUMMARY.md) |
| 260723-skr | 2026-07-23 | fix-false-alive-stream-candidate-confirm | Fix Tailscale exit-node false-alive candidate: `_confirmStreamAlive` now requires positive evidence (audioParams sampleRate > 0, real audio/video track via new `hasRealTrack`, or mpv `track-list/count` > 0); grace-window silence disqualifies only after 4s + 6s extended window with `track-list/count` parsing to 0 both times, so the dead `local` candidate throws and the remote (ts.net) candidate gets tried; plumbing failures still degrade to assume-alive | [PLAN](quick/260723-skr-fix-false-alive-stream-candidate-confirm/260723-skr-PLAN.md) · [SUMMARY](quick/260723-skr-fix-false-alive-stream-candidate-confirm/260723-skr-SUMMARY.md) |
| 260723-pki | 2026-07-23 | strengthen-claude-md-pr-title-descriptio | Rework CLAUDE.md "Never accept GitHub's auto-generated PR title" bullet into a 5-step "Creating a PR" procedure: review all branch commits (`git log --oneline main..HEAD`) before composing, title = Conventional Commits line for the OVERALL change (never the first pre-dispatch `docs:` plan commit), description summarizes the whole diff, always pass explicit title+body to `gh pr create`/MCP `create_pull_request`, fix already-opened PRs via `gh pr edit` | [PLAN](quick/260723-pki-strengthen-claude-md-pr-title-descriptio/260723-pki-PLAN.md) · [SUMMARY](quick/260723-pki-strengthen-claude-md-pr-title-descriptio/260723-pki-SUMMARY.md) |
| 260723-sph | 2026-07-23 | redesign-spl-indicator-absolute-realtime | SPL indicator redesign: level bar now shows absolute pseudo-SPL from encoded `audio-bitrate` (log mapping 2→96 kbps via pure `audio_level_meter.dart` helper, pts flow kept for silence only); card outline alpha ∝ recent peak-to-trough variation of that level (baby-cry visualization, EMA `_baselineLevel` removed); new 10 s rolling Audacity-style mirrored `_WaveformChart` (CustomPaint, 20-slot `levelHistory` on `CameraAudioState`) on live cards | [PLAN](quick/260723-sph-redesign-spl-indicator-absolute-realtime/260723-sph-PLAN.md) · [SUMMARY](quick/260723-sph-redesign-spl-indicator-absolute-realtime/260723-sph-SUMMARY.md) |

### Blockers/Concerns

- ~~Research flags media_kit RTSP audio-only as untested~~ — **resolved**: media_kit_libs_audio lacks RTSP demuxer, must use media_kit_libs_video with vid=no
- ~~Protect API auth method uncertainty~~ — **resolved**: X-API-Key via integration API, bootstrap API does NOT work with API key
- L/R stereo panning deferred — prebuilt FFmpeg lacks audio filters (ebur128, astats, stereotools, pan all missing)
- OEM battery optimization killing foreground service — Phase 3 risk, needs real device testing

## Session Continuity

Last session: --stopped-at
Stopped at: Phase 4 UI-SPEC approved
Resume file: --resume-file

**Planned Phase:** 04 (Reliability + Overnight Monitoring) — 5 plans — 2026-04-24T09:00:20.299Z
