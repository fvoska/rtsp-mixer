---
phase: quick-260724-h2l
plan: 01
subsystem: about
tags: [changelog, ui, parser, about-screen]
status: complete
requires: []
provides:
  - "parseChangelog() — dependency-free release-please changelog parser + release model"
  - "Collapsible per-release changelog rendering on the About screen"
affects:
  - lib/features/about/screens/about_screen.dart
tech-stack:
  added: []
  patterns:
    - "Hand-rolled markdown-subset parser (no renderer dependency)"
    - "ExpansionTile-in-card accordion matching the Help screen pattern"
    - "Text.rich inline spans for bold scope prefixes and link text"
key-files:
  created:
    - lib/features/about/changelog.dart
    - test/features/about/changelog_test.dart
  modified:
    - lib/features/about/screens/about_screen.dart
decisions:
  - "Render releases as ExpansionTiles inside the existing Changelog _Section card (no nested inner cards) to keep Help-like visual weight without doubling card chrome."
  - "Link spans are styled (primary color) only — no tap/launch handler, per plan scope."
metrics:
  duration: 4min
  completed: 2026-07-24
---

# Quick Task 260724-h2l: In-App Changelog as Collapsible Markdown Summary

Rendered the About screen changelog as structured, collapsed-by-default per-release accordion sections parsed from the release-please CHANGELOG subset by hand (no markdown package), with bold scope prefixes and primary-colored link text; degrades to the existing plain monospace text if parsing yields nothing, and trimmed the "Made by" card body to show just the name.

## What Was Built

- **`lib/features/about/changelog.dart`** — a dependency-free `parseChangelog(String)` plus immutable `ChangelogRelease` (version, optional compareUrl, optional date, sections) and `ChangelogSection` (heading, raw entry strings) model. Parses the release-please shape (`## [x.y.z](url) (date)`, `### Heading`, `*`/`-` bullets), ignores the top-level `# Changelog` H1, preserves source order (newest first), and is defensively tolerant: malformed lines are skipped, and empty/non-matching input or any unexpected failure returns an empty list.
- **`lib/features/about/screens/about_screen.dart`** — the changelog `FutureBuilder` now calls `parseChangelog`; a non-empty result renders one collapsible `ExpansionTile` per release (collapsed by default, `Border()`/`collapsedShape` matching the Help `_HelpSection` pattern) with grouped section bullets rendered via `Text.rich`, bolding `**scope:**` prefixes and coloring `[text](url)` link text in the primary color. An empty parse result falls back to the original plain monospace `SelectableText`. The "Made by" card body text changed from `Made by Filip Voska` to `Filip Voska` (email untouched); loading/null/empty states unchanged.
- **`test/features/about/changelog_test.dart`** — 7 unit tests covering the real changelog shape (multiple releases/section types, order, URL, date), H1 ignoring, empty input, non-release text, empty-body release, bare `## [x.y.z]` header without URL/date, and `-` bullets.

## Tasks Completed

| Task | Name | Type | Commit |
| ---- | ---- | ---- | ------ |
| 1 | Parse release-please changelog subset into a release model (TDD) | tracer | `2975a87` (test/RED), `999f935` (feat/GREEN) |
| 2 | Render collapsible releases in AboutScreen and trim "Made by" body | auto | `dfbd0cf` |

## Verification

- `flutter test test/features/about/changelog_test.dart` — 7/7 passing (parser + fallback behavior).
- `flutter test test/features/about/` — all passing.
- `flutter analyze lib/features/about/screens/about_screen.dart lib/features/about/changelog.dart` — No issues found.
- No new package added to pubspec.yaml (grep for `flutter_markdown` / `markdown:` confirms none).

## Deviations from Plan

None — plan executed exactly as written.

## TDD Gate Compliance

Task 1 followed RED → GREEN: a `test(...)` commit (`2975a87`) with failing tests preceded the `feat(...)` implementation commit (`999f935`). No refactor commit was needed.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: lib/features/about/changelog.dart
- FOUND: lib/features/about/screens/about_screen.dart
- FOUND: test/features/about/changelog_test.dart
- FOUND commit: 2975a87 (test/RED)
- FOUND commit: 999f935 (feat/GREEN)
- FOUND commit: dfbd0cf (feat/render)
