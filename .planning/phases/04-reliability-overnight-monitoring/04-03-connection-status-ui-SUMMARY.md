---
phase: 04-reliability-overnight-monitoring
plan: 03
subsystem: monitoring-ui
tags: [ui, flutter, material3, baby-monitor, reconnect-indicator, camera-audio-card, widget-test]

# Dependency graph
requires:
  - plan: 04-01-reconnect-core
    provides: CameraConnectionStatus.reconnecting enum variant + isReconnecting getter (Wave 1)
provides:
  - CameraAudioCard render support for CameraConnectionStatus.reconnecting (RELY-02 UI portion)
  - Status-dot tertiary-color branch, header tertiaryContainer tint wrapper, inline 14×14 CircularProgressIndicator + 'Reconnecting…' status text
  - Copy normalization: 'Connecting...' → 'Connecting…' (U+2026 ellipsis, aligned with 'Reconnecting…')
  - Widget-test harness pattern (ProviderScope + MaterialApp + bounded 50ms pump) — reusable by future card-level widget tests
affects:
  - 04-05-health-summary (unaffected — shares no files; may render camera names via the same player_state enum)
  - 04-02-zombie-detection (unaffected — triggers reconnecting state via ReconnectSupervisor; this plan only renders it)
  - 04-04-push-alert (unaffected — separate surface; notification UI)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Widget test harness: ProviderScope > MaterialApp > Scaffold > widget under test, plus bounded `tester.pump(Duration(milliseconds: 50))` (not pumpAndSettle — avoids hanging on the card's 300ms activity-border AnimatedContainer).
    - If/else-if status-text branch chain enforcing exactly-one-renders per state (replaces previous independent `if` blocks which allowed two branches to co-render during the reconnecting transition window).
    - Conditional container decoration (`decoration: cond ? BoxDecoration(...) : null`) for per-state tint wrappers that preserve outer-widget animation contracts.

key-files:
  created:
    - test/features/monitoring/widgets/camera_audio_card_test.dart
  modified:
    - lib/features/monitoring/widgets/camera_audio_card.dart

key-decisions:
  - "Header-tint wrapper lives INSIDE the outer AnimatedContainer, not around it (T-04-15 mitigation). Wrapping the outer animated container would cause the 300ms border animation to replay on every reconnecting ↔ playing transition, which is exactly the 3am flash-thrash the plan rejects."
  - "Status-text branches converted from independent `if (…)` blocks to a single `if / else if / … / else if` chain. Original code had `if (isConnecting) Text('Connecting…')` + `if (cs.isLive) Text('Live')` + `if (cs.isError) Text(...)` as three independent branches — mutually exclusive today only because connection status is an enum, but brittle. The chain makes the exclusivity structural and adds the reconnecting branch without introducing ambiguity."
  - "Multiline `colorScheme.tertiaryContainer.withValues(alpha: 0.3)` — dart format wraps this across two lines. Line-oriented grep from the plan's acceptance list does not match, but `perl -0777` confirms the semantic invariant is present. Same pattern noted in 04-01 SUMMARY for `.timeout(const Duration(seconds: 15))`. No change to code style — readability > greppability."

patterns-established:
  - "Widget-level test harness for this app: `Future<void> _pumpCard(tester, state)` that builds ProviderScope + MaterialApp + home: Scaffold(body: widget), then does a single bounded pump. Future card widget tests (e.g., 04-05 summary screen) should copy this shape."
  - "Whenever a widget reads `theme.colorScheme.tertiary*`, the tint scope MUST be an inner container — never the outermost widget — to preserve existing animation contracts on the outer widget."

requirements-completed: [RELY-02]

# Metrics
duration: 3min
completed: 2026-04-24
---

# Phase 4 Plan 03: Connection Status UI Summary

**Render `CameraConnectionStatus.reconnecting` on CameraAudioCard with a tertiary-tinted header, a 14×14 inline spinner, and 'Reconnecting…' text — keeping the linear progress bar reserved for the initial `connecting` state and enforcing no attempt/countdown copy (D-10, D-11, D-12).**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-24T11:00:08Z
- **Completed:** 2026-04-24T11:02:34Z
- **Tasks:** 1/1
- **Files modified:** 2 (1 new widget test, 1 modified widget)

## Accomplishments

- `CameraAudioCard` now distinguishes `reconnecting` from `connecting`, `playing`, `error`, and `idle` at a glance — parent looking at the phone at 3am can read the amber tint + spinner + "Reconnecting…" label without thinking.
- The four rules from the UI-SPEC Interaction States Matrix are enforced in code **and** asserted by widget tests:
  1. Only one of {`LinearProgressIndicator`, `CircularProgressIndicator`} renders per state.
  2. Header tint appears ONLY in reconnecting.
  3. No attempt/retry/countdown copy anywhere on the card (D-11).
  4. Copy uses U+2026 ellipsis consistently (`Connecting…` / `Reconnecting…`).
- Widget-test harness established — first widget-level test in the repo. Future card/screen widget tests can copy the `_pumpCard` pattern.

## Task Commits

Committed atomically with `--no-verify` per parallel worktree protocol:

1. **Task 1 RED — Failing widget test for reconnecting state** — `0ec4485` (test)
2. **Task 1 GREEN — CameraAudioCard renders reconnecting state** — `264993c` (feat)

_TDD gates: a `test(…)` commit precedes the `feat(…)` commit. Initial run of the RED test confirmed 3 expected failures (missing spinner, missing `Reconnecting…` text, missing `Connecting…` normalization). After the feat commit all 6 widget tests pass on first run._

## Files Created

- `test/features/monitoring/widgets/camera_audio_card_test.dart` — 6 widget tests. Two groups:
  - **"CameraAudioCard reconnecting state (RELY-02 / D-10 / D-11)"** — 4 tests asserting `CircularProgressIndicator` presence, `'Reconnecting…'` text, `LinearProgressIndicator` absence, and no attempt/retry/countdown copy anywhere.
  - **"CameraAudioCard connecting state (regression guard)"** — 2 tests asserting `LinearProgressIndicator` still renders and the `Connecting…` text uses U+2026 (not three ASCII dots).

## Files Modified

- `lib/features/monitoring/widgets/camera_audio_card.dart` — 3 changes inside the header `Row` (all within the existing build tree; no changes outside the single Column of the card body):
  1. Wrapped the header `Row` in a conditional-decoration `Container`. Padding + tertiaryContainer @ 30% alpha + 8px rounded only when `connectionStatus == reconnecting`; otherwise `EdgeInsets.zero` + `null` decoration (zero cost).
  2. Added a fourth branch to the status-dot color expression: `reconnecting → colorScheme.tertiary`.
  3. Replaced the three independent status-text `if` blocks with a single `if / else if / else if / else if` chain that adds the reconnecting branch (inline 14×14 `CircularProgressIndicator` + `Spacing.xs` gap + `'Reconnecting…'` text) and normalizes `'Connecting...'` to `'Connecting…'`.

## API Surface

No public API changes — this is purely a presentational diff on `CameraAudioCard`'s `build()` method. Existing props, callbacks, and state shape unchanged. No new constants, no new widgets extracted.

## Verification

Acceptance criteria (plan's <acceptance_criteria> block) — all spot-checks pass:

| Criterion | Result |
|-----------|--------|
| `grep -c "CameraConnectionStatus.reconnecting"` ≥ 3 | **4** (status-dot branch, header tint padding, header tint decoration, status text branch) |
| `grep "Reconnecting…"` present | Line 187 |
| `grep "Connecting…"` present | Line 194 |
| `grep "Connecting..."` absent | Confirmed — no three-ASCII-dot form remains |
| `grep -c "colorScheme.tertiary"` ≥ 2 | **4** (status dot, spinner valueColor, header decoration, text copyWith) |
| `tertiaryContainer.withValues(alpha: 0.3)` present | Present (split across lines 124-125 by dart format; `perl -0777` confirms) |
| `Colors.amber / Colors.orange / Color(0x...)` not newly introduced | Only pre-existing `Colors.amber` inside `_AudioLevelIndicator` (Phase 2 code) remains; no new top-level color constants |
| 14×14 SizedBox spinner | Present at lines 176-178 |
| Widget test file exists | Present |
| `flutter analyze --no-preamble lib test` | **0 new issues** (5 pre-existing warnings in `auth_provider_test.dart` and `camera_provider_test.dart` — lineage traced in 04-01 SUMMARY, predate Phase 4) |
| `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart` | **6/6 pass** |
| `flutter test` full suite | **93/93 pass** (no regressions) |

## Deviations from Plan

None — plan executed exactly as written. The single item worth flagging is not a deviation but a style note:

- **Dart format wraps `theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3)` across two lines.** A line-oriented `grep "tertiaryContainer.withValues(alpha: 0.3)"` returns nothing; a multiline `perl -0777` confirms the expression is present. Identical situation to the 04-01 `.timeout(const Duration(seconds: 15))` split-across-lines issue — kept the formatted source, acceptance criterion is satisfied in spirit.

## Deferred Issues

None.

## Known Stubs

None. The rendered state reflects real data from `CameraAudioState.connectionStatus` — no placeholder text, no mocked data. The reconnecting state is driven by the live `ReconnectSupervisor` wired in Plan 04-01.

## Threat Flags

None. No new surface: no network endpoints, no auth changes, no file access, no schema changes. `cs.errorMessage` continues to surface only in the `error` state (unchanged), and `HealthEvent.detail` truncation happens at the recording site (Plan 04-01), not at the render site. T-04-14 through T-04-16 from the plan's threat model are all accepted or mitigated as declared.

## Next-plan Integration Cheat-sheet

- **Plan 04-05 (health summary screen):** the `_pumpCard` widget-test pattern can be copied to test the summary screen. Same `ProviderScope + MaterialApp + bounded pump` harness works; substitute `HealthSummaryScreen` for `CameraAudioCard`.
- **Plan 04-04 (push alert):** no interaction with this plan — alerts fire from the supervisor, not from the card render path. Card continues showing `reconnecting` indefinitely per D-02 (retry forever); the 5-minute alert is a separate notification channel.
- **Future iteration (if a global indicator ever becomes needed despite D-12):** the status dot branch + amber color tokens are all centralized in this file; a future `MonitoringScreen` app-bar indicator can reuse the same `colorScheme.tertiary` role without redefining colors.

## Self-Check

- `test -f lib/features/monitoring/widgets/camera_audio_card.dart` → FOUND
- `test -f test/features/monitoring/widgets/camera_audio_card_test.dart` → FOUND
- `git log --oneline | grep 0ec4485` → FOUND (RED test commit)
- `git log --oneline | grep 264993c` → FOUND (GREEN feat commit)
- `flutter analyze --no-preamble lib test` → 5 pre-existing warnings; 0 new from this plan
- `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart` → 6/6 pass
- `flutter test` → 93/93 pass (no regressions from Plans 04-01 or any prior phase)

## Self-Check: PASSED
