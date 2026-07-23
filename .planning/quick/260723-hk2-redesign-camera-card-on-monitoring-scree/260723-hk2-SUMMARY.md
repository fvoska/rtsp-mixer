---
phase: quick-260723-hk2
plan: 01
subsystem: monitoring-ui
status: complete
tags: [ui, flutter, monitoring, camera-card, reliability]
requirements:
  - QUICK-260723-hk2
dependency-graph:
  requires:
    - Phase 04 UI-SPEC (D-09/D-10/D-11) camera-card state contract
  provides:
    - CameraAudioCard banner+header+status-line layout
  affects:
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - monitoring_screen.dart (consumer — public API unchanged)
tech-stack:
  added: []
  patterns:
    - "Structural zones: edge-to-edge status banner (problem states) vs. full-width status line (healthy states)"
    - "Shared _StatusBanner widget/slot for reconnecting + error keeps problem cards structurally consistent"
key-files:
  created: []
  modified:
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - test/features/monitoring/widgets/camera_audio_card_layout_test.dart
    - test/features/monitoring/widgets/camera_audio_card_test.dart
decisions:
  - "Amber accent (colorScheme.tertiary) moved from a header-wrapping tint box to a dedicated edge-to-edge banner slot; accent stays reserved for reconnecting only (D-10 preserved, placement-only UI-SPEC update)."
  - "Error uses the same banner slot in error-red, making both problem states structurally identical."
  - "Connecting status text uses colorScheme.primary to match its spinner; amber remains reserved for reconnecting."
metrics:
  duration: 5min
  completed: 2026-07-23
  tasks: 2
  files: 3
---

# Phase quick-260723-hk2 Plan 01: Redesign Camera Card on Monitoring Screen Summary

Restructured `CameraAudioCard` into distinct zones — an edge-to-edge tinted status banner for problem states (reconnecting/error), an identity-only header row, and a full-width status line for healthy states — eliminating the "Re…" truncation and the structural inconsistency between live and reconnecting cards, with no player/reconnect/provider logic changes.

## What Was Built

- **Task 1 (tracer):** Reworked only the `build()` widget tree of `_CameraAudioCardState`:
  - `Card.filled` gained `clipBehavior: Clip.antiAlias` and its child is now a `Column` whose first child is the conditional banner and second is the existing `Padding(Spacing.md)` content.
  - New `_StatusBanner` (stateless, `key: ValueKey('status-banner')`): edge-to-edge tinted strip rendered only for reconnecting (amber `tertiaryContainer@0.3` + 14×14 spinner + "Reconnecting…", `maxLines: 1`, strictly status-only per D-11) and error (`statusOffline@0.12` + `error_outline` icon + `errorMessage ?? 'Stream failed'`, `maxLines: 3`).
  - Header row now holds identity only (8×8 status dot with the unchanged 4-branch color logic, `Expanded` name+badge, trailing `Row(mainAxisSize: min)` of the three unchanged compact IconButtons). The old reconnecting header-tint `Container` was removed, and the `flex: 2` dropped so the name gets maximal room.
  - New `_StatusLine` (stateless): full-width line below the header for healthy states only — playing → `graphic_eq` icon + "Live"; connecting → 14×14 primary spinner + "Connecting…"; all other states → `SizedBox.shrink()`.
  - Volume row shows "Muted" (in `statusOffline`) instead of `${volume}%` when muted.
  - Preserved unchanged: `LinearProgressIndicator` during connecting, volume slider when not connecting, audio-level indicator, quality dropdown, debug panel, video preview, all zoom/pan/remove helpers, and the public constructor signature.
- **Task 2:** Updated both widget test files for the new layout — `_mayWrap` now also allows the multi-line error banner copy; added a 340dp assertion that "Reconnecting…" renders un-truncated on one line; added banner-slot presence/absence assertions across states; added muted-clarity tests.

## Verification

- `flutter analyze lib/features/monitoring/widgets/camera_audio_card.dart` — **No issues found**.
- `flutter test test/features/monitoring/widgets/` — **68 tests passed** (includes the two target files: layout sweep across [340,360,411,480]dp × all scenarios, plus reconnecting/connecting/error/banner-slot/muted-clarity groups).
- Tracer feedback gate (autonomous run): tracer `<verify>` (analyze) re-run clean before expanding to Task 2.

## Deviations from Plan

None — plan executed as written.

## UI-SPEC Deviation (deliberate, user-approved)

Per the plan objective, the amber accent moved from the Phase 04 UI-SPEC's header-wrapping *tint box* (§Reserved-accent item 1) to a dedicated edge-to-edge **status banner** at the top of the card. This is a **placement-only** change:
- **D-10 preserved:** `colorScheme.tertiary` / `tertiaryContainer` remains reserved exclusively for the reconnecting state; reconnecting still stands out in amber (banner tint + spinner + text).
- **D-11 preserved:** the reconnecting card is status-only — NO attempt count, NO countdown, NO error message (asserted by the forbidden-copy regex test).
- Error reuses the same banner slot in error-red, which is what makes both problem cards structurally consistent.

## Threat Surface

No new trust boundary introduced (T-hk2-01, low, mitigated). The card remains a pure render over immutable `CameraAudioState`; no new nullable dereferences or index math were added, honoring the CLAUDE.md defensive rule so a render exception cannot bubble up and kill the audio stream.

## Self-Check: PASSED

- FOUND: lib/features/monitoring/widgets/camera_audio_card.dart
- FOUND: test/features/monitoring/widgets/camera_audio_card_layout_test.dart
- FOUND: test/features/monitoring/widgets/camera_audio_card_test.dart
- FOUND commit: 91b3f33 (Task 1)
- FOUND commit: 33d2d23 (Task 2)
