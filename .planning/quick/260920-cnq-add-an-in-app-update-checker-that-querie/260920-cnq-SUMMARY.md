---
phase: quick-260920-cnq
plan: 01
subsystem: core
tags: [updates, github-api, networking, ui, riverpod]
status: complete
requires:
  - storageProvider (lib/core/storage/storage_service.dart, lib/features/auth/providers/auth_provider.dart)
  - openExternalLink / tryParseLaunchableLink (lib/core/services/external_link_launcher.dart)
  - PackageInfo.fromPlatform (package_info_plus)
provides:
  - AppUpdate model + tolerant release parsing
  - isNewerVersion / selectUpdate pure decision functions
  - UpdateChecker (Dio, injectable HttpClientAdapter seam)
  - updateCheckerProvider / updateCheckProvider
  - rememberDismissedUpdate + kDismissedUpdateVersionKey
  - UpdateBanner (self-hiding shell strip)
affects:
  - lib/core/widgets/main_shell.dart (body column gained one child)
tech-stack:
  added: []
  patterns:
    - "Scripted HttpClientAdapter test harness (copied from protect_api_client_test)"
    - "FLUTTER_TEST network guard following AppLogger.fileSinkEnabled"
    - "Self-hiding SizedBox.shrink shell widget (ActiveSessionBar precedent)"
key-files:
  created:
    - lib/core/services/update_checker.dart
    - lib/core/widgets/update_banner.dart
    - test/core/services/update_checker_test.dart
    - test/core/widgets/update_banner_test.dart
  modified:
    - lib/core/widgets/main_shell.dart
    - README.md
decisions:
  - "Banner lives at the bottom of MainShell's body column (above ActiveSessionBar), not at the top: branch screens own their own Scaffold/AppBar, so a top strip would float above those app bars and under the status bar"
  - "Unauthenticated GitHub request, normal TLS verification — ProtectApiClient's badCertificateCallback deliberately NOT copied"
  - "Dismissal is per-version (string compare against the normalised tag), so a later release re-arms the strip"
  - "Riverpod 3 removed AsyncValue.valueOrNull; the banner reads AsyncValue.value, which is the nullable accessor (loading and error both read as null)"
metrics:
  duration: ~12min
  tasks: 2
  files: 6
  tests_added: 48
  completed: 2026-09-20
---

# Quick Task 260920-cnq: In-app update checker Summary

Roomtone now asks GitHub once per launch whether a newer release exists and, if so, shows a dismissible strip in the app shell that hands the parent the download in one tap.

## What Was Built

**Task 1 — `lib/core/services/update_checker.dart`** (commits `022c9fd` test, `c5e584e` impl)

The whole non-UI path, in one file:

- `AppUpdate` — immutable `version` / `releaseUrl` / `apkUrl`, with a `downloadUrl` getter that resolves to the APK asset on Android (guarded by `!kIsWeb && Platform.isAndroid`, as `lib/main.dart` does) and to the human-readable release page everywhere else or whenever no APK was published.
- `AppUpdate.fromJson` — tolerant by construction: every field read is a type-checked cast-or-null, a `draft`/`prerelease` release resolves to null, a wrong-typed `assets` degrades to "no APK" instead of throwing, and the whole body is try/caught.
- `isNewerVersion(latestTag, currentVersion)` over a private `_parseVersion` that strips one leading `v`, cuts at the first `+` or `-`, requires digits-only components, takes at most three and zero-pads to three. Either side failing to parse returns `false` — an unreadable tag can never produce a banner.
- `UpdateChecker` — its own Dio (5s connect / 8s receive, `validateStatus: <500`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: Roomtone`), plus a `@visibleForTesting setHttpClientAdapterForTest` seam mirroring `ProtectApiClient`. `fetchLatestRelease()` returns null for any non-200, any `DioException`, any non-Map body and any parse surprise — one `UPDATE` log line, never a throw.
- `selectUpdate({latest, currentVersion, dismissedVersion})` — pure; newer-and-not-dismissed is the only path that returns an update.
- `rememberDismissedUpdate(storage, version)` + `kDismissedUpdateVersionKey` (`dismissed_update_version`), writes swallowed on failure.
- `updateCheckerProvider` (overridable in widget tests) and `updateCheckProvider` — a `FutureProvider` that calls `ref.keepAlive()` (Riverpod 3 providers are auto-dispose by default, so without it a momentary loss of listeners would re-hit GitHub), returns null immediately under the `updateCheckDisabled` guard, and wraps its whole body in one try/catch.
- `updateCheckDisabled` — `Platform.environment.containsKey('FLUTTER_TEST')`, following `AppLogger.fileSinkEnabled`. This is what keeps the untouched `main_shell_test.dart` off the network.

**Task 2 — `lib/core/widgets/update_banner.dart` + shell wiring** (commits `a61acab` test, `43dd018` impl)

- `UpdateBanner` — a `ConsumerStatefulWidget` with one `_dismissed` field. Reads `ref.watch(updateCheckProvider).value` before any early return (so dismissal does not drop the pinned result), and renders `SizedBox.shrink()` when there is no update or it was dismissed. Otherwise a `secondaryContainer` strip (the calm pair, not the error pair — a new build is information, not a fault) with `Icons.system_update_outlined`, "Roomtone {version} is available", a `Download` `TextButton` and a tooltipped close `IconButton`.
- The download target passes through `tryParseLaunchableLink`; a non-http(s) URL renders **no button at all** rather than one that silently does nothing (T-CNQ-02).
- Dismiss sets state first (instant disappearance), then fire-and-forget `rememberDismissedUpdate`.
- Wired into `MainShell`'s body `Column` between `Expanded(navigationShell)` and `ActiveSessionBar`, with an inline comment recording the placement rationale.
- README gained one bullet under `## Persistence & UX`.

## Verification

| Gate | Result |
|------|--------|
| `flutter test test/core/services/update_checker_test.dart` | 40/40 pass |
| `flutter analyze --fatal-infos` (Task 1 files) | No issues found |
| `flutter test test/core/widgets/update_banner_test.dart test/core/widgets/main_shell_test.dart` | 10/10 pass |
| `flutter analyze --fatal-infos` (whole repo) | No issues found |
| `flutter test` (full suite) | **654/654 pass** |

Every behaviour bullet in the plan has a test. The fetch path is exercised through the scripted adapter for 200, 403, 404, 500, `connectionError`, `receiveTimeout`, an HTML body, a `text/plain` body, a JSON array and an empty body — all null, none throwing. The request assertions pin the URL to `https://api.github.com/repos/fvoska/rtsp-mixer/releases/latest` and assert no `authorization` header is present.

`main_shell_test.dart` was **not** modified and still passes, which is the evidence that the shell wiring introduced no network call or pending timer under test.

## Deviations from Plan

**1. [Rule 3 - Blocking] `AsyncValue.valueOrNull` does not exist in Riverpod 3.4.3**
- **Found during:** Task 2
- **Issue:** The plan specified `ref.watch(updateCheckProvider).valueOrNull`; that getter was removed in Riverpod 3, so the banner failed to compile.
- **Fix:** Used `.value`, which in Riverpod 3 is the nullable accessor with identical semantics for this use (loading and error both read as null). Comment added at the call site recording why.
- **Files modified:** `lib/core/widgets/update_banner.dart`
- **Commit:** `43dd018`

**2. [Clarification] `StorageService` path and key visibility**
- The plan referenced the storage service as if under `lib/core/services/`; it actually lives at `lib/core/storage/storage_service.dart` — imports adjusted.
- The dismissed-version key is a **public** `const kDismissedUpdateVersionKey` rather than a private one, so the banner test can read the value back out of in-memory storage without duplicating the literal. No behavioural difference.

No other deviations. No architectural changes, no authentication gates, no `pubspec.yaml` change (all four dependencies were already present, so no package-legitimacy gate applied).

## Threat Mitigations Applied

| Threat ID | How it is mitigated in the code |
|-----------|--------------------------------|
| T-CNQ-01 (spoofing) | `UpdateChecker`'s Dio has **no** `badCertificateCallback`; a comment in the constructor records that the omission is deliberate and why |
| T-CNQ-02 (tampering) | `tryParseLaunchableLink` gates the URL; a non-http(s) target renders no action, and `openExternalLink` re-checks the scheme |
| T-CNQ-03 (info disclosure) | Fixed URL, generic `User-Agent: Roomtone`, no token, no credentials, no device identifiers; asserted by test (no `authorization` header) |
| T-CNQ-04 (DoS) | One request per launch, 5s/8s timeouts, lazy provider off the startup path, whole path try/caught to null |

## Known Stubs

None. No stubbed data paths, no skipped tests, no unrun `<verify>` commands.

## Human Verification (optional, not blocking)

Not performed in this session — it needs a device or a `flutter run` with `version:` temporarily lowered below the live GitHub release. The plan's automated gates all pass; the human check would confirm the strip's live appearance, that Download opens the browser, and that dismissal survives a relaunch.

## Self-Check: PASSED

- All four created files exist on disk; `lib/core/widgets/main_shell.dart` and `README.md` modified.
- All four commits (`022c9fd`, `c5e584e`, `a61acab`, `43dd018`) present in `git log`.
- `git status --short` clean; no tracked file deleted by any commit in this task.
