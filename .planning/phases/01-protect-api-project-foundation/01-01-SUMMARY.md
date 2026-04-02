---
phase: 01-protect-api-project-foundation
plan: 01
subsystem: infra
tags: [flutter, riverpod, dio, flutter_secure_storage, go_router, material3, macos]

requires: []
provides:
  - "Flutter project scaffold with macOS and Android platform support"
  - "All Phase 1 dependencies installed and resolvable"
  - "Dark Material 3 theme with indigo seed color and typography overrides"
  - "macOS entitlements for network client and keychain access"
  - "Feature-first directory structure (auth, cameras, monitoring)"
  - "Wave 0 test stubs for AUTH-01, AUTH-02, AUTH-03"
  - "Bootstrap JSON fixture with 3 cameras for deterministic testing"
affects: [01-02-PLAN, 01-03-PLAN]

tech-stack:
  added: [flutter_riverpod 3.3.x, dio 5.9.x, flutter_secure_storage 10.x, go_router 17.x, riverpod_annotation 4.x, mockito 5.x, build_runner 2.x]
  patterns: [feature-first directory layout, dark-only Material 3 theme, abstract final class for constants]

key-files:
  created:
    - pubspec.yaml
    - lib/main.dart
    - lib/app.dart
    - lib/core/theme/app_theme.dart
    - lib/core/theme/spacing.dart
    - test/fixtures/bootstrap.json
    - test/core/api/protect_api_client_test.dart
    - test/core/api/dio_client_test.dart
    - test/features/cameras/camera_model_test.dart
    - test/features/cameras/camera_provider_test.dart
    - test/features/auth/auth_provider_test.dart
    - test/core/storage/secure_storage_test.dart
  modified:
    - macos/Runner/DebugProfile.entitlements
    - macos/Runner/Release.entitlements

key-decisions:
  - "Skipped riverpod_generator and riverpod_lint dev deps due to analyzer version conflicts with Dart 3.9.2 SDK; will use manual Riverpod providers until ecosystem catches up"
  - "Used ThemeData.dark(useMaterial3: true) constructor instead of deprecated copyWith(useMaterial3:) per Flutter 3.35 deprecation"

patterns-established:
  - "Feature-first layout: lib/features/{name}/screens|providers|models and lib/core/{name}"
  - "Theme: AppTheme.dark static getter with ColorScheme.fromSeed"
  - "Spacing: abstract final class Spacing with xs/sm/md/lg/xl/xxl constants"

requirements-completed: [PLAT-01]

duration: 4min
completed: 2026-04-02
---

# Phase 01 Plan 01: Project Scaffold Summary

**Flutter project with dark Material 3 theme, Riverpod/Dio/SecureStorage deps, macOS entitlements, and 25 Wave 0 test stubs**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-02T18:13:23Z
- **Completed:** 2026-04-02T18:17:54Z
- **Tasks:** 2
- **Files modified:** 75

## Accomplishments
- Flutter project scaffold with macOS and Android platforms, all core Phase 1 dependencies installed
- Dark Material 3 theme with indigo seed color, typography overrides per UI-SPEC, and status colors
- macOS entitlements configured for network client access and keychain sharing
- Feature-first directory structure per D-09/D-10 with auth, cameras, monitoring features
- 25 Wave 0 test stubs covering AUTH-01, AUTH-02, AUTH-03 plus bootstrap JSON fixture

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Flutter project with dependencies and macOS configuration** - `da4fde6` (feat)
2. **Task 2: Create Wave 0 test scaffolds and bootstrap fixture** - `a5c2769` (test)

## Files Created/Modified
- `pubspec.yaml` - Project configuration with all Phase 1 dependencies
- `lib/main.dart` - App entry point with ProviderScope wrapping App widget
- `lib/app.dart` - MaterialApp with dark theme and placeholder home screen
- `lib/core/theme/app_theme.dart` - Dark Material 3 theme with indigo seed, typography, status colors
- `lib/core/theme/spacing.dart` - Spacing constants (xs through xxl)
- `macos/Runner/DebugProfile.entitlements` - Network client + keychain + JIT entitlements
- `macos/Runner/Release.entitlements` - Network client + keychain entitlements
- `test/fixtures/bootstrap.json` - 3-camera fixture (Nursery, Bedroom connected; Garage disconnected)
- `test/core/api/protect_api_client_test.dart` - 7 stub tests for Protect API auth and bootstrap
- `test/core/api/dio_client_test.dart` - 2 stub tests for self-signed cert handling
- `test/features/cameras/camera_model_test.dart` - 5 stub tests for camera model parsing
- `test/features/cameras/camera_provider_test.dart` - 3 stub tests for camera selection logic
- `test/features/auth/auth_provider_test.dart` - 5 stub tests for auth state management
- `test/core/storage/secure_storage_test.dart` - 3 stub tests for credential persistence

## Decisions Made
- Skipped `riverpod_generator` and `riverpod_lint` dev dependencies due to analyzer version conflicts with Dart SDK 3.9.2 and `riverpod_annotation 4.x`. Manual Riverpod providers will be used until ecosystem compatibility resolves.
- Used `ThemeData.dark(useMaterial3: true)` constructor instead of deprecated `copyWith(useMaterial3:)` pattern per Flutter 3.35 deprecation warnings.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed riverpod_generator and riverpod_lint from dev deps**
- **Found during:** Task 1 (dependency installation)
- **Issue:** `riverpod_generator` and `riverpod_lint` have incompatible analyzer version constraints with `riverpod_annotation 4.x` on Dart SDK 3.9.2. Version solving fails.
- **Fix:** Installed only `build_runner` and `mockito` as dev deps. Code generation can be added later when packages are compatible.
- **Files modified:** pubspec.yaml
- **Verification:** `flutter pub get` succeeds, `flutter analyze` clean
- **Committed in:** da4fde6 (Task 1 commit)

**2. [Rule 1 - Bug] Fixed deprecated useMaterial3 usage**
- **Found during:** Task 1 (flutter analyze verification)
- **Issue:** `ThemeData.dark().copyWith(useMaterial3: true)` triggers deprecation warning in Flutter 3.35
- **Fix:** Changed to `ThemeData.dark(useMaterial3: true)` constructor pattern
- **Files modified:** lib/core/theme/app_theme.dart
- **Verification:** `flutter analyze` returns 0 issues
- **Committed in:** da4fde6 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes necessary for correct dependency resolution and clean analysis. No scope creep.

## Issues Encountered
- `flutter build macos --debug` fails because Xcode is not fully installed on this machine (only command-line tools). This is an environment limitation, not a code issue. The project structure is verified correct via `flutter analyze` (0 issues) and `flutter test` (25 passing).

## Known Stubs
None -- all test stubs are intentional Wave 0 placeholders to be implemented in Plans 02 and 03 as specified.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Project scaffold complete, ready for Plan 02 (Protect API client implementation)
- All test stubs in place for AUTH-01, AUTH-02, AUTH-03 requirement coverage
- Xcode full installation needed before `flutter build macos` will work

## Self-Check: PASSED

All 12 created files verified present. Both task commits (da4fde6, a5c2769) verified in git log.

---
*Phase: 01-protect-api-project-foundation*
*Completed: 2026-04-02*
