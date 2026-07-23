---
phase: quick-260722-pdb
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/core/storage/storage_service.dart
  - lib/features/auth/models/auth_state.dart
  - lib/features/auth/providers/auth_provider.dart
  - lib/features/cameras/models/protect_camera.dart
  - lib/features/cameras/providers/camera_provider.dart
  - lib/features/monitoring/helpers/rtsp_url.dart
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/settings/screens/settings_screen.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
  - lib/features/help/screens/help_screen.dart
  - test/features/monitoring/helpers/rtsp_url_test.dart
  - test/features/cameras/models/camera_model_test.dart
  - test/core/storage/storage_service_test.dart
autonomous: true
requirements: [QUICK-260722-PDB]

must_haves:
  truths:
    - "With both a local and remote console address configured, login/verify succeeds when only the remote (VPN/Tailscale) address is reachable — local is tried first, remote is the fallback, and failure occurs only when both fail"
    - "A manual RTSP camera can carry an optional remote URL; audio playback tries the local URL first and falls back to the remote URL, and reconnect attempts re-prefer local each cycle so the app recovers to the LAN stream when back home"
    - "From Settings, the user can edit the console local address, set/clear the console remote URL, and set/clear per-manual-camera remote URLs — including adding the local address later when initial setup was done via the remote address"
    - "The Help page has a Remote access (VPN / Tailscale) section explaining what Remote URL is, local-preferred/remote-fallback behavior, and where to configure it"
    - "No fallback failure ever kills a running audio stream — candidate-open errors are caught, logged via appLog, and surfaced as connection state, never as an uncaught exception"
  artifacts:
    - "lib/features/monitoring/helpers/rtsp_url.dart — replaceUrlHost(String url, String newHost)"
    - "lib/core/storage/storage_service.dart — remote_host save/load/delete helpers"
    - "lib/features/cameras/models/protect_camera.dart — nullable remoteUrl field, serialized"
    - "lib/features/settings/screens/settings_screen.dart — Connection section with edit dialogs"
    - "lib/features/help/screens/help_screen.dart — Remote access help section"
  key_links:
    - "AuthNotifier verify/login → ProtectApiClient.verifyConnection tried against local host then remote host on connectionRefused/timeout AppError"
    - "CameraNotifier._refreshFromApi → whichever host answered becomes the active API host for getRtspsUrls"
    - "audio_player_provider startMonitoring / _performReconnectOpen / switchQuality → ordered [local, remote] candidate list built from CameraAudioState.availableQualities + remoteQualities"
---

<objective>
Add "Remote URL" fallback connectivity: the Unifi Protect console and each manual RTSP camera can have both a local address and a remote (VPN/Tailscale) address. All connection attempts (API auth, camera refresh, stream open, reconnect, quality switch) prefer local and fall back to remote, failing only when both fail. Settings gains a Connection section for editing all addresses (including adding a local address after remote-first setup), and the Help page documents the feature.

Purpose: lets the parent set up and use the monitor away from home over Tailscale/WireGuard while keeping LAN-first behavior at home, without ever silently dying.
Output: fallback-aware auth/camera/playback layers, Settings Connection UI, add-camera remote field, Help section, and focused unit tests.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/home/user/rtsp-mixer/CLAUDE.md
@/home/user/rtsp-mixer/.planning/STATE.md
@lib/core/storage/storage_service.dart
@lib/features/auth/models/auth_state.dart
@lib/features/auth/providers/auth_provider.dart
@lib/core/api/protect_api_client.dart
@lib/features/cameras/models/protect_camera.dart
@lib/features/cameras/providers/camera_provider.dart
@lib/features/monitoring/helpers/rtsp_url.dart
@lib/features/monitoring/models/player_state.dart
@lib/features/monitoring/providers/audio_player_provider.dart
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Data + connectivity layer — remote host storage, model field, host-replace helper, API fallback</name>
  <files>lib/core/storage/storage_service.dart, lib/features/auth/models/auth_state.dart, lib/features/auth/providers/auth_provider.dart, lib/features/cameras/models/protect_camera.dart, lib/features/cameras/providers/camera_provider.dart, lib/features/monitoring/helpers/rtsp_url.dart, test/features/monitoring/helpers/rtsp_url_test.dart, test/features/cameras/models/camera_model_test.dart, test/core/storage/storage_service_test.dart</files>
  <behavior>
    - rtsp_url_test.dart: replaceUrlHost swaps only the host — preserves scheme, port, path, and query (e.g. rtsps://10.0.0.5:7441/abc?enableSrtp with host 100.64.0.9 → rtsps://100.64.0.9:7441/abc?enableSrtp); tolerates newHost pasted with a scheme prefix and/or trailing slash (strips them); returns the original URL unchanged when parsing fails (never throws)
    - camera_model_test.dart: ProtectCamera with remoteUrl survives toJson/fromJson round-trip; legacy JSON without the remoteUrl key deserializes with remoteUrl == null; copyWith can set remoteUrl
    - storage_service_test.dart: remote_host save → load round-trips; delete → load returns null
  </behavior>
  <action>
    Write the failing tests above first, then implement:

    1. rtsp_url.dart: add top-level `String replaceUrlHost(String url, String newHost)` using Uri.tryParse and uri.replace(host:), after normalizing newHost (strip any scheme prefix like http:// or rtsp://, strip trailing slashes, trim whitespace). On any parse failure return the input url unchanged — this helper must never throw (defensive-error-handling rule).
    2. storage_service.dart: add `remote_host` key with saveRemoteHost/loadRemoteHost/deleteRemoteHost following the existing saveCredentials/loadCredentials pattern. `host` remains the local/primary address.
    3. protect_camera.dart: add nullable `String? remoteUrl` — constructor param, param on ProtectCamera.manual, serialized in toJson, read in fromJson (absent key → null), and included in copyWith (note copyWith currently only handles rtspsStreamUrls; extend it so remoteUrl can be both set and preserved — use a sentinel or explicit bool if needed to allow clearing to null).
    4. auth_state.dart: add nullable `remoteHost` to the authenticated state; manual/unauthenticated keep it null.
    5. auth_provider.dart: load remote_host during build alongside credentials. In login/verify and background validation: attempt client.verifyConnection(localHost) first; if it fails with an AppError of type connectionRefused or timeout AND a remote host is configured, attempt verifyConnection(remoteHost); fail only when both fail (surface the local-attempt error). Track which host answered and pass it to loadCameras. Add AuthNotifier methods `updateLocalHost(String host)` and `updateRemoteHost(String? host)` (null/empty clears): persist via StorageService, update AuthState, trigger a camera reload. updateLocalHost is what covers "setup done via Tailscale, add the real local address later" — user can also swap values between the two fields.
    6. camera_provider.dart: extend _refreshFromApi (and loadCameras plumbing) to accept both hosts; try local first, fall back to remote on connectionRefused/timeout; whichever host answers becomes the active API host used for the subsequent getRtspsUrls calls. Add `addManualCamera` optional remoteUrl param (persisted via saveManualCameras) and a new `updateManualCamera(String id, {String? url, String? remoteUrl, String? name})` method that edits the stored manual camera, allows clearing remoteUrl, persists, and updates state.

    All fallback branches wrap the secondary attempt in try/catch and log via appLog; a remote-attempt failure must never mask or escalate beyond the combined "both failed" error path.
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/helpers/rtsp_url_test.dart test/features/cameras/models/camera_model_test.dart test/core/storage/storage_service_test.dart && flutter analyze</automated>
  </verify>
  <done>replaceUrlHost, remote_host storage, ProtectCamera.remoteUrl, auth local→remote verify fallback, camera-refresh fallback with active-API-host propagation, and updateManualCamera all exist; new tests pass and flutter analyze is clean.</done>
</task>

<task type="auto">
  <name>Task 2: Playback candidate fallback — startMonitoring, reconnect, and quality switch try local then remote</name>
  <files>lib/features/monitoring/models/player_state.dart, lib/features/monitoring/providers/audio_player_provider.dart</files>
  <action>
    1. player_state.dart: add `Map<String, String> remoteQualities` to CameraAudioState (default empty; quality → remote URL), preserved in copyWith. `activeStreamUrl` continues to reflect the URL actually in use.
    2. audio_player_provider.dart — startMonitoring: when building per-camera URLs, also build the remote variant. For Unifi cameras: remote candidate = API URL with host swapped to remoteHost via replaceUrlHost (only when a remote host is configured; still run through resolveStreamUrl/resolveFor so the useRtsp/RTSPS handling matches the local candidate). For manual cameras: local candidate = entered URL verbatim, remote candidate = camera.remoteUrl verbatim (skip host rewriting, matching the existing manual-camera convention). Populate availableQualities (local) and remoteQualities (remote) accordingly. For the chosen quality, build an ordered candidate list [local, remote-if-present] and try each with a per-candidate open timeout of ~12 seconds (mirror the existing 15s timeout pattern in _performReconnectOpen — plain player.open has no timeout today, so wrap it). First success wins: set activeStreamUrl to that candidate and appLog which candidate (local/remote) connected. Set the camera's error state only when ALL candidates fail; each candidate failure is caught and logged, never rethrown mid-loop.
    3. _performReconnectOpen(cameraId): instead of retrying only cam.activeStreamUrl, rebuild the same ordered candidate list for the camera's current quality (local first, from availableQualities/remoteQualities) so recovery re-prefers local when the parent is back home. Keep the existing defensive structure exactly: per-candidate timeout, catch/log each failure, update activeStreamUrl to whichever candidate succeeded, and throw only when all candidates fail so ReconnectSupervisor reschedules as it does today.
    4. switchQuality: apply the same candidate approach for the new quality (local candidate from availableQualities, remote from remoteQualities, local first, error only when both fail).

    CLAUDE.md defensive rule is binding here: every candidate attempt is individually try/caught; no exception from a fallback attempt may propagate in a way that kills another camera's running stream.
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
  </verify>
  <done>CameraAudioState carries remoteQualities; startMonitoring, _performReconnectOpen, and switchQuality all iterate ordered [local, remote] candidates with per-candidate timeouts, log the winning candidate, error only when all fail, and full test suite + analyze pass.</done>
</task>

<task type="auto">
  <name>Task 3: Settings Connection section, add-camera remote field, Help page section</name>
  <files>lib/features/settings/screens/settings_screen.dart, lib/features/monitoring/screens/monitoring_screen.dart, lib/features/help/screens/help_screen.dart</files>
  <action>
    1. settings_screen.dart: add a "Connection" section above the Help entry, following the existing SwitchListTile/ListTile section pattern.
       - Unifi mode only (read AuthState/AuthMode): "Console local address" and "Console remote URL" ListTiles, current value as subtitle ("Not set" when absent). Each opens an AlertDialog with a single text field; remote dialog offers a clear action (persists null). Persist via AuthNotifier.updateLocalHost / updateRemoteHost from Task 1.
       - Both modes: "Camera remote URLs" — one ListTile per manual camera (subtitle = current remoteUrl or "Not set") opening an edit dialog with rtsp(s):// validation on non-empty input and a clear action; persist via CameraNotifier.updateManualCamera. Hide the whole group when there are no manual cameras.
    2. monitoring_screen.dart — _showAddManualCameraDialog: add an optional "Remote URL (optional)" text field below the URL field; when non-empty validate with the existing _validateRtspUrl logic (rtsp:// or rtsps:// prefix); pass through to addManualCamera(remoteUrl:).
    3. help_screen.dart: add a new _HelpSection "Remote access (VPN / Tailscale)" using the existing _Step/_Note/_UrlExample widgets. Cover: what a Remote URL is; connections prefer the local address and fall back to remote, failing only when both fail; works with Tailscale, WireGuard, or any VPN that makes the camera network routable; configure it in Settings → Connection or the Add camera dialog; if you set the app up while away using a VPN address, add the local address later in Settings → Connection; remote streaming adds latency and battery cost, and monitoring auto-recovers to the local stream when back home.
    4. Commit with Conventional Commits type(s), e.g. feat(connectivity) for code and docs(help) if split.
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
    <human-check>In Settings (Unifi mode), Connection section shows console local/remote tiles with edit dialogs; manual-camera remote URL tiles appear only when manual cameras exist; Add camera dialog has the optional Remote URL field; Help shows the Remote access section.</human-check>
  </verify>
  <done>Settings exposes editable console local address, console remote URL, and per-manual-camera remote URLs with clear actions; add-camera dialog accepts an optional validated remote URL; Help documents remote access; analyze and tests pass.</done>
</task>

</tasks>

<verification>
- `flutter analyze` clean (use /root/flutter/bin/flutter if flutter is not on PATH)
- `flutter test` passes, including new replaceUrlHost, remoteUrl JSON round-trip/legacy, and remote_host storage tests
- Grep confirms no plain `player.open(` call in the startMonitoring candidate loop without a timeout wrapper
- All commits follow Conventional Commits (feat/test/docs scopes)
</verification>

<success_criteria>
- Console auth and camera refresh succeed via remote host when local is unreachable, and fail only when both fail
- Stream open, reconnect, and quality switch iterate [local, remote] candidates, local-first on every reconnect cycle
- All addresses editable from Settings (including adding local after remote-first setup); add-camera dialog supports remote URL
- Help page documents Remote access (VPN / Tailscale)
- No fallback path can throw an uncaught exception that kills a running audio stream
- No pubspec changes
</success_criteria>

<output>
Create `.planning/quick/260722-pdb-add-remote-url-fallback-connectivity-loc/260722-pdb-SUMMARY.md` when done
</output>
