---
phase: quick-260723-mkn
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - test/features/monitoring/widgets/camera_audio_card_test.dart
  - test/features/monitoring/widgets/camera_audio_card_layout_test.dart
autonomous: true
requirements: [RELY-02]
must_haves:
  truths:
    - "Reconnecting spinner and 'Reconnecting…' label are optically vertically centered on the single-line banner."
    - "The multi-line error banner keeps its icon aligned to the first text line, not the block center."
    - "The Live / Connecting… status-line spinner/icon is optically vertically centered with its label."
    - "The status banner fades and resizes in/out instead of popping instantly."
    - "The status line crossfades when its content changes (Live ↔ Connecting…) and animates height when appearing/disappearing."
    - "The volume-row text crossfades between 'Muted' and a percentage instead of swapping instantly."
    - "The connecting LinearProgressIndicator ↔ volume slider swap animates height with no abrupt jump."
    - "No layout overflow at 340dp during or after transitions; the layout sweep test stays green."
    - "Constructor signature is unchanged and no new throw paths are introduced (pure render)."
  artifacts:
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - test/features/monitoring/widgets/camera_audio_card_test.dart
    - test/features/monitoring/widgets/camera_audio_card_layout_test.dart
  key_links:
    - "AnimatedSize wrappers use clipBehavior + top alignment so a mid-collapse height change never paints outside the card in the Wrap grid at 340dp."
    - "AnimatedSwitcher uses FadeTransition (opacity only) so RenderParagraph layout size is unchanged mid-animation — the bounded pump(50ms) finders and _wrapped() layout checks stay valid despite the never-settling CircularProgressIndicator."
---

<objective>
Polish the redesigned camera card (merged in PR #19): fix the spinner/icon-to-text vertical alignment in `_StatusBanner` and `_StatusLine`, and animate all abrupt state swaps so nothing pops.

Purpose: The parent tested the merged redesign on a real device and reported (1) the loading spinner sits optically high against its adjacent status label, and (2) state changes are jarring — the banner, status line, volume text, and connecting indicator all appear/disappear/swap instantly with the card height jumping.

Output: A UI-only change to `camera_audio_card.dart` plus test updates. No player/reconnect/provider logic changes; the `CameraAudioCard` constructor signature is unchanged.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@lib/features/monitoring/widgets/camera_audio_card.dart
@test/features/monitoring/widgets/camera_audio_card_test.dart
@test/features/monitoring/widgets/camera_audio_card_layout_test.dart

Constraints carried from the quick-task brief:
- UI-only render change. No changes to player, reconnect, or provider logic. Constructor signature unchanged. No new throw paths (per CLAUDE.md: no exception may kill the audio stream).
- Preserve UI-SPEC contracts: the amber/tertiary accent stays reserved for reconnecting (D-10); the reconnecting banner stays status-only with no attempt count, countdown, or error copy (D-11). Existing tests guard both — do not weaken them.
- Tests must use bounded `pump(...)` (never `pumpAndSettle`) because the `CircularProgressIndicator` in the banner and status line animates forever and would hang a settle.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Optically center spinner/icon with text in _StatusBanner and _StatusLine</name>
  <files>lib/features/monitoring/widgets/camera_audio_card.dart</files>
  <action>
Fix the vertical alignment of the 14x14 leading widget (CircularProgressIndicator / Icon) against its adjacent label in both status rows. The rows currently use CrossAxisAlignment.start with a 14x14 leading box, so on a single-line label the leading sits at the top of the taller text line-box instead of its optical center.

For `_StatusLine` (the healthy Live / Connecting… row, currently at the Row around lines 591-604): its label is always single-line, so change that inner Row's crossAxisAlignment from start to CrossAxisAlignment.center. This centers the 14x14 leading box against the single-line label.

For `_StatusBanner` (the reconnecting/error row around lines 521-534): this row serves BOTH a single-line reconnecting label AND an up-to-3-line error label, so a blanket center would push the icon to the block center of a wrapped error message. Instead, keep CrossAxisAlignment.start and make the leading widget optically center on the FIRST text line: wrap the existing `SizedBox(width: 14, height: 14, child: Center(child: leading))` in an outer SizedBox whose height equals the label's single-line height, and center the 14x14 box within it. Compute the line height from the label's TextStyle (theme.textTheme.bodyMedium) as fontSize * (height ?? 1.0), with a sensible fallback (~20) if either is null — do NOT hardcode a bare magic number without the TextStyle-derived value. Result: single-line reconnecting is centered, and the multi-line error keeps its icon aligned to the first line rather than the block center.

Keep the ValueKey('status-banner') on the `_StatusBanner` root Container. Do not change colors, copy, maxLines, or the D-10/D-11 behavior.
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/widgets/camera_audio_card_test.dart test/features/monitoring/widgets/camera_audio_card_layout_test.dart</automated>
  </verify>
  <done>Both existing test files pass. In `_StatusLine` the status Row uses CrossAxisAlignment.center; in `_StatusBanner` the leading box is centered within a TextStyle-derived first-line height with CrossAxisAlignment.start preserved for the multi-line error case.</done>
</task>

<task type="auto">
  <name>Task 2: Animate card state transitions and lock behavior with tests</name>
  <files>lib/features/monitoring/widgets/camera_audio_card.dart, test/features/monitoring/widgets/camera_audio_card_test.dart, test/features/monitoring/widgets/camera_audio_card_layout_test.dart</files>
  <action>
Replace the four instant state swaps with standard Flutter implicit animations (durations ~200-300ms, sensible curves), consistent with the existing 300ms AnimatedContainer activity border. Use AnimatedSize for height changes and AnimatedSwitcher for content changes. CRITICAL: every AnimatedSwitcher must use a fade-only transition (the default FadeTransition, opacity only) — do NOT use ScaleTransition or SizeTransition inside a switcher, because those alter child layout mid-animation and would invalidate the layout sweep's _wrapped() paragraph-size check. Every AnimatedSize must set clipBehavior: Clip.hardEdge and alignment topCenter so a mid-collapse height never paints outside the card in the Wrap grid at 340dp.

1. Banner appear/disappear (outer Column child, currently the `if (reconnecting || isError) _StatusBanner(...)` around lines 156-161): replace the conditional with an always-present AnimatedSize wrapping an AnimatedSwitcher whose child is the `_StatusBanner` (keyed ValueKey('status-banner')) when in a problem state, else a `const SizedBox.shrink(key: ValueKey('no-banner'))`. The banner is width double.infinity, so keep the AnimatedSize full-width. This animates size + fade so the banner grows/fades in and collapses/fades out.

2. Status line (the `_StatusLine(status: cs.connectionStatus)` call around line 265): animate its appearance and content change. Inside `_StatusLine.build`, wrap the returned subtree in an AnimatedSwitcher (fade) whose child carries a ValueKey(status) — the Row for playing/connecting and a keyed SizedBox.shrink for idle/reconnecting/error — so Live ↔ Connecting… crossfades. Wrap the `_StatusLine(...)` call site in an AnimatedSize (top-aligned, clipped) so the height change when the line appears/disappears animates rather than jumps.

3. Volume-row text (the `SizedBox(width: 48, child: Text(cs.isMuted ? 'Muted' : '${cs.volume.round()}%', ...))` around lines 438-453): wrap the Text in an AnimatedSwitcher (fade) and give the Text a ValueKey built from the displayed string so the Muted ↔ percentage swap crossfades. Keep the width:48 wrapper and the existing styles so it still never wraps.

4. Connecting ↔ playing swap (the `if (isConnecting) LinearProgressIndicator` around lines 411-415 and the `if (!isConnecting) ...[ volume slider row ]` around lines 418-457): wrap this either/or region in an AnimatedSize (top-aligned, clipped) plus an AnimatedSwitcher (fade) that switches between the connecting indicator subtree (keyed) and the slider-row subtree (keyed by !isConnecting) so the LinearProgressIndicator crossfades into the slider row and the height animates.

Follow CLAUDE.md defensive rules: this is pure render, add no new throw paths, and do not touch the audio-player provider calls inside the callbacks.

Test updates (both files):
- Confirm all existing assertions still pass. On a fresh build each test renders a single fixed state, so each AnimatedSwitcher has only an entering child (no outgoing lingering child) — `findsOneWidget` / `findsNothing` finders and the 'Reconnecting…' / 'Connecting…' / 'Muted' / '100%' text finders remain valid after the bounded pump(50ms). If any finder now returns findsWidgets due to a lingering child, raise the pump duration past the animation duration (still bounded, never pumpAndSettle) rather than weakening the assertion.
- Add regression assertions in camera_audio_card_test.dart that lock the animations in: for the playing state, `find.byType(AnimatedSwitcher)` findsWidgets (status line + volume text); for the reconnecting/error states the banner is still findsOneWidget after the bounded pump; the muted state still resolves 'Muted' to exactly one Text.
- Re-run the full layout sweep (all widths x scenarios) — the _expectClean no-overflow and _wrapped single-line checks must all stay green at 340/360/411/480 dp, including the reconnecting @ 340dp single-line assertion.
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/widgets/camera_audio_card_test.dart test/features/monitoring/widgets/camera_audio_card_layout_test.dart</automated>
  </verify>
  <done>Banner, status line, volume text, and connecting/slider swap all animate via AnimatedSize + fade-only AnimatedSwitcher (~200-300ms). Both test files pass, including the full 340/360/411/480 dp layout sweep with no overflow exceptions and no unexpected wrapping. New assertions confirm AnimatedSwitcher presence and preserved banner/muted finders.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| (none new) | Pure UI render change inside an existing widget. No new input, network, storage, or IPC surface crosses any boundary. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-mkn-01 | Denial of Service | camera_audio_card render (AnimatedSize/AnimatedSwitcher during a state change) | low | mitigate | Fade-only switcher + clipped top-aligned AnimatedSize prevent layout overflow exceptions in the Wrap grid; layout sweep test at 340dp enforces this. No new throw paths per CLAUDE.md (no exception may kill the audio stream). |
| T-mkn-02 | Tampering | dependencies | low | accept | No new packages installed; only Flutter SDK implicit-animation widgets are used. |
</threat_model>

<verification>
- `flutter test test/features/monitoring/widgets/camera_audio_card_test.dart test/features/monitoring/widgets/camera_audio_card_layout_test.dart` passes.
- `flutter analyze lib/features/monitoring/widgets/camera_audio_card.dart` reports no new issues.
- Manual/visual (optional, on device): banner and status line fade+resize; volume text crossfades Muted↔%; connecting indicator crossfades into the slider row; spinner sits centered with its label.
</verification>

<success_criteria>
- Spinner/icon is optically centered with single-line labels; error icon aligns to the first line.
- All four state swaps animate (~200-300ms) with no popping and no card-height jump.
- Full test suite for the card (unit + layout sweep) stays green; D-10/D-11 contracts preserved.
- Constructor signature unchanged; no new throw paths.
</success_criteria>

<output>
Create `.planning/quick/260723-mkn-polish-camera-card-fix-spinner-text-alig/260723-mkn-SUMMARY.md` when done.
</output>
