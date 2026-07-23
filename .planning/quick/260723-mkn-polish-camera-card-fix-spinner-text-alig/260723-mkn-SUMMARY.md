---
phase: quick-260723-mkn
plan: 01
subsystem: monitoring-ui
status: complete
tags: [ui, animation, camera-card, alignment, flutter]
requires:
  - PR #19 camera card redesign (hybrid A+B status banner)
provides:
  - Optically centered status spinner/icon alignment
  - Animated camera-card state transitions (banner, status line, volume text, connecting swap)
affects:
  - lib/features/monitoring/widgets/camera_audio_card.dart
tech-stack:
  added: []
  patterns:
    - AnimatedSize (clip + topCenter) for height transitions
    - Fade-only AnimatedSwitcher for content crossfades
key-files:
  created: []
  modified:
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - test/features/monitoring/widgets/camera_audio_card_test.dart
decisions:
  - Fade-only AnimatedSwitcher (default FadeTransition) keeps child layout size stable so the layout sweep's paragraph-size checks and bounded pump() finders stay valid despite the never-settling CircularProgressIndicator
  - _StatusBanner leading box centered within a TextStyle-derived first-line height so multi-line error icon stays aligned to line one, not the block center
  - AnimatedSize wrappers use clipBehavior Clip.hardEdge + Alignment.topCenter so a mid-collapse height never paints outside the card in the 340dp Wrap grid
metrics:
  duration: 6min
  completed: 2026-07-23
  tasks: 2
  files: 2
requirements: [RELY-02]
---

# Quick Task 260723-mkn: Polish Camera Card (spinner alignment + state animations) Summary

Fixed the optical spinner/icon-to-text vertical alignment in the redesigned camera card and replaced all four abrupt state swaps with fade + resize implicit animations, so nothing pops when a camera changes state. Pure UI render change: the `CameraAudioCard` constructor signature is unchanged and no new throw paths were introduced.

## What Was Built

### Task 1 — Optical alignment (commit `28e6731`)
- `_StatusLine`: the single-line status Row now uses explicit `CrossAxisAlignment.center`, centering the 14x14 spinner/icon against its taller text line-box.
- `_StatusBanner`: kept `CrossAxisAlignment.start` (needed for the up-to-3-line error copy) but wrapped the 14x14 leading box in an outer `SizedBox` whose height is derived from the label `TextStyle` (`bodyMedium.fontSize * (height ?? 1.0)`, fallback 20.0) and centered the box within it. Single-line reconnecting is now centered; the multi-line error icon stays aligned to the first line rather than the block center. `ValueKey('status-banner')` preserved; no colour/copy/maxLines/D-10/D-11 changes.

### Task 2 — State-transition animations (commit `3089046`)
All durations ~200–250ms, consistent with the existing 300ms activity-border `AnimatedContainer`.
1. **Banner**: always-present `AnimatedSize` (clip + topCenter) wrapping a fade-only `AnimatedSwitcher` that switches between `_StatusBanner` and `SizedBox.shrink(key: ValueKey('no-banner'))`; grows/fades in and collapses/fades out.
2. **Status line**: `_StatusLine.build` now returns a fade-only `AnimatedSwitcher` whose child is keyed by `ValueKey(status)`, so Live ↔ Connecting… crossfades; the call site is wrapped in an `AnimatedSize` for the appear/disappear height change.
3. **Volume text**: the `Muted` ↔ percentage `Text` is wrapped in a fade-only `AnimatedSwitcher` keyed on the displayed string; the `width: 48` wrapper and styles are preserved so it never wraps.
4. **Connecting ↔ playing swap**: the `LinearProgressIndicator` / slider-row either-or region is wrapped in `AnimatedSize` + fade-only `AnimatedSwitcher` (keyed `connecting-indicator` / `volume-row`) so the indicator crossfades into the slider row with an animated height.

Every `AnimatedSwitcher` uses the default `FadeTransition` (opacity only) — no `ScaleTransition`/`SizeTransition` — so child layout size is unchanged mid-animation. Every `AnimatedSize` sets `clipBehavior: Clip.hardEdge` and `alignment: Alignment.topCenter`.

### Test updates
Added a regression group in `camera_audio_card_test.dart` locking in the animations: playing state has `find.byType(AnimatedSwitcher)` `findsWidgets`; reconnecting/error keep the banner `findsOneWidget` after the bounded pump; muted resolves `Muted` to exactly one `Text`. The existing `findsOneWidget`/`findsNothing` and text finders remained valid with the existing bounded `pump(50ms)` (no lingering outgoing child on a fresh single-state build).

## Verification

- `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart test/features/monitoring/widgets/camera_audio_card_layout_test.dart` → **66 tests, all passed** (was 62 before; +4 new regression assertions). Full 340/360/411/480 dp layout sweep green, including reconnecting @ 340dp single-line and volume `100%` never-wraps checks.
- `flutter analyze lib/features/monitoring/widgets/camera_audio_card.dart` → **No issues found**.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- `lib/features/monitoring/widgets/camera_audio_card.dart` — FOUND
- `test/features/monitoring/widgets/camera_audio_card_test.dart` — FOUND
- Commit `28e6731` (Task 1) — FOUND
- Commit `3089046` (Task 2) — FOUND
