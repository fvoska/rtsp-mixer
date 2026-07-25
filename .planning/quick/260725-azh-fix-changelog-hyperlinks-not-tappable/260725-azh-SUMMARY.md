---
phase: quick-260725-azh
plan: 01
status: complete
date: 2026-07-25
commits:
  - f285b3d feat(about) - add a defensive external link launcher
  - 509a254 refactor(about) - make inline changelog markdown a tested pure function
  - ea53f59 fix(about) - make changelog hyperlinks actually open
files_modified:
  - pubspec.yaml
  - pubspec.lock
  - android/app/src/main/AndroidManifest.xml
  - lib/core/services/external_link_launcher.dart
  - lib/features/about/changelog.dart
  - lib/features/about/screens/about_screen.dart
  - test/features/about/changelog_test.dart
  - test/features/about/about_screen_links_test.dart
---

# Quick Task 260725-azh: Fix changelog hyperlinks not tappable

## What was wrong

The About screen renders the bundled `CHANGELOG.md` through a hand-rolled
markdown subset (the app ships no markdown package — flutter_markdown is
discontinued upstream). The renderer recognised `[label](url)` and painted the
label in the primary colour, but never attached a gesture recognizer. Every
link in the changelog therefore *looked* like a link and did nothing when
tapped. Separately, the compare URL parsed off each `## [x.y.z](…)` release
header was stored on `ChangelogRelease.compareUrl` and then never rendered.

## What changed

**A single choke point for outbound links** —
`lib/core/services/external_link_launcher.dart`:

- `openExternalLink(uri)` launches via `url_launcher` in
  `LaunchMode.externalApplication` and swallows every failure mode (rejected
  scheme, no browser installed, platform channel error) into a logged `false`.
  This screen is reachable while audio is streaming, so per CLAUDE.md nothing
  here may throw.
- http/https only, host required. Link targets come out of a text file, so
  `tel:`, `intent:`, `javascript:` and friends never reach the platform.
- `externalLinkOpener` is a `@visibleForTesting` seam, matching the existing
  seams (`AuthNotifier.backgroundValidationDelay`,
  `ProtectApiClient.setDioForTest`).
- `AndroidManifest.xml` gained an `ACTION_VIEW` + `https` `<queries>` intent.
  Android 30+ package visibility hides browser activities without it.

**Parsing lifted out of the widget** — `parseInlineMarkdown(raw)` in
`changelog.dart` returns typed `ChangelogInline` runs (plain / bold / link with
target). Previously the regex lived in a private `_inlineSpans` helper, which
made it untestable and discarded the link target at parse time.

**Tappable rendering** — `_BulletText` replaces `_inlineSpans`. It is a
`StatefulWidget` because each link needs a `TapGestureRecognizer` and those
must be disposed; recognizers are rebuilt only when the bullet text changes, so
a theme change or parent rebuild cannot dispose one mid-gesture. Links are
underlined as well as tinted — colour alone is not an accessible affordance.
A target that is not a launchable http(s) URL gets no recognizer and renders as
plain text, so nothing looks tappable while being inert.

**Compare URL surfaced** — each expanded release gains a "View changes on
GitHub" row. Deliberately not on the `ExpansionTile` header: a tappable span up
there would compete with the tile's own expand/collapse tap target, so tapping
the version number would do something different from tapping beside it.

**Asset seam** — the changelog now loads via `DefaultAssetBundle.of(context)`
(which falls back to `rootBundle` in the app) so widget tests supply a fixed
changelog rather than asserting against the repo's real, ever-changing one.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — 356 tests pass (was 329; +27 here).
- Coverage added: both link shapes launch the right URL, the compare row
  launches the compare URL, raw markdown never leaks into the UI, and a hostile
  target stays inert. That last one asserts on the span's `recognizer` rather
  than on the tap, because `openExternalLink`'s own allowlist would refuse a
  `javascript:` target anyway and a tap-only assertion would pass even if the
  renderer wrongly made the span tappable.

## Notes / not done

- Not exercised on a device. The app needs a Unifi console or a manual RTSP
  source to reach a useful state, and this container has neither, so the
  evidence here is the widget tests rather than a screenshot.
- iOS has no `LSApplicationQueriesSchemes` entry added — http/https do not need
  one, and the project targets Android plus desktop.
- The contact email on the same screen is still a `SelectableText`, not a
  `mailto:` link. Left alone as out of scope for a changelog fix; it is now a
  one-liner if wanted, since the launcher exists.
