---
phase: quick-260920-cnq
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/core/services/update_checker.dart
  - test/core/services/update_checker_test.dart
  - lib/core/widgets/update_banner.dart
  - lib/core/widgets/main_shell.dart
  - test/core/widgets/update_banner_test.dart
  - README.md
autonomous: true
requirements: [QUICK-260920-CNQ]
must_haves:
  truths:
    - "When the newest GitHub release of fvoska/rtsp-mixer is a higher version than the running build, a dismissible strip appears in the app shell naming the new version"
    - "Tapping the strip's download action leaves the app for the browser at the release's APK (Android) or release page (elsewhere)"
    - "Dismissing the strip hides it for that version permanently — it returns only when a newer version than the dismissed one ships"
    - "No update-check failure is observable: offline, rate-limited, 404, malformed JSON, unparseable tag or missing package info all resolve to no banner, a log line, and zero effect on startup or on a running stream"
    - "The check costs one GitHub request per app launch, runs unauthenticated, and never runs under `flutter test`"
  artifacts:
    - path: lib/core/services/update_checker.dart
      provides: "AppUpdate model, UpdateChecker (Dio + injectable HttpClientAdapter seam), pure version comparison, updateCheckProvider"
    - path: lib/core/widgets/update_banner.dart
      provides: "UpdateBanner — self-hiding Material 3 strip with download + dismiss actions"
  key_links:
    - from: updateCheckProvider
      to: UpdateBanner
      via: "ref.watch(updateCheckProvider).valueOrNull — null means render nothing"
    - from: UpdateBanner dismiss action
      to: updateCheckProvider on next launch
      via: "StorageService key `dismissed_update_version` compared against the fetched tag"
    - from: MainShell body Column
      to: UpdateBanner
      via: "inserted directly above ActiveSessionBar, so it shows on every tab"
---

<objective>
Tell the parent when a newer Roomtone build exists, and hand them the download
in one tap.

Purpose: this app is side-loaded from GitHub releases — there is no store to
nag the user, so an installed build silently rots. A check against the public
releases API on launch closes that gap without any release pipeline work.

Output: `UpdateChecker` + `updateCheckProvider` (network → parsed decision),
an `UpdateBanner` strip wired into `MainShell`, unit tests for the comparison
and fetch paths, widget tests for the banner, and a README bullet.

Non-goals (deliberately out of scope): a Settings toggle, a manual
"check now" button, background/periodic polling, in-app APK install, and
authenticated GitHub requests.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md

Patterns this plan copies — read before writing code:
@lib/core/api/protect_api_client.dart
@lib/core/services/external_link_launcher.dart
@lib/core/providers/settings_provider.dart
@lib/core/widgets/main_shell.dart
@lib/features/peer/screens/host_screen.dart
@test/core/api/protect_api_client_test.dart

Already-available dependencies (pubspec.yaml is NOT modified by this plan):
`dio ^5.9.2`, `package_info_plus ^10.1.0`, `url_launcher ^6.3.2`,
`flutter_riverpod ^3.3.1`, `flutter_secure_storage` (via `StorageService`).
No package install, therefore no package legitimacy gate.
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: GitHub release check — fetch, compare, decide (no UI)</name>
  <files>lib/core/services/update_checker.dart, test/core/services/update_checker_test.dart</files>
  <read_first>lib/core/api/protect_api_client.dart (Dio construction, `setHttpClientAdapterForTest` seam, DioException handling), test/core/api/protect_api_client_test.dart (`_ScriptedAdapter` — copy this harness), lib/core/providers/settings_provider.dart (tolerant decode style, `storageProvider` usage, `appLog` tagging)</read_first>
  <behavior>
    Pure version comparison (`isNewerVersion(latestTag, currentVersion)`):
    - "v1.15.0" over "1.14.0" → true; "1.14.1" over "1.14.0" → true; "v2.0.0" over "1.14.0" → true
    - "v1.14.0" over "1.14.0" → false; "v1.13.9" over "1.14.0" → false
    - "v1.14" over "1.14.0" → false (missing components pad with zero)
    - "v1.15.0+3" over "1.14.0+22" → true (build metadata after `+` ignored)
    - "v1.15.0-rc.1" over "1.14.0" → true (pre-release suffix after `-` ignored for the numeric compare)
    - "latest", "", "v", "1.x.0" on either side → false (unparseable never produces a banner)
    Release parsing (`AppUpdate.fromJson`):
    - tag_name "v1.15.0" → version "1.15.0"; html_url kept as releaseUrl
    - first asset whose name ends in `.apk` → apkUrl; no such asset → apkUrl null
    - `draft: true` or `prerelease: true` → null (guard, even though /releases/latest excludes them)
    - missing/wrong-typed tag_name or html_url → null, never a throw
    Fetch (`UpdateChecker.fetchLatestRelease`, driven by a scripted HttpClientAdapter):
    - 200 + well-formed body → AppUpdate with the parsed fields; the request went to
      `https://api.github.com/repos/fvoska/rtsp-mixer/releases/latest` with no Authorization header
    - 403 (rate limited), 404, 500, a connection-error DioException, a non-JSON body, a JSON array → null + one log line, no throw
    Decision (`selectUpdate(latest:, currentVersion:, dismissedVersion:)`):
    - newer + not dismissed → the AppUpdate
    - newer but dismissedVersion equals its version → null
    - newer and dismissedVersion is an OLDER version → the AppUpdate (dismissal is per-version, not forever)
    - latest null, or not newer → null
  </behavior>
  <action>
Create `lib/core/services/update_checker.dart` holding the whole non-UI path.

Model: an immutable `AppUpdate` with `version` (tag with any leading `v`
stripped), `releaseUrl` (the release's `html_url`) and `apkUrl` (nullable
`browser_download_url` of the first asset whose `name` ends in `.apk` — CI
publishes `rtsp-mixer-<version>-android.apk`). Add a `downloadUrl` getter that
returns `apkUrl` on Android when present and `releaseUrl` everywhere else, so a
desktop dev build links to the human-readable page and a phone links straight at
the installer. Guard the `Platform.isAndroid` read with `kIsWeb` exactly as
`lib/main.dart` does. Give it a tolerant static `fromJson` returning
`AppUpdate?`: every field read is a type-checked cast-or-null, and a draft or
pre-release release resolves to null.

Version comparison: a private `List&lt;int&gt;? _parseVersion(String)` that trims,
strips one leading `v`/`V`, cuts the string at the first `+` or `-`, splits on
`.`, requires every remaining component to be digits-only, takes at most three
and zero-pads to three; anything else resolves to null. Expose
`bool isNewerVersion(String latestTag, String currentVersion)` doing a
component-wise compare, returning false whenever either side fails to parse.
Both are top-level and `@visibleForTesting`-free — the tests call them directly.

`UpdateChecker` class: constructor builds its own `Dio` with
`connectTimeout` 5s, `receiveTimeout` 8s, `validateStatus: (s) =&gt; s != null &amp;&amp; s &lt; 500`,
and headers `Accept: application/vnd.github+json`,
`X-GitHub-Api-Version: 2022-11-28`, `User-Agent: Roomtone`. Do NOT copy
`ProtectApiClient`'s `badCertificateCallback` — this talks to the public
internet and must keep normal TLS verification. Do NOT send any Authorization
header; the endpoint is public and unauthenticated by design. Expose
`@visibleForTesting void setHttpClientAdapterForTest(HttpClientAdapter)`
mirroring `ProtectApiClient`. `Future&lt;AppUpdate?&gt; fetchLatestRelease()` issues
the GET, returns null for any status other than 200, and wraps the whole body
in try/catch (`on DioException` plus a bare `catch`) so a transport failure, a
non-JSON body or a shape surprise all log via `appLog('UPDATE', ...)` and
resolve to null. Note in a doc comment that unauthenticated GitHub API calls
are rate limited per-IP (60/hour) and that one call per launch stays far under it.

`selectUpdate({required AppUpdate? latest, required String currentVersion, required String? dismissedVersion})`:
a pure top-level function returning `AppUpdate?` that applies `isNewerVersion`
and then the dismissal comparison (`dismissedVersion` is stored with the same
normalisation as `AppUpdate.version`, so compare the strings directly).

Providers, co-located in this file (precedent: `audioHandlerProvider` lives in
`lib/features/monitoring/services/audio_handler.dart`):
- `updateCheckerProvider` — a plain `Provider` returning `UpdateChecker()`, so
  widget tests can override it.
- `updateCheckProvider` — `FutureProvider&lt;AppUpdate?&gt;` that calls
  `ref.keepAlive()` first (Riverpod 3 providers are auto-dispose by default and
  this must hit GitHub at most once per launch), returns null immediately when
  the test guard is set, then reads `PackageInfo.fromPlatform().version`, reads
  the dismissed version from `ref.read(storageProvider)` (key constant
  `dismissed_update_version`, declared here as `SettingsNotifier` declares its
  own `_storageKey`), awaits `fetchLatestRelease()` and returns
  `selectUpdate(...)`. The entire body sits inside one try/catch that logs and
  returns null — per CLAUDE.md this is a nice-to-have and is never allowed to
  surface an error state or block anything.

Test guard: a file-level `final bool updateCheckDisabled = kIsWeb ? false : Platform.environment.containsKey('FLUTTER_TEST');`
following `AppLogger.fileSinkEnabled`'s precedent, consulted only by the
provider (never by `UpdateChecker`, whose tests must exercise the real fetch
path through the scripted adapter). This keeps every existing widget test —
`test/core/widgets/main_shell_test.dart` included — off the network.

Also expose `Future&lt;void&gt; rememberDismissedUpdate(StorageService storage, String version)`
that writes the key inside try/catch and swallows failures, so the banner has
one call to make.

Tests in `test/core/services/update_checker_test.dart`: copy the
`_ScriptedAdapter` harness from `test/core/api/protect_api_client_test.dart`,
call `installAppLoggerTestIsolation()` from `test/support/logging.dart` at the
top of `main()`, and cover every bullet in the behavior block. Assert on the
recorded `RequestOptions` that the URL is the fvoska/rtsp-mixer latest-release
endpoint and that no `authorization` header is present.
  </action>
  <verify>
    <automated>cd /home/user/rtsp-mixer &amp;&amp; flutter test test/core/services/update_checker_test.dart &amp;&amp; flutter analyze --fatal-infos lib/core/services/update_checker.dart test/core/services/update_checker_test.dart</automated>
  </verify>
  <done>Every behavior bullet has a passing test; a scripted 200 yields an AppUpdate, and 403/404/500/connection-error/malformed-body each yield null with no thrown exception; `analyze --fatal-infos` is clean.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: UpdateBanner strip in the app shell, dismissible per version</name>
  <files>lib/core/widgets/update_banner.dart, lib/core/widgets/main_shell.dart, test/core/widgets/update_banner_test.dart, README.md</files>
  <read_first>lib/features/peer/screens/host_screen.dart (the `_ErrorBanner` container recipe — padding, `Radii.inner`, container/on-container colour pair), lib/features/monitoring/widgets/active_session_bar.dart (self-hiding shell widget returning `SizedBox.shrink`), lib/core/services/external_link_launcher.dart (`tryParseLaunchableLink`, `openExternalLink`, the `externalLinkOpener` test seam), test/core/widgets/main_shell_test.dart (shell test scaffolding)</read_first>
  <behavior>
    With `updateCheckProvider` overridden to an AppUpdate for version 1.15.0:
    - the strip renders and its text names the version (e.g. contains "1.15.0")
    - tapping the download action calls the `externalLinkOpener` seam exactly once with the update's downloadUrl
    - tapping the dismiss action removes the strip from the tree in the same frame
    - after dismissing, the storage-backed dismissed-version key holds "1.15.0"
    With the provider overridden to null (no update), and while it is still loading:
    - nothing is rendered (`SizedBox.shrink`), no layout space is taken
    With an AppUpdate whose downloadUrl is not an http(s) URL:
    - the strip still renders, but no download action is offered (inert beats fake-tappable, matching the changelog link rule)
    MainShell:
    - `test/core/widgets/main_shell_test.dart` still passes untouched — the FLUTTER_TEST guard means the shell's banner resolves to null without a network call or a pending timer
  </behavior>
  <action>
Create `lib/core/widgets/update_banner.dart` with `UpdateBanner`, a
`ConsumerStatefulWidget` holding one `bool _dismissed` field.

Build: `final update = ref.watch(updateCheckProvider).valueOrNull;` — the
AsyncValue's loading and error cases both collapse to null, which is the point.
Return `const SizedBox.shrink()` when `update == null || _dismissed`. Otherwise
render a `Padding` (`Spacing.md` horizontal, `Spacing.sm` vertical) around a
`Container` decorated with `theme.colorScheme.secondaryContainer` and
`BorderRadius.circular(Radii.inner)` — the same recipe as `_ErrorBanner` in
`host_screen.dart`, in the calm secondary pair rather than the error pair,
because a new build is information and not a fault. Inside, a `Row` of:
`Icon(Icons.system_update_outlined)` tinted `onSecondaryContainer`, a
`Spacing.sm` gap, an `Expanded` `Text` reading "Roomtone {version} is available"
in `bodyMedium`/`onSecondaryContainer`, a `TextButton` labelled "Download", and
an `IconButton` with `Icons.close` and tooltip "Dismiss".

Resolve the link once per build with `tryParseLaunchableLink(update.downloadUrl)`;
when it returns null, omit the `TextButton` entirely. The button's handler is
fire-and-forget `openExternalLink(uri)` — that helper already logs, refuses
non-http(s) schemes and never throws, so there is nothing to await or catch at
the call site (the About screen's mailto handler is the precedent).

Dismiss handler: `setState(() =&gt; _dismissed = true)` first so the strip
disappears instantly, then fire-and-forget
`rememberDismissedUpdate(ref.read(storageProvider), update.version)`. Keep
watching the provider after dismissal (the `ref.watch` runs before the early
return) so the pinned result is not re-fetched.

Wire it into `lib/core/widgets/main_shell.dart` as a new child of the existing
body `Column`, between `Expanded(child: widget.navigationShell)` and
`ActiveSessionBar` — i.e. a bottom strip. Chosen over a top placement because
each branch screen owns its own `Scaffold`/`AppBar`: a top strip would float
above those app bars and under the status bar in the bottom-nav layout, while
the bottom of the column is already the shell's established home for
cross-tab furniture and needs no `SafeArea` handling in either the
NavigationBar or the NavigationRail branch. Unlike `ActiveSessionBar` it is
shown on all four tabs, so it takes no `selectedIndex`. Add a short comment
recording that placement rationale.

Tests in `test/core/widgets/update_banner_test.dart`: pump the widget inside a
`ProviderScope` with `updateCheckProvider.overrideWith((ref) async =&gt; ...)` and
`storageProvider.overrideWithValue(StorageService.inMemory())`, swap
`externalLinkOpener` for a recording fake in `setUp` and restore
`defaultExternalLinkOpener` in `tearDown` (the seam documents this contract),
and call `installAppLoggerTestIsolation()`. Cover every behavior bullet,
including reading the dismissed key back out of the in-memory storage after the
dismiss tap. Run the existing shell test alongside to prove the wiring did not
disturb it.

README: add one bullet to the `## Persistence &amp; UX` list, in the voice of the
neighbouring bullets, saying the app checks GitHub for a newer release on
launch and shows a dismissible download prompt when one exists.
  </action>
  <verify>
    <automated>cd /home/user/rtsp-mixer &amp;&amp; flutter test test/core/widgets/update_banner_test.dart test/core/widgets/main_shell_test.dart &amp;&amp; flutter analyze --fatal-infos</automated>
  </verify>
  <done>Banner tests and the untouched `main_shell_test.dart` both pass, `flutter analyze --fatal-infos` is clean across the repo, and the README bullet is present.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| app → api.github.com | Outbound request to a public third-party service over the internet (all other network traffic in this app is LAN-only) |
| GitHub JSON → app | Untrusted response body: tag, release URL and asset URLs are attacker-shaped strings as far as the app is concerned |
| app → OS browser | A URL taken from that response is handed to the platform launcher |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-CNQ-01 | Spoofing | `UpdateChecker` Dio instance | high | mitigate | Default TLS verification kept; explicitly do NOT copy `ProtectApiClient`'s `badCertificateCallback` self-signed bypass (called out in Task 1) |
| T-CNQ-02 | Tampering | `AppUpdate.downloadUrl` → `openExternalLink` | medium | mitigate | URL passes through `tryParseLaunchableLink`/`isLaunchableLink`, which admit only `http`/`https` with a non-empty host; anything else renders no action at all |
| T-CNQ-03 | Information disclosure | GitHub request | low | mitigate | Unauthenticated request with a fixed URL and a generic `User-Agent`; no token, no credentials, no camera/host data, no device identifiers leave the app |
| T-CNQ-04 | Denial of service | app startup / running stream | high | mitigate | One request per launch, 5s connect / 8s receive timeouts, off the startup critical path (lazy provider inside the shell), whole path try/caught to null per CLAUDE.md defensive rule |
| T-CNQ-05 | Denial of service | GitHub rate limit (60/hr/IP) | low | accept | `ref.keepAlive()` pins one check per launch; a 403 resolves to no banner, which is the same as no update |
| T-CNQ-06 | Elevation of privilege | APK install | medium | accept | The app only opens a URL in the browser; the OS side-load prompt and its user confirmation remain the gate — no in-app install path is added |
| T-CNQ-SC | Tampering | npm/pip/cargo installs | high | mitigate | N/A — no dependency is added; `pubspec.yaml` is not modified by this plan |
</threat_model>

<verification>
Automated (both tasks green):
- `flutter test test/core/services/update_checker_test.dart test/core/widgets/update_banner_test.dart test/core/widgets/main_shell_test.dart`
- `flutter analyze --fatal-infos`
- Full suite unaffected: `flutter test`

Human check (optional, on a device or `flutter run -d macos`):
- Temporarily lower `version:` in pubspec.yaml below the live GitHub release, run
  the app, confirm the strip appears on every tab, the Download action opens the
  browser at the release, and the dismiss action hides it and keeps it hidden
  across a relaunch. Restore the version afterwards.
- With WiFi off, confirm launch is visually identical to today (no strip, no
  spinner, no error) and a single `UPDATE` log line explains the skip.
</verification>

<success_criteria>
- A newer GitHub release produces a dismissible in-app strip naming the version; an equal or older one produces nothing.
- Download opens the APK asset on Android and the release page elsewhere, via the existing `openExternalLink` guard.
- Dismissal is remembered per version in secure storage and survives relaunch, while a later release re-arms the strip.
- Every failure mode — offline, 403/404/500, malformed JSON, unparseable tag, missing package info — is caught, logged under the `UPDATE` tag, and results only in the absence of the strip.
- No new dependency, no pubspec change, no settings surface, no background polling.
</success_criteria>

<output>
Create `.planning/quick/260920-cnq-add-an-in-app-update-checker-that-querie/260920-cnq-SUMMARY.md` when done
</output>
