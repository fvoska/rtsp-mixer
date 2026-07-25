---
phase: quick-260725-azh
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pubspec.yaml
  - android/app/src/main/AndroidManifest.xml
  - lib/core/services/external_link_launcher.dart
  - lib/features/about/changelog.dart
  - lib/features/about/screens/about_screen.dart
  - test/features/about/changelog_test.dart
  - test/features/about/about_screen_links_test.dart
autonomous: true
requirements: [QUICK-260725-azh]

must_haves:
  truths:
    - "Tapping a `[text](url)` link in the in-app changelog opens that URL in the device browser instead of doing nothing."
    - "Links look tappable, not just tinted — primary color plus an underline, so a colour-blind or low-contrast reader can still tell them apart from body text."
    - "The compare URL parsed off each release header is reachable from the UI; before this change it was captured and then dropped."
    - "Inline markdown parsing (bold / link / plain runs) is a pure, unit-tested function in changelog.dart rather than an untested regex buried in a private widget helper."
    - "A launch failure — no browser, a malformed URL, a platform channel error — logs and is ignored. It can never throw out of a build or a tap callback, per the project's defensive-error-handling rule."
    - "Only http/https URLs are launched. Anything else parsed out of the changelog renders as plain text and is never handed to the platform launcher."
  artifacts:
    - "lib/core/services/external_link_launcher.dart — openExternalLink(url) with a @visibleForTesting override seam and http/https-only allowlist."
    - "lib/features/about/changelog.dart — ChangelogInline segment model + parseInlineMarkdown(raw)."
    - "lib/features/about/screens/about_screen.dart — _BulletText StatefulWidget owning/disposing TapGestureRecognizers; compare-URL link row per release."
    - "android/app/src/main/AndroidManifest.xml — <intent> query for ACTION_VIEW https so package visibility does not hide browsers on Android 30+."
    - "test/features/about/changelog_test.dart — parseInlineMarkdown cases (bold, link, mixed, unbalanced, empty)."
    - "test/features/about/about_screen_links_test.dart — widget test: tapping a changelog link calls the launcher with the right Uri."
  key_links:
    - "parseInlineMarkdown → _BulletText → TapGestureRecognizer.onTap → openExternalLink(Uri)."
    - "ChangelogRelease.compareUrl → _ReleaseTile compare-link row → openExternalLink(Uri)."
    - "openExternalLink → url_launcher launchUrl(LaunchMode.externalApplication)."
---

<objective>
Make the hyperlinks in the in-app rendered changelog actually work.

Purpose: the About screen renders release-please's CHANGELOG.md with a hand-rolled
markdown subset (no markdown package — flutter_markdown is discontinued upstream).
`_inlineSpans` recognises `[text](url)` and paints the link text in the primary
colour, but never attaches a gesture recognizer — so every link in the changelog
looks like a link and does nothing when tapped. The release compare URL is parsed
off the `##` header, stored on the model, and then never rendered at all.

Output: tappable, underlined links that open in the external browser; a
"View changes on GitHub" row per release for the compare URL; the inline markdown
parser lifted out of the widget into a tested pure function; and a launcher seam
that swallows every failure mode rather than letting a dead browser throw.
</objective>

<tasks>

### Task 1: Add url_launcher and a defensive launcher seam

files:
  - pubspec.yaml
  - android/app/src/main/AndroidManifest.xml
  - lib/core/services/external_link_launcher.dart

action:
- Add `url_launcher: ^6.3.2` to dependencies; run `flutter pub get`.
- Add an `<intent>` query for `ACTION_VIEW` + `https` scheme to the existing
  `<queries>` block in AndroidManifest.xml. Android 30+ package visibility
  otherwise hides browser activities from the app.
- New `lib/core/services/external_link_launcher.dart`:
  - `Future<bool> openExternalLink(Uri url)` — rejects any scheme other than
    http/https, calls `launchUrl(url, mode: LaunchMode.externalApplication)`,
    wraps everything in try/catch, logs via `appLog` and returns false on failure.
  - `@visibleForTesting` override hook so widget tests can capture the Uri
    without a platform channel (mirrors `AuthNotifier.backgroundValidationDelay`
    and `ProtectApiClient.setDioForTest`).

verify: `flutter analyze` clean; `flutter pub get` resolves.
done: openExternalLink exists, is http/https-only, and cannot throw.

### Task 2: Lift inline markdown parsing into changelog.dart

files:
  - lib/features/about/changelog.dart
  - test/features/about/changelog_test.dart

action:
- Add a `ChangelogInline` segment model (plain text / bold / link-with-url).
- Add `List<ChangelogInline> parseInlineMarkdown(String raw)` carrying over the
  existing `**bold**` / `[text](url)` regex, returning a single plain segment on
  any parse trouble (same degrade-to-raw-text contract as before).
- Unit tests: plain, bold only, link only, bold+link mixed, empty string,
  unbalanced markers, link with an empty URL.

verify: `flutter test test/features/about/changelog_test.dart`.
done: parser is pure, exported, and covered.

### Task 3: Render tappable links in the About screen

files:
  - lib/features/about/screens/about_screen.dart
  - test/features/about/about_screen_links_test.dart

action:
- Replace `_inlineSpans` with a `_BulletText` StatefulWidget that builds spans
  from `parseInlineMarkdown`, owns a `TapGestureRecognizer` per link span, and
  disposes them in `dispose`/`didUpdateWidget` (leaking recognizers is the usual
  bug with `TextSpan.recognizer`).
- Style links primary + underline. Only attach a recognizer when the URL parses
  to an http/https Uri; otherwise render the link text as plain text.
- Add a "View changes on GitHub" row at the bottom of each expanded release when
  `compareUrl` is present, wired to `openExternalLink`. Kept out of the
  ExpansionTile header on purpose — a tappable span inside the header would
  fight the tile's own expand/collapse tap target.
- Widget test: pump AboutScreen with a stubbed CHANGELOG, tap a link, assert the
  launcher seam received the expected Uri.

verify: `flutter analyze`; `flutter test`.
done: tapping a changelog link launches it; recognizers are disposed.

</tasks>
