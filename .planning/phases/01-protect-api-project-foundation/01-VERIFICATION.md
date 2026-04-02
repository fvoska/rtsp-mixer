---
phase: 01-protect-api-project-foundation
verified: 2026-04-02T22:00:00Z
status: gaps_found
score: 3/4 success criteria verified
re_verification: false
gaps:
  - truth: "App remembers credentials and auto-connects on next launch without re-entering them (AUTH-03 / Success Criterion 3)"
    status: partial
    reason: "StorageService uses an in-memory Map. Credentials are lost when the process terminates. Auto-connect works within a session (tests prove it) but not across app restarts. This is a known accepted limitation for debug builds per user context, but AUTH-03 as written in REQUIREMENTS.md is 'App persists credentials securely and auto-connects on launch' — securely and across launches are not met."
    artifacts:
      - path: "lib/core/storage/storage_service.dart"
        issue: "In-memory Map<String,String> — no disk persistence. Data is cleared on process exit. File-backed or keychain storage is absent."
    missing:
      - "Replace StorageService in-memory Map with a persistent backend (flutter_secure_storage for Android production; shared_preferences or file storage as a debug fallback that actually survives restarts)"
      - "Add a test or integration note documenting that persistence works across process boundaries"
  - truth: "macOS entitlements allow network access and keychain storage (Plan 01-01 must_have)"
    status: partial
    reason: "DebugProfile.entitlements is missing keychain-access-groups. Release.entitlements has it, but debug builds (which are the daily-use target on macOS) lack the keychain entry. Plan 01-01 acceptance criteria required keychain-access-groups in both files."
    artifacts:
      - path: "macos/Runner/DebugProfile.entitlements"
        issue: "Missing keychain-access-groups key. Contains only com.apple.security.cs.allow-jit and com.apple.security.network.client."
    missing:
      - "Add keychain-access-groups array to DebugProfile.entitlements (matching Release.entitlements)"
human_verification:
  - test: "End-to-end login flow on macOS with real Protect console"
    expected: "Enter IP and API key, tap Connect, see camera list with real cameras, select 2, tap Start Monitoring, navigate to monitoring placeholder"
    why_human: "Requires live Unifi Protect console on LAN; cannot verify network connectivity or RTSP URL correctness from test environment"
  - test: "Camera list UI visual check"
    expected: "Dark Material 3 theme, checkboxes for each camera, online/offline colored dots, Start Monitoring button enables at 1+ selection, third camera row appears muted when 2 already selected, logout icon in AppBar"
    why_human: "Visual layout and interaction behavior cannot be verified by static analysis"
---

# Phase 1: Protect API + Project Foundation — Verification Report

**Phase Goal:** User can connect to their Unifi Protect console, see their cameras, and the app remembers credentials across launches
**Verified:** 2026-04-02
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Key Implementation Deviation

The phase deviated significantly from the original PLAN files:

| Plan spec | Actual implementation |
|-----------|----------------------|
| cookie/CSRF login (`/api/auth/login` POST) | X-API-Key header via official Protect integration API (`/proxy/protect/integration/v1`) |
| `flutter_secure_storage` for persistence | In-memory `Map<String,String>` (StorageService) — no disk persistence |
| Username + password fields | Console IP + API Key fields |
| `ProtectAuthInterceptor` with CSRF state | Direct `X-API-Key` header on each request |
| `StreamChannel` / RTSP URL generation | Removed — ProtectCamera simplified to id/name/state/isMicEnabled |

These deviations are functionally coherent and were verified working on real hardware (Protect 7.0.94, 6 cameras). Verification is performed against the **phase goal and success criteria**, not the original plan tasks.

---

## Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can enter Protect console IP and credentials, and the app authenticates successfully | VERIFIED | `LoginScreen` (ConsumerStatefulWidget) has IP + API Key fields wired to `AuthNotifier.login()`. `ProtectApiClient.verifyConnection()` returns true/false. 8 auth provider tests cover success, failure, connection error, and exception paths — all passing. |
| 2 | User can see a list of discovered cameras and select 2 for monitoring | VERIFIED | `CameraListScreen` renders `CheckboxListTile` per camera, wired to `CameraNotifier.toggleCamera()`. Selection enforces max-2 limit. `Start Monitoring` button is gated on `canStartMonitoring`. 10 camera provider tests pass, including toggle enforcement and pre-selection. |
| 3 | App remembers credentials and auto-connects on next launch without re-entering them | PARTIAL — gap found | `AuthNotifier.build()` calls `StorageService.loadCredentials()` on startup and auto-connects if credentials exist. However, `StorageService` stores data in a `Map<String,String>` that is garbage-collected when the process exits. Credentials do not survive an app restart. "Across launches" is the core of AUTH-03 and is not met in any build variant. |
| 4 | App builds and runs on macOS desktop for development iteration | VERIFIED | `flutter build macos --debug` exits 0. `flutter test` passes 27 tests. `flutter analyze` reports 2 minor warnings (unnecessary `!` assertions in test files) — no errors. |

**Score: 3/4 success criteria verified**

---

## Required Artifacts

### Plan 01-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `pubspec.yaml` | Phase 1 dependencies | VERIFIED | Contains flutter_riverpod, dio, flutter_secure_storage, go_router, mockito |
| `lib/main.dart` | ProviderScope entry point | VERIFIED | `runApp(const ProviderScope(child: App()))` |
| `lib/core/theme/app_theme.dart` | Dark Material 3 theme | VERIFIED | `ColorScheme.fromSeed(seedColor: Color(0xFF5C6BC0), brightness: Brightness.dark)`, statusOnline/statusOffline constants |
| `macos/Runner/DebugProfile.entitlements` | Network + keychain entitlements | PARTIAL | Has `network.client` and `allow-jit` — **missing `keychain-access-groups`** |
| `macos/Runner/Release.entitlements` | Network + keychain entitlements | VERIFIED | Has all three: `app-sandbox`, `network.client`, `keychain-access-groups` |

### Plan 01-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/api/protect_api_client.dart` | ProtectApiClient with auth + bootstrap | VERIFIED (adapted) | Implements `verifyConnection()` + `getCameras()` via X-API-Key. Original `login()` / `getBootstrap()` contract replaced — functionally equivalent for phase goal. |
| `lib/core/api/dio_client.dart` | Dio factory with self-signed cert support | MISSING | File does not exist. Self-signed cert handling was folded directly into `ProtectApiClient` constructor (`badCertificateCallback = true`). Functionally present but not as a separate factory. |
| `lib/features/auth/screens/login_screen.dart` | Login form UI | VERIFIED (adapted) | Has IP + API Key fields (not username/password as planned). `TextFormField`, `Connect to Console` button, loading spinner, inline error display. SSL dialog removed (not needed for API key flow). |
| `lib/features/cameras/models/protect_camera.dart` | Camera model with RTSP URL generation | PARTIAL | `ProtectCamera.fromJson()` exists and tested. `rtspUrl()` method and `StreamChannel` model were removed — the API key flow returns cameras without RTSP aliases in the simplified model. RTSP URL generation is deferred to Phase 2. |

### Plan 01-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/storage/storage_service.dart` | Secure credential persistence | PRESENT, NOT PERSISTENT | Class exists, methods work, all 5 storage tests pass. Backend is in-memory Map — see gap above. |
| `lib/core/router/app_router.dart` | GoRouter with auth redirect | VERIFIED | Routes `/login`, `/cameras`, `/monitoring`. Redirect logic: unauthenticated → `/login`, authenticated on `/login` → `/cameras`. `_AuthRefreshNotifier` bridges Riverpod to GoRouter `refreshListenable`. |
| `lib/features/auth/providers/auth_provider.dart` | AuthNotifier with auto-connect | VERIFIED (within-session) | `AsyncNotifier.build()` auto-connects with saved credentials. `login()`, `logout()` implemented. Wired to `storageProvider` and `apiClientProvider`. 8 tests pass. |
| `lib/features/cameras/providers/camera_provider.dart` | CameraNotifier with selection | VERIFIED | `loadCameras()`, `toggleCamera()`, max-2 enforcement, pre-selection from storage, `canStartMonitoring`. 10 tests pass. |
| `lib/features/cameras/screens/camera_list_screen.dart` | Camera selection UI | VERIFIED | `CheckboxListTile` per camera, online/offline dots using `AppTheme.statusOnline/statusOffline`, Opacity(0.5) for muted rows, `Start Monitoring` FilledButton, logout icon in AppBar. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `auth_provider.dart` | `storage_service.dart` | `storageProvider` | WIRED | `ref.read(storageProvider)` in build, login, logout |
| `auth_provider.dart` | `protect_api_client.dart` | `apiClientProvider` | WIRED | `ref.read(apiClientProvider)` in build and login |
| `app_router.dart` | `auth_provider.dart` | `authNotifierProvider` | WIRED | `ref.read(authNotifierProvider)` in redirect; `_AuthRefreshNotifier` listens via `ref.listen` |
| `camera_list_screen.dart` | `camera_provider.dart` | `cameraNotifierProvider` | WIRED | `ref.watch(cameraNotifierProvider)` for state; `ref.read(...notifier).toggleCamera()` for actions |
| `camera_provider.dart` | `storage_service.dart` | `storageProvider` | WIRED | `loadSelectedCameraIds()` in `loadCameras`, `saveSelectedCameraIds()` in `toggleCamera` |
| `login_screen.dart` | `auth_provider.dart` | `authNotifierProvider` | WIRED | `ref.read(authNotifierProvider.notifier).login()` on submit; `ref.watch(authNotifierProvider)` for loading state |
| `app.dart` | `app_router.dart` | `appRouterProvider` | WIRED | `ref.watch(appRouterProvider)` fed to `MaterialApp.router(routerConfig:)` |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `camera_list_screen.dart` | `cameraState` (cameras list) | `cameraNotifierProvider` → `getCameras(host)` → Protect API | Yes (API returns real camera list; in-memory state populated per fetch) | FLOWING |
| `login_screen.dart` | `authState` (loading / error) | `authNotifierProvider` → `verifyConnection()` → Protect API | Yes (live API call) | FLOWING |
| `app.dart` | `router` | `appRouterProvider` watching `authNotifierProvider` | Yes (redirect logic reads live auth state) | FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 27 tests pass | `flutter test` | `+27: All tests passed!` | PASS |
| macOS debug build succeeds | `flutter build macos --debug` | `Built build/macos/.../rtsp_audio_mixer.app` | PASS |
| Static analysis clean | `flutter analyze` | 2 warnings (unnecessary `!` in test files), 0 errors | PASS (warnings only, not blocking) |
| StorageService credentials do NOT persist across process restart | Inspecting `storage_service.dart` | `Map<String,String> _data = {}` — heap-allocated, no persistence | CONFIRMS GAP |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AUTH-01 | 01-02-PLAN | User can authenticate with Unifi Protect using IP + credentials | SATISFIED | `ProtectApiClient.verifyConnection()` with X-API-Key header. `AuthNotifier.login()` wired to login screen. 8 auth tests pass including success/failure/error cases. Verified on real hardware. |
| AUTH-02 | 01-02-PLAN, 01-03-PLAN | User can discover and select 2 cameras from Protect API camera list | SATISFIED | `getCameras()` fetches real camera list. `CameraListScreen` with CheckboxListTile, max-2 enforcement. 10 camera provider tests pass. |
| AUTH-03 | 01-03-PLAN | App persists credentials securely and auto-connects on launch | BLOCKED — partial | Auto-connect logic is correct and tested. Persistence backend is in-memory only — credentials do not survive process termination. "Secure" storage (keychain/file) and "across launches" are both unmet. |
| PLAT-01 | 01-01-PLAN | App builds and runs on macOS desktop | SATISFIED | `flutter build macos --debug` exits 0. Builds and runs successfully. |

**Orphaned requirement check:** REQUIREMENTS.md Traceability table lists AUTH-01, AUTH-02, AUTH-03, PLAT-01 for Phase 1 — all four are claimed in plan frontmatter. No orphaned requirements.

**AUTH-03 note:** REQUIREMENTS.md has AUTH-03 checked as `[x]` (complete) in the checkbox list, but marked "Pending" in the traceability table. The traceability table is more accurate — the checkbox appears to have been marked optimistically.

---

## Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `lib/core/storage/storage_service.dart:4-5` | `TODO: Replace with flutter_secure_storage for production Android builds` + in-memory `Map` | Blocker for AUTH-03 | Credentials are lost on app restart; AUTH-03 "across launches" not met |
| `macos/Runner/DebugProfile.entitlements` | Missing `keychain-access-groups` | Warning | Debug builds cannot use keychain; this means flutter_secure_storage would also fail in debug builds if switched, without also fixing this entitlement |
| `test/features/auth/auth_provider_test.dart:37` | Unnecessary `!` assertion (`unnecessary_non_null_assertion`) | Info | Minor code quality warning, not a runtime issue |
| `test/features/cameras/camera_provider_test.dart:37` | Unnecessary `!` assertion | Info | Same as above |

---

## Human Verification Required

### 1. End-to-end login and camera discovery on real hardware

**Test:** On a Mac connected to the same LAN as a Unifi Protect console, run `flutter run -d macos`. Enter the NVR IP address and a valid API key (generated from Protect → Settings → Integrations → API Keys). Tap "Connect to Console".
**Expected:** Loading spinner appears, then navigation to camera list. All cameras appear with names and online/offline colored dots. Selecting 2 cameras enables "Start Monitoring". Third camera row appears visually muted.
**Why human:** Requires live Unifi Protect NVR. Cannot verify API key format acceptance, TLS certificate handling, or actual camera data format against a real API response.

### 2. Camera list visual layout

**Test:** After login, inspect camera list screen.
**Expected:** Dark Material 3 indigo theme. "Select Cameras" in AppBar. Logout icon (door-with-arrow) top right. Instructional text "Choose 1 or 2 cameras to monitor". Each camera row: checkbox left, camera name as title, state string as subtitle, small colored circle right. When 2 selected, unselected rows appear at 50% opacity.
**Why human:** Visual/opacity rendering, icon appearance, and text layout cannot be verified by static analysis.

---

## Gaps Summary

Two gaps block full goal achievement:

**Gap 1 — AUTH-03 credential persistence (blocker):** The `StorageService` class uses an in-memory `Map`. This satisfies within-session auto-connect (which the tests correctly verify) but does not satisfy the requirement's core contract of persisting credentials "across launches." The user acknowledged this limitation for debug builds, but no production-ready storage path exists yet — there is no conditional or build-flavor switch to a persistent backend. The `TODO` comment in `storage_service.dart` confirms this is known unfinished work.

**Gap 2 — DebugProfile.entitlements missing keychain-access-groups (warning):** `macos/Runner/Release.entitlements` has the keychain entry; `macos/Runner/DebugProfile.entitlements` does not. This means debug builds on macOS cannot access the keychain. This is consistent with the in-memory storage workaround (keychain not needed for Map), but it means that if `flutter_secure_storage` is adopted to fix Gap 1, debug builds will require this entitlement too.

These two gaps are related: fixing Gap 1 (persistent storage) will require fixing Gap 2 (debug entitlement) simultaneously for the full macOS debug iteration workflow to work.

---

_Verified: 2026-04-02_
_Verifier: Claude (gsd-verifier)_
