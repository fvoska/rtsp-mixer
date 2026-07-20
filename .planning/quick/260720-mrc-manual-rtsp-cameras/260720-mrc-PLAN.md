---
phase: quick-260720-mrc
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/features/cameras/models/protect_camera.dart
  - lib/features/cameras/providers/camera_state.dart
  - lib/features/cameras/providers/camera_provider.dart
  - lib/features/cameras/widgets/camera_source_badge.dart
  - lib/core/storage/storage_service.dart
  - lib/features/auth/models/auth_state.dart
  - lib/features/auth/providers/auth_provider.dart
  - lib/features/auth/screens/login_screen.dart
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - lib/features/settings/screens/settings_screen.dart
autonomous: true
requirements:
  - QUICK-260720-MRC
must_haves:
  truths:
    - "During setup the user can skip Unifi login and set up the app with manually-entered RTSP URLs only."
    - "Manual cameras are persisted locally and become the camera list (no Unifi API dependency)."
    - "Unifi users can also add manual RTSP cameras; manual cameras are appended to the Unifi list."
    - "When both Unifi and manual cameras are present, each camera's source is labelled; when only one type exists, no label is shown."
    - "Manual cameras play using their URL verbatim — the Unifi RTSPS->RTSP rewrite is not applied to them."
    - "Manual mode persists across app relaunch (returns to the app, not the login screen)."
---

<objective>
Open the app to non-Unifi users while keeping Unifi the primary path. Add a
"skip Unifi" setup option and a manual RTSP-URL camera source that is persisted
locally and merged with (or fully replaces) the Unifi camera list.
</objective>

<context>
Cameras were previously sourced exclusively from the Unifi Protect integration
API and gated behind API-key auth. This adds a second camera source (manual
RTSP URLs) and a manual auth mode, without disturbing the reliability/audio
pipeline, which is already source-agnostic (it consumes ProtectCamera +
selectedCameras).
</context>

<tasks>

<task type="auto">
  <name>Task 1: Manual RTSP camera source + skip-Unifi setup mode</name>
  <action>
1. ProtectCamera: add CameraSource {unifi, manual}, `source` field (default
   unifi, JSON round-trip, legacy JSON => unifi), `isManual`, a `.manual()`
   factory (single `stream` URL, mic assumed on, state CONNECTED), and make
   defaultStreamUrl/defaultQuality fall back to the first URL entry.
2. StorageService: persist manual cameras (`manual_cameras`) and setup mode
   (`auth_mode`).
3. CameraState: hasUnifiCameras / hasManualCameras / hasMixedSources.
4. CameraNotifier: compose `_unifiCameras + _manualCameras`; loadCameras
   becomes `[String? host]` (null => manual-only); addManualCamera /
   removeManualCamera with persistence; manual cameras survive Unifi refresh.
5. AuthState: AuthMode {unifi, manual}, `AuthState.manual()`, isManualMode.
6. AuthNotifier: skipUnifi(); build() restores manual mode from auth_mode;
   login persists auth_mode=unifi; clearResumeFlag preserves mode.
7. LoginScreen: "Skip — add RTSP URLs manually" action.
8. MonitoringScreen idle picker: Add-RTSP-camera dialog + button (empty state
   and header), source badges when mixed, delete for manual cameras, hide
   Refresh in manual mode.
9. Live cards: thread isManual into CameraAudioState; show source badge when
   the live mix mixes sources. Shared CameraSourceBadge widget.
10. audio_player_provider: resolve manual URLs verbatim (skip resolveStreamUrl).
11. SettingsScreen: sign-out copy adapts to manual mode.
  </action>
  <verify>
    <automated>flutter analyze; flutter test test/features/cameras test/features/auth</automated>
  </verify>
</task>

</tasks>

<output>
After completion, create
`.planning/quick/260720-mrc-manual-rtsp-cameras/260720-mrc-SUMMARY.md`.
</output>
