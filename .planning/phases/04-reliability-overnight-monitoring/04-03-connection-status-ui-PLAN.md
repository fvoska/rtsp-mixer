---
phase: 04-reliability-overnight-monitoring
plan: 03
type: execute
wave: 2
depends_on: [04-01-reconnect-core-PLAN.md]
files_modified:
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - test/features/monitoring/widgets/camera_audio_card_test.dart
autonomous: true
requirements: [RELY-02]
tags: [ui, flutter, material3, baby-monitor, reconnect-indicator]

must_haves:
  truths:
    - "When `connectionStatus == CameraConnectionStatus.reconnecting`, the camera card renders a 14×14 CircularProgressIndicator + 'Reconnecting…' label in `colorScheme.tertiary`"
    - "When reconnecting, the card header row is wrapped in a Container with `colorScheme.tertiaryContainer.withValues(alpha: 0.3)` background + 8px rounded corners"
    - "When reconnecting, the status dot is `colorScheme.tertiary` (fourth branch alongside isLive/isError/default)"
    - "When reconnecting, the LinearProgressIndicator (lines ~321–325) is NOT rendered — reserved for `connecting` only (UI-SPEC interaction matrix)"
    - "When reconnecting, the volume slider remains visible but disabled (cs.isLive is false — existing gating works without modification)"
    - "Status text color is the only color change in reconnecting — camera name (titleMedium) stays default"
    - "No new Color or TextStyle constants introduced — all resolved via theme.colorScheme or AppTheme.status*"
    - "No attempt-count or countdown text appears anywhere on the card (D-11 enforcement)"
  artifacts:
    - path: "lib/features/monitoring/widgets/camera_audio_card.dart"
      provides: "CameraAudioCard renders reconnecting state per UI-SPEC §Component Inventory #1"
      contains: "CameraConnectionStatus.reconnecting"
    - path: "test/features/monitoring/widgets/camera_audio_card_test.dart"
      provides: "Widget test asserting reconnecting state rendering (spinner present, linear progress absent, amber tint)"
      contains: "reconnecting"
  key_links:
    - from: "lib/features/monitoring/widgets/camera_audio_card.dart"
      to: "lib/features/monitoring/models/player_state.dart"
      via: "reads CameraConnectionStatus.reconnecting + CameraAudioState.isLive / isError / isReconnecting"
      pattern: "CameraConnectionStatus\\.reconnecting"
    - from: "lib/features/monitoring/widgets/camera_audio_card.dart"
      to: "lib/core/theme/app_theme.dart"
      via: "colorScheme.tertiary (spinner), colorScheme.tertiaryContainer.withValues(alpha: 0.3) (header tint)"
      pattern: "colorScheme\\.tertiary"
---

<objective>
Render the `reconnecting` state on CameraAudioCard per UI-SPEC §Component Inventory #1 and the Interaction States Matrix. Adds: a fourth status-dot color branch, a header-row background tint wrapper, an inline 14×14 CircularProgressIndicator + 'Reconnecting…' text in the status row, and strict gating so the linear progress bar (reserved for `connecting`) does NOT render during `reconnecting`. No app-bar / global indicator work — D-12 rejects that.

Purpose: RELY-02 — "App shows per-camera connection status (connecting, live, reconnecting, error)" becomes visually distinct for the parent looking at the phone at 3am.
Output: Purely presentational diff on one widget + one widget test. Parallel-safe with Plans 04-02 and 04-05 (no shared files).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md
@.planning/phases/04-reliability-overnight-monitoring/04-RESEARCH.md
@.planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md
@.planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md
@.planning/phases/04-reliability-overnight-monitoring/04-VALIDATION.md
@.planning/phases/04-reliability-overnight-monitoring/04-01-SUMMARY.md

<interfaces>
<!-- Key types + render shape contracts. Plan 04-01 guarantees enum exists. -->

From lib/features/monitoring/models/player_state.dart (post-04-01):
```dart
enum CameraConnectionStatus { idle, connecting, playing, reconnecting, error }

class CameraAudioState {
  // ...
  final CameraConnectionStatus connectionStatus;
  bool get isLive => connectionStatus == CameraConnectionStatus.playing; // UNCHANGED
  bool get isError => connectionStatus == CameraConnectionStatus.error;
  bool get isReconnecting => connectionStatus == CameraConnectionStatus.reconnecting; // NEW in 04-01
}
```

Existing camera_audio_card.dart (will be modified):
- Line 85: `final isConnecting = cs.connectionStatus == CameraConnectionStatus.connecting;` — currently a local helper
- Lines 115–177: the header `Row` containing status dot (117–129) + camera name + status text (137–153)
- Lines 180–187: `_AudioLevelIndicator` — gated on `cs.isLive` (no change needed)
- Lines 321–325: LinearProgressIndicator — gated on `isConnecting` (no change needed; DO NOT add a reconnecting branch here)
- Line 339: volume slider onChanged gates on `cs.isLive` (no change needed)

From lib/core/theme/app_theme.dart:
- `AppTheme.statusOnline` = green (`#81C784`)
- `AppTheme.statusOffline` = red (`#E57373`)
- Theme colors come from `ColorScheme.fromSeed(seedColor: Color(0xFF5C6BC0), brightness: Brightness.dark)`
- `colorScheme.tertiary` renders as amber-ish from the indigo seed

From lib/core/theme/spacing.dart: `Spacing.xs = 4`, `Spacing.sm = 8`, `Spacing.md = 16`, `Spacing.lg = 24`.

UI-SPEC Interaction States Matrix (authoritative):

| status | Status dot | Header tint | Spinner | Status text | Linear progress |
|---|---|---|---|---|---|
| idle | onSurface @ 50% | none | none | (none) | hidden |
| connecting | onSurface @ 50% | none | none | "Connecting…" | **visible** |
| playing | statusOnline | none | none | "Live" (green) | hidden |
| reconnecting | colorScheme.tertiary | tertiaryContainer @ 0.3 | visible | "Reconnecting…" (tertiary) | **hidden** |
| error | statusOffline | none | none | errorMessage (red) | hidden |

**Copy consistency rule (UI-SPEC):** Change existing `Connecting...` (three ASCII dots at line ~137) to `Connecting…` (U+2026) so both `Connecting…` and `Reconnecting…` use the same ellipsis glyph.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Render reconnecting state on CameraAudioCard (status dot, header tint, inline spinner, status text) + copy fix</name>
  <files>
    lib/features/monitoring/widgets/camera_audio_card.dart,
    test/features/monitoring/widgets/camera_audio_card_test.dart
  </files>
  <read_first>
    - .planning/phases/04-reliability-overnight-monitoring/04-UI-SPEC.md §Color, §Copywriting Contract (card status labels), §Component Inventory #1, §Interaction States Matrix, §Out of Scope
    - .planning/phases/04-reliability-overnight-monitoring/04-PATTERNS.md §9 (camera_audio_card.dart — verbatim status-dot + status-text + header-tint patterns)
    - .planning/phases/04-reliability-overnight-monitoring/04-CONTEXT.md §decisions D-09, D-10, D-11, D-12
    - CLAUDE.md §Project > Constraints (parent must be able to read the card at 3am)
    - lib/features/monitoring/widgets/camera_audio_card.dart (ENTIRE FILE — lines 1–561; you must understand the existing header Row structure and progress indicator placement)
    - lib/features/monitoring/models/player_state.dart (post-04-01 — confirm isReconnecting getter exists)
    - lib/core/theme/app_theme.dart (AppTheme constants + how colorScheme.tertiary is derived)
    - lib/core/theme/spacing.dart (Spacing tokens)
  </read_first>
  <behavior>
    - Widget test 1: pumping CameraAudioCard with `connectionStatus: reconnecting` renders a `CircularProgressIndicator` widget inside the card subtree. Assert via `find.byType(CircularProgressIndicator)` being non-empty.
    - Widget test 2: pumping with `reconnecting` renders a Text widget with exact data `'Reconnecting…'` (U+2026). Assert `find.text('Reconnecting…')`.
    - Widget test 3: pumping with `reconnecting` does NOT render `LinearProgressIndicator`. Assert `find.byType(LinearProgressIndicator)` is empty.
    - Widget test 4: pumping with `connecting` renders exactly one `LinearProgressIndicator` and NO `CircularProgressIndicator` inside the header area.
    - Widget test 5: pumping with `connecting` renders the text `'Connecting…'` (U+2026) — verifies the copy fix.
    - Widget test 6: pumping with `reconnecting` does NOT contain any text matching `RegExp(r'attempt|retry|countdown', caseSensitive: false)` anywhere in the widget tree (D-11 enforcement — no attempt count, no countdown).
  </behavior>
  <action>
    Step A — Find the existing header `Row` in lib/features/monitoring/widgets/camera_audio_card.dart (currently around lines 115–177, inside the main build tree — look for `Row(` following the status dot `Container`).

    Step B — Update the status dot color branch (existing Container around lines 117–129). Expand the `color:` expression to add the reconnecting branch:

    BEFORE (existing shape):
    ```dart
    color: cs.isLive
        ? AppTheme.statusOnline
        : cs.isError
            ? AppTheme.statusOffline
            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
    ```

    AFTER:
    ```dart
    color: cs.isLive
        ? AppTheme.statusOnline
        : cs.isError
            ? AppTheme.statusOffline
            : cs.connectionStatus == CameraConnectionStatus.reconnecting
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
    ```

    Step C — Header tint wrapper (UI-SPEC Component #1). Locate the header `Row` (the one that follows the status dot and contains the camera name + status text, starting around line 115). Wrap ONLY this `Row` (not the outer AnimatedContainer — outer border animation must stay unchanged) in a `Container` when reconnecting. The simplest implementation is to keep the existing Row and wrap it conditionally:

    Replace the header `Row(...)` with:
    ```dart
    Container(
      padding: cs.connectionStatus == CameraConnectionStatus.reconnecting
          ? const EdgeInsets.all(Spacing.sm)
          : EdgeInsets.zero,
      decoration: cs.connectionStatus == CameraConnectionStatus.reconnecting
          ? BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        // ... existing children unchanged (status dot, camera name, status text)
      ),
    ),
    ```

    IMPORTANT: Preserve every child of the existing Row unchanged EXCEPT the status-text Row branches updated in Step D. Do not move, reorder, or remove any existing children (mute icon, video icon, etc.).

    Step D — Status text row branches (currently around lines 137–153). The current structure uses `if (cs.isLive) Text('Live', ...)` / `if (cs.isError) Text(cs.errorMessage ?? 'Stream failed', ...)` and an implicit fallback `Text('Connecting...', ...)`. Add a `reconnecting` branch BEFORE the connecting fallback AND change the existing `Connecting...` (three ASCII dots) to `Connecting…` (U+2026) per UI-SPEC Copywriting Contract:

    ```dart
    if (cs.isLive)
      Text(
        'Live',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.statusOnline),
      )
    else if (cs.isError)
      Text(
        cs.errorMessage ?? 'Stream failed',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.statusOffline),
      )
    else if (cs.connectionStatus == CameraConnectionStatus.reconnecting)
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.tertiary),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            'Reconnecting…',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.tertiary),
          ),
        ],
      )
    else if (cs.connectionStatus == CameraConnectionStatus.connecting)
      Text(
        'Connecting…',
        style: theme.textTheme.bodyMedium,
      ),
    ```

    If the existing code uses a different structure (e.g., unconditional Text for the fallback), match the UI-SPEC Interaction Matrix exactly: the four explicit branches above + `idle` renders no status text. Consult the existing file lines 137–153 to preserve the original layout choices (e.g., wrapping Expanded, alignment).

    Step E — DO NOT add a `reconnecting` branch to the LinearProgressIndicator block at lines ~321–325. UI-SPEC is explicit: "`connecting` gets the linear bar, `reconnecting` gets the inline spinner — never both." The existing `if (isConnecting) LinearProgressIndicator(...)` gate already correctly excludes `reconnecting`.

    Step F — VERIFY no changes needed to: volume slider (`cs.isLive` gate, line ~339), audio level indicator (`cs.isLive` gate, lines ~180–187), or mute/video icon buttons (they remain visible + enabled per UI-SPEC Component #1 table).

    Step G — Create test/features/monitoring/widgets/camera_audio_card_test.dart:

    ```dart
    import 'package:flutter/material.dart';
    import 'package:flutter_riverpod/flutter_riverpod.dart';
    import 'package:flutter_test/flutter_test.dart';
    import 'package:rtsp_mixer/core/theme/app_theme.dart';
    import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
    import 'package:rtsp_mixer/features/monitoring/widgets/camera_audio_card.dart';

    Future<void> _pumpCard(
      WidgetTester tester,
      CameraAudioState state,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: CameraAudioCard(
                cameraState: state,
                cameraIndex: 0,
                showVideoPreview: false,
                showDebugInfo: false,
                activityThreshold: 0.1,
                onToggleVideo: () {},
              ),
            ),
          ),
        ),
      );
      // Let riverpod + animated containers settle. Use a bounded pump instead of
      // pumpAndSettle to avoid hanging on the activity-border animation.
      await tester.pump(const Duration(milliseconds: 50));
    }

    void main() {
      const reconnecting = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        connectionStatus: CameraConnectionStatus.reconnecting,
      );
      const connecting = CameraAudioState(
        cameraId: 'cam1',
        cameraName: 'Nursery',
        connectionStatus: CameraConnectionStatus.connecting,
      );

      group('CameraAudioCard reconnecting state (RELY-02 / D-10 / D-11)', () {
        testWidgets('renders a CircularProgressIndicator spinner', (tester) async {
          await _pumpCard(tester, reconnecting);
          expect(find.byType(CircularProgressIndicator), findsWidgets);
        });

        testWidgets('renders "Reconnecting…" text (U+2026 ellipsis)', (tester) async {
          await _pumpCard(tester, reconnecting);
          expect(find.text('Reconnecting…'), findsOneWidget);
        });

        testWidgets('does NOT render LinearProgressIndicator', (tester) async {
          await _pumpCard(tester, reconnecting);
          expect(find.byType(LinearProgressIndicator), findsNothing);
        });

        testWidgets('contains NO attempt/retry/countdown copy (D-11)', (tester) async {
          await _pumpCard(tester, reconnecting);
          final forbidden = RegExp(r'attempt|retry|countdown', caseSensitive: false);
          final textWidgets = find.byType(Text).evaluate();
          for (final elem in textWidgets) {
            final widget = elem.widget as Text;
            final data = widget.data ?? '';
            expect(
              forbidden.hasMatch(data),
              isFalse,
              reason: 'D-11 forbids attempt/retry/countdown on card — found: "$data"',
            );
          }
        });
      });

      group('CameraAudioCard connecting state (regression guard)', () {
        testWidgets('renders LinearProgressIndicator', (tester) async {
          await _pumpCard(tester, connecting);
          expect(find.byType(LinearProgressIndicator), findsWidgets);
        });

        testWidgets('renders "Connecting…" text (U+2026, not three ASCII dots)', (tester) async {
          await _pumpCard(tester, connecting);
          expect(find.text('Connecting…'), findsOneWidget);
          expect(find.text('Connecting...'), findsNothing);
        });
      });
    }
    ```

    Step H — Verify:
      Run `flutter analyze --no-preamble lib test` — zero issues.
      Run `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart` — all tests green.
      Run `flutter test` — full suite green.
  </action>
  <verify>
    <automated>flutter analyze --no-preamble lib test &amp;&amp; flutter test --reporter expanded test/features/monitoring/widgets/camera_audio_card_test.dart</automated>
  </verify>
  <acceptance_criteria>
    - `grep "CameraConnectionStatus.reconnecting" lib/features/monitoring/widgets/camera_audio_card.dart` shows ≥ 3 hits (status dot branch, header tint conditional, status text branch)
    - `grep "Reconnecting\\…\\|Reconnecting…" lib/features/monitoring/widgets/camera_audio_card.dart` exits 0 (the literal text)
    - `grep "Connecting…" lib/features/monitoring/widgets/camera_audio_card.dart` exits 0
    - `grep "Connecting\\.\\.\\." lib/features/monitoring/widgets/camera_audio_card.dart` exits 1 (no three-ASCII-dot form remaining in card)
    - `grep "colorScheme.tertiary" lib/features/monitoring/widgets/camera_audio_card.dart` exits 0 (at least 2 hits: spinner valueColor + status text copyWith)
    - `grep "tertiaryContainer.withValues(alpha: 0.3)" lib/features/monitoring/widgets/camera_audio_card.dart` exits 0
    - `grep "Colors.amber\\|Colors.orange\\|Color(0x" lib/features/monitoring/widgets/camera_audio_card.dart` exits 1 (no new top-level color constants introduced in the edited file beyond existing ones)
    - `grep "SizedBox(\\s*width: 14,\\s*height: 14" lib/features/monitoring/widgets/camera_audio_card.dart` exits 0 (14×14 spinner sizebox per UI-SPEC)
    - `test -f test/features/monitoring/widgets/camera_audio_card_test.dart` exits 0
    - `flutter analyze --no-preamble lib test` exits 0
    - `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart` reports 6 tests passed
    - `flutter test` full suite passes (no regressions)
  </acceptance_criteria>
  <done>
    CameraAudioCard renders the reconnecting state per UI-SPEC Component Inventory #1 and Interaction States Matrix. Copy is consistent (`Connecting…`/`Reconnecting…` both use U+2026). Widget test covers spinner presence, linear-progress absence, correct copy, and D-11 enforcement (no attempt/retry/countdown text).
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Widget tree ↔ Theme system | All colors resolved via `theme.colorScheme.*` or `AppTheme.status*`. No untrusted input crosses into render path. |
| CameraAudioCard props ↔ parent widget | `cs.errorMessage` comes from AudioPlayerNotifier which forwards error.toString() (media_kit-sanitized). |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-14 | Information Disclosure | `cs.errorMessage` rendered in error state could contain internal system paths or stack traces | accept | Message originates from `error.toString()` on media_kit's player.stream.error; media_kit already sanitizes before forwarding. Visible only on-device to the logged-in user. No change in this plan. |
| T-04-15 | Denial of Service | Constant re-build of the card header during rapid `reconnecting ↔ playing` transitions thrashes UI | mitigate | The outer `AnimatedContainer` (activity border) is NOT wrapped in the tint container — only the inner header Row. The `Container` wrap only adds padding + decoration when reconnecting; flipping between null-decoration and a BoxDecoration is cheap. UI-SPEC Component #1 animation contract: "tint is applied to an inner container; the outer border stays calm." |
| T-04-16 | Elevation of Privilege | Test file imports production code including AppTheme which itself reads from platform binding | accept | Widget test uses `ProviderScope` + `MaterialApp` — standard Flutter test harness. No privileged platform surface is touched. |
</threat_model>

<verification>
- Widget test confirms `CircularProgressIndicator` present on reconnecting
- Widget test confirms `LinearProgressIndicator` ABSENT on reconnecting
- Widget test confirms exact text `'Reconnecting…'` is rendered
- Widget test confirms the old `'Connecting...'` ASCII-dot form is NOT present (regression guard for copy fix)
- Regex scan asserts no `attempt`/`retry`/`countdown` substring exists in any Text widget on the reconnecting card (D-11)
- `flutter analyze` stays clean
- Full `flutter test` suite stays green — no regressions from Plans 04-01 or 04-02
</verification>

<success_criteria>
- RELY-02 ("per-camera connection status") UI portion complete: `reconnecting` is distinguishable at a glance from `connecting`, `playing`, `error`, and `idle`.
- UI-SPEC Interaction States Matrix conforms exactly to the code behavior (verified by widget test assertions).
- No global indicator added (D-12 enforced — no change to MonitoringScreen in this plan).
- No new color/text-style constants, no new Spacing tokens.
</success_criteria>

<output>
After completion, create `.planning/phases/04-reliability-overnight-monitoring/04-03-SUMMARY.md` documenting the three new render branches (status dot, header tint, status text + spinner), the copy normalization (Connecting...→Connecting…), and the widget-test harness pattern used (ProviderScope + MaterialApp + bounded pump).
</output>
