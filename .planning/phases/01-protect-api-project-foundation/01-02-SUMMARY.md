---
phase: 01-protect-api-project-foundation
plan: 02
subsystem: api
tags: [dio, protect-api, csrf, rtsp, flutter, material3, login-screen]

requires:
  - phase: 01-protect-api-project-foundation plan 01
    provides: "Flutter project scaffold, dependencies, test stubs, bootstrap fixture"
provides:
  - "ProtectApiClient with login (CSRF retry) and bootstrap fetch"
  - "ProtectCamera and StreamChannel data models with JSON parsing and RTSP URL generation"
  - "Dio factory with self-signed certificate acceptance"
  - "ProtectAuthInterceptor for automatic CSRF/cookie header injection"
  - "AppError type for structured API error handling"
  - "AuthState model for authentication flow state"
  - "LoginScreen UI with form validation, inline errors, and SSL certificate dialog"
affects: [01-03-PLAN]

tech-stack:
  added: [mockito-codegen]
  patterns: [Dio interceptor for auth headers, AppError structured errors, callback-based screen (pre-Riverpod wiring)]

key-files:
  created:
    - lib/core/api/protect_api_client.dart
    - lib/core/api/dio_client.dart
    - lib/core/api/protect_auth_interceptor.dart
    - lib/core/models/app_error.dart
    - lib/features/cameras/models/protect_camera.dart
    - lib/features/cameras/models/stream_channel.dart
    - lib/features/auth/models/auth_state.dart
    - lib/features/auth/screens/login_screen.dart
    - test/core/api/protect_api_client_test.mocks.dart
  modified:
    - lib/app.dart
    - test/core/api/protect_api_client_test.dart
    - test/core/api/dio_client_test.dart
    - test/features/cameras/camera_model_test.dart

key-decisions:
  - "Used validateStatus option in Dio to handle 401/403 without throwing, enabling cleaner control flow for CSRF retry logic"
  - "LoginScreen uses callback parameter (onConnect) instead of direct Riverpod wiring -- Plan 03 will wire the provider"
  - "AppError implements Exception for throwability in API client error mapping"

patterns-established:
  - "API error mapping: DioException types mapped to AppErrorType enum for UI consumption"
  - "Auth interceptor pattern: ProtectAuthInterceptor extracts CSRF/cookie from responses, injects on requests"
  - "Server error inline display: LoginScreen maps AppErrorType to specific field errors (D-03)"

requirements-completed: [AUTH-01, AUTH-02]

duration: 5min
completed: 2026-04-02
---

# Phase 01 Plan 02: Protect API Client & Login Screen Summary

**Protect API client with CSRF-retry login and bootstrap camera discovery, plus login screen UI with inline error mapping and SSL certificate dialog**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-02T18:19:57Z
- **Completed:** 2026-04-02T18:25:10Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments
- ProtectApiClient authenticates with Protect console (login with CSRF retry on 403) and fetches bootstrap camera list
- Camera data models parse bootstrap JSON and generate RTSP URLs (encrypted and unencrypted)
- Login screen with Console IP, Username, Password fields, inline error display, SSL certificate warning dialog, and loading state
- 19 new tests covering API client (login success/failure/CSRF retry/connection error), bootstrap parsing, camera models, Dio factory

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement data models, Dio client factory, and Protect API client with tests** - `27d63e2` (feat)
2. **Task 2: Build login screen with form validation and inline errors** - `ecafb12` (feat)

## Files Created/Modified
- `lib/core/api/protect_api_client.dart` - Single API client for auth + bootstrap (D-11)
- `lib/core/api/dio_client.dart` - Dio factory with self-signed cert support
- `lib/core/api/protect_auth_interceptor.dart` - CSRF token and cookie interceptor
- `lib/core/models/app_error.dart` - Structured error types for UI consumption
- `lib/features/cameras/models/protect_camera.dart` - Camera model with RTSP URL generation
- `lib/features/cameras/models/stream_channel.dart` - RTSP channel model
- `lib/features/auth/models/auth_state.dart` - Auth state with status enum
- `lib/features/auth/screens/login_screen.dart` - Login form with inline errors and SSL dialog
- `lib/app.dart` - Updated to route to LoginScreen as home
- `test/core/api/protect_api_client_test.dart` - 8 tests for API client
- `test/core/api/dio_client_test.dart` - 2 tests for Dio factory
- `test/features/cameras/camera_model_test.dart` - 9 tests for camera/channel models
- `test/core/api/protect_api_client_test.mocks.dart` - Generated Dio mock

## Decisions Made
- Used `validateStatus` option in Dio POST to handle 401/403 responses without throwing exceptions, enabling cleaner CSRF retry control flow
- LoginScreen takes an `onConnect` callback parameter rather than directly depending on Riverpod -- Plan 03 will wire the auth provider
- `AppError` implements `Exception` so it can be thrown from the API client and caught in the UI layer

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused _host field from ProtectApiClient**
- **Found during:** Task 2 (flutter analyze verification)
- **Issue:** `_host` field was set but never read, causing analyzer warning
- **Fix:** Removed the field since it's not needed (host is passed per-call)
- **Files modified:** lib/core/api/protect_api_client.dart
- **Verification:** `flutter analyze` returns 0 issues
- **Committed in:** ecafb12 (Task 2 commit)

**2. [Rule 1 - Bug] Removed unused private constructor from AuthState**
- **Found during:** Task 2 (flutter analyze verification)
- **Issue:** `AuthState._` private constructor and its optional parameters were unused since all named constructors initialize fields directly
- **Fix:** Removed private constructor, named constructors use direct field initialization
- **Files modified:** lib/features/auth/models/auth_state.dart
- **Verification:** `flutter analyze` returns 0 issues
- **Committed in:** ecafb12 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes address analyzer warnings. No scope creep.

## Issues Encountered
- `flutter build macos --debug` fails because Xcode is not fully installed on this machine (only command-line tools). This is the same environment limitation documented in Plan 01. Verification performed via `flutter analyze` (0 issues) and `flutter test` (30 passing).

## Known Stubs
None -- all code is fully implemented. The `onConnect` callback in LoginScreen is a design pattern (not a stub), to be wired to Riverpod in Plan 03.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- API client and data models ready for Plan 03 to wire Riverpod providers
- Login screen ready for Plan 03 to connect to auth provider
- Full Xcode installation still needed for `flutter build macos`

## Self-Check: PASSED

All 9 created files verified present. Both task commits (27d63e2, ecafb12) verified in git log.

---
*Phase: 01-protect-api-project-foundation*
*Completed: 2026-04-02*
