---
phase: quick-260720-mrc
plan: 01
subsystem: cameras-auth-monitoring
tags: [feature, cameras, auth, riverpod, storage, ui]
requirements:
  - QUICK-260720-MRC
dependency_graph:
  requires: []
  provides:
    - CameraSource
    - ProtectCamera.manual
    - AuthMode
    - AuthState.manual
    - AuthNotifier.skipUnifi
    - CameraNotifier.addManualCamera
    - CameraNotifier.removeManualCamera
    - CameraSourceBadge
  affects:
    - lib/features/cameras/models/protect_camera.dart
    - lib/features/cameras/providers/camera_state.dart
    - lib/features/cameras/providers/camera_provider.dart
    - lib/features/auth/models/auth_state.dart
    - lib/features/auth/providers/auth_provider.dart
    - lib/features/monitoring/providers/audio_player_provider.dart
tech_stack:
  added: []
  patterns:
    - "Two camera sources merged in one AsyncNotifier: private _unifiCameras + _manualCameras composed into CameraState, with an authoritative _selectedIds set filtered to existing cameras on every publish."
    - "Manual RTSP URLs are used verbatim at playback; the Unifi-specific RTSPS->RTSP rewrite (resolveStreamUrl) is only applied to Unifi cameras."
key_files:
  created:
    - lib/features/cameras/widgets/camera_source_badge.dart
  modified:
    - lib/features/cameras/models/protect_camera.dart
    - lib/features/cameras/providers/camera_state.dart
    - lib/features/cameras/providers/camera_provider.dart
    - lib/core/storage/storage_service.dart
    - lib/features/auth/models/auth_state.dart
    - lib/features/auth/providers/auth_provider.dart
    - lib/features/auth/screens/login_screen.dart
    - lib/features/monitoring/models/player_state.dart
    - lib/features/monitoring/providers/audio_player_provider.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - lib/features/settings/screens/settings_screen.dart
decisions:
  - "[Quick 260720-mrc] Reused ProtectCamera for manual cameras via a CameraSource enum + .manual() factory rather than a new model, to avoid churn across the source-agnostic audio/reliability pipeline and existing tests."
  - "[Quick 260720-mrc] Scope = manual URL ENTRY. Network auto-discovery (ONVIF/mDNS) was left out — it needs native deps not present in the stack — but the UI is worded generically (\"Add RTSP camera\") so discovery can be added later without rework."
  - "[Quick 260720-mrc] Manual cameras stored under their own storage key (manual_cameras), independent of the Unifi cache, so they survive Unifi refreshes and exist with no console configured."
  - "[Quick 260720-mrc] auth_mode persisted so a returning manual-only user lands in the app, not the login screen. Sign-out/reset performs a full clearAll (also wipes manual cameras) — consistent with the existing 'forget everything' semantics."
completed: "2026-07-20"
---

# Quick Task 260720-mrc: Manual RTSP Cameras + Skip-Unifi Setup — Summary

Non-Unifi users can now use the app: during setup they can skip Unifi login and
enter RTSP stream URLs manually. Unifi users can additionally append manual RTSP
cameras to their Unifi camera list. Cameras of each type are labelled only when
both types are present.

## What Changed

### Camera model & source (`protect_camera.dart`)
- New `enum CameraSource { unifi, manual }` and a `source` field (default
  `unifi`; legacy cached JSON without `source` decodes as `unifi`).
- `ProtectCamera.manual({id, url, name})` factory — single `stream` URL,
  `isMicEnabled: true` (no false "mic disabled" warning), `state: CONNECTED`.
- `isManual` getter; `copyWith` and `toJson`/`fromJson` preserve `source`.
- `defaultStreamUrl`/`defaultQuality` fall back to the first URL entry so a
  manual camera's `stream` key resolves.

### Storage (`storage_service.dart`)
- `saveManualCameras` / `loadManualCameras` (key `manual_cameras`).
- `saveAuthMode` / `loadAuthMode` (key `auth_mode`).

### Camera state & notifier (`camera_state.dart`, `camera_provider.dart`)
- `hasUnifiCameras`, `hasManualCameras`, `hasMixedSources` on `CameraState`.
- `CameraNotifier` now keeps `_unifiCameras`, `_manualCameras`, `_selectedIds`
  and composes them (Unifi first, manual appended). `loadCameras([String? host])`
  — `null` host = manual-only (no API call). `addManualCamera` (auto-selects and
  persists) and `removeManualCamera`. Manual cameras survive Unifi API refresh.

### Auth (`auth_state.dart`, `auth_provider.dart`, `login_screen.dart`)
- `AuthMode {unifi, manual}`, `AuthState.manual()`, `isManualMode`.
- `AuthNotifier.skipUnifi()` persists manual mode and loads manual cameras.
  `build()` restores manual mode from `auth_mode`; `login()` persists
  `auth_mode=unifi`; `clearResumeFlag()` preserves the current mode.
- Login screen: an "or" divider and an outlined **Skip — add RTSP URLs manually**
  button.

### Monitoring UI (`monitoring_screen.dart`, `camera_audio_card.dart`, `camera_source_badge.dart`, `player_state.dart`)
- Idle picker: **Add RTSP camera** dialog (name optional + validated
  `rtsp://`/`rtsps://` URL) reachable from the empty state and the header;
  Refresh hidden in manual mode; manual cameras show their URL and a delete
  control; `CameraSourceBadge` (UniFi/Manual) shown only when
  `hasMixedSources`.
- `CameraAudioState.isManual` threaded through `startMonitoring`; live cards
  show the source badge when the active mix contains both types.
- New shared `CameraSourceBadge` widget (used by picker + live card).

### Playback (`audio_player_provider.dart`)
- Manual camera URLs are used verbatim; `resolveStreamUrl` (the Unifi
  RTSPS↔RTSP port/scheme rewrite) is applied only to Unifi cameras.

### Settings (`settings_screen.dart`)
- Sign-out tile + dialog copy adapt to manual mode ("Reset setup" / removes
  manual cameras) vs Unifi mode ("Sign out" / forget API key).

## Tests
- `camera_model_test.dart`: source default (incl. legacy JSON), `.manual()`
  factory, JSON round-trip, first-entry URL fallback, copyWith preserves source.
- `camera_provider_test.dart`: replaced the stale "enforces max 2" test (the cap
  was removed in 260516-vgb) with an "allows more than 2" test; added
  addManualCamera / removeManualCamera / manual-only load / manual-survives-
  refresh.
- `auth_provider_test.dart`: skipUnifi enters+persists manual mode; relaunch
  restores manual mode from `auth_mode`.

## Verification
- `flutter`/`dart` SDK is not installed in this environment, so `flutter analyze`
  / `flutter test` could not be run here. Changes were reviewed manually against
  all call sites (loadCameras signature, CameraAudioState construction, badge
  wiring). Run `flutter analyze && flutter test` locally to confirm.

## Deviations / Out of Scope
- Network auto-discovery (ONVIF/mDNS) is not implemented — only manual URL entry.
  UI wording is generic so discovery can be added later.
