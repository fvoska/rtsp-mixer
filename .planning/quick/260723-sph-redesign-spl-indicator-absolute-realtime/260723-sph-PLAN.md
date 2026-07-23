---
phase: quick-260723-sph
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/features/monitoring/helpers/audio_level_meter.dart
  - lib/features/monitoring/models/player_state.dart
  - lib/features/monitoring/providers/audio_player_provider.dart
  - lib/features/monitoring/widgets/camera_audio_card.dart
  - lib/features/settings/screens/settings_screen.dart
  - test/features/monitoring/helpers/audio_level_meter_test.dart
  - test/features/monitoring/widgets/camera_audio_card_test.dart
autonomous: true
requirements: [QUICK-260723-SPH]
must_haves:
  truths:
    - "The level bar on a live camera card shows an ABSOLUTE pseudo-SPL derived from the mpv audio-bitrate property via a fixed log-scale mapping (floor 2 kbps → 0.0, ceiling 96 kbps → 1.0) — NOT the old pts-delta flow level and NOT baseline-relative"
    - "The card border highlight alpha is proportional to recent VARIATION (peak-to-trough over the last ~5 s of pseudo-SPL samples), still gated by the existing activityThreshold setting"
    - "Each live camera card renders a 10-second rolling Audacity-style mirrored waveform chart from the new levelHistory buffer, oldest left → newest right"
    - "When audio-pts stops advancing (silence/zombie), level is forced to 0 and silence detection behaves exactly as before"
    - "No exception raised by the new metering code can kill a running audio stream (all new poll-loop work is try/catch + appLog + continue)"
  artifacts:
    - "lib/features/monitoring/helpers/audio_level_meter.dart (pure Dart, zero media_kit/flutter imports)"
    - "test/features/monitoring/helpers/audio_level_meter_test.dart"
    - "levelHistory field on CameraAudioState with copyWith support"
    - "_WaveformChart widget in camera_audio_card.dart wrapped in RepaintBoundary"
  key_links:
    - "_pollAudioLevels → audio_level_meter.bitrateToLevel → CameraAudioState.audioLevel + levelHistory"
    - "levelHistory → audio_level_meter variation → CameraAudioState.audioActivity → border alpha in camera_audio_card.dart"
    - "levelHistory → _WaveformChart CustomPaint"
---

<objective>
Redesign the audio level / loudness (SPL) indicator on camera cards:

1. The progress bar shows a realtime pseudo-SPL estimate on an ABSOLUTE scale (deterministic log mapping of AAC encoded bitrate, not adaptive/baseline-relative).
2. The card outline highlight intensity is proportional to RECENT VARIATION of that level (visualizes a baby crying — bursts of change, not steady loudness).
3. Each live camera card gains a 10-second rolling Audacity-style mirrored waveform chart.

Purpose: today `audioLevel` is a data-flow proxy (audio-pts delta) that pins near ~0.83 whenever the stream flows — it tells the parent nothing about how loud the room is. `audioActivity` is deviation from an EMA baseline of that flow level — equally unrelated to loudness. The parent cannot glance at the card and see "quiet room" vs "baby crying".

Output: pure-Dart metering helper + unit tests, reworked poll loop, updated CameraAudioState model, redesigned card UI with waveform, updated settings copy, updated/added widget tests.

HARD CONSTRAINT (CLAUDE.md): the prebuilt media_kit FFmpeg has NO audio analysis filters (`ebur128`, `astats`, `aformat` all missing) and lavfi filter chains cannot pass `|` through mpv setProperty. Attempting an unverified lavfi audio filter KILLS the stream asynchronously. Do NOT use any lavfi/af approach. The loudness proxy is the mpv `audio-bitrate` property (already polled): Unifi cameras stream VBR AAC, so encoded bitrate correlates with signal energy — near-silence encodes to a very low bitrate, a crying baby to a high one.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@/home/user/rtsp-mixer/CLAUDE.md
@/home/user/rtsp-mixer/lib/features/monitoring/providers/audio_player_provider.dart
@/home/user/rtsp-mixer/lib/features/monitoring/models/player_state.dart
@/home/user/rtsp-mixer/lib/features/monitoring/widgets/camera_audio_card.dart
@/home/user/rtsp-mixer/lib/core/providers/settings_provider.dart
@/home/user/rtsp-mixer/lib/features/settings/screens/settings_screen.dart
@/home/user/rtsp-mixer/test/features/monitoring/widgets/camera_audio_card_test.dart
</context>

<design_decisions>
Decisions the orchestrator delegated to the planner, with rationale — implement as specified:

- **Poll cadence stays at 500 ms; history capacity = 20 samples (10 s).** Splitting into a cheap 250 ms tick plus every-Nth heavy tick would double timer complexity in a loop that already feeds three watchdogs, for marginal smoothness gain: mpv refreshes `audio-bitrate` roughly once per second anyway, so 250 ms sampling would mostly duplicate values. 20 bars over 10 s is a perfectly legible Audacity-style trail.
- **Variation statistic = peak-to-trough (max − min) over the last 10 samples (~5 s), clamped 0..1.** Chosen over std dev because: (a) with only ~10 samples, std dev underestimates short cry bursts — a single loud spike SHOULD light the border on a baby monitor; (b) levels are already 0..1 so max−min is naturally normalized with no extra scaling constant; (c) it is trivially explainable in the settings copy ("how much the level swung recently").
- **Log mapping bounds: floor 2000 bps, ceiling 96000 bps** (mpv `audio-bitrate` is in bits/sec — the existing `_StreamInfoPanel._formatBitrate` already treats it as bps). `level = ((ln(bps) − ln(2000)) / (ln(96000) − ln(2000))).clamp(0.0, 1.0)`; bps ≤ 0 or null → handled by caller (see Task 2).
- **State updates every poll tick for live cameras.** Appending a history sample makes the state unequal every tick anyway, so the old `> 0.05` change-gating on audioLevel is dropped for live cameras (2 emissions/s for 2 cameras is negligible; the notification-text update keeps its own text-diff guard, so no notification churn).
- **`_baselineLevel` is removed entirely** — the EMA baseline has no consumer once activity = history variation. Its per-camera lifecycle (clear on stop/dispose, remove on reconnect/removeCamera) is replaced by `levelHistory` living inside `CameraAudioState` (destroyed with the state) plus an explicit history reset on successful reconnect.
</design_decisions>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Pure audio-level-meter helper + unit tests</name>
  <files>lib/features/monitoring/helpers/audio_level_meter.dart, test/features/monitoring/helpers/audio_level_meter_test.dart</files>
  <behavior>
    Write the test file FIRST against this contract, watch it fail to compile/pass, then implement:
    - `bitrateToLevel(96000) == 1.0` and `bitrateToLevel(2000) == 0.0` (exact bounds, within 1e-9)
    - `bitrateToLevel(200000) == 1.0` and `bitrateToLevel(500) == 0.0` (clamped outside bounds)
    - `bitrateToLevel(0)` and `bitrateToLevel(-5)` return 0.0 (never NaN/throw — ln of non-positive input must be guarded)
    - Monotonic: for bps values [3000, 8000, 20000, 48000, 90000] each level is strictly greater than the previous
    - Midpoint sanity: `bitrateToLevel(sqrt(2000*96000))` ≈ 0.5 (log scale, tolerance 1e-6)
    - `appendLevel(history, sample, capacity: 20)`: appending to a full 20-element list returns 20 elements with the OLDEST dropped and the new sample LAST; returned list is a new instance (input not mutated); appending to empty list returns [sample]
    - `recentVariation(history, window: 10)`: flat signal (all 0.4) → 0.0; oscillating [0.1, 0.9, 0.1, 0.9, ...] → 0.8 (±1e-9); single spike in otherwise-flat window → spike minus floor; empty list and single-element list → 0.0 (no throw); only the LAST `window` samples are considered (a big swing 15 samples ago in a 20-sample history with window 10 must NOT register)
  </behavior>
  <action>
    Create `lib/features/monitoring/helpers/audio_level_meter.dart` — pure Dart, imports ONLY `dart:math`. No media_kit, no Flutter, no riverpod imports (this is what makes it unit-testable without native libs). Follow the existing helper style in `lib/features/monitoring/helpers/stream_candidates.dart` (top-level functions + doc comments).

    Provide:
    - `const kBitrateFloorBps = 2000.0;` and `const kBitrateCeilingBps = 96000.0;` and `const kLevelHistoryCapacity = 20;` and `const kVariationWindow = 10;` — exported so provider and tests share one source of truth.
    - `double bitrateToLevel(double? bps)` — null or `bps <= 0` returns 0.0; otherwise the log mapping from design_decisions, clamped 0..1. Guard against NaN/infinite input (return 0.0).
    - `List<double> appendLevel(List<double> history, double sample, {int capacity = kLevelHistoryCapacity})` — returns a NEW unmodifiable-safe list (use `List.unmodifiable` or a fresh growable copy; document choice) containing the last `capacity` samples with `sample` appended.
    - `double recentVariation(List<double> history, {int window = kVariationWindow})` — peak-to-trough over the last `window` samples, `(max − min).clamp(0.0, 1.0)`; returns 0.0 for fewer than 2 samples.

    Doc-comment each function with WHY (bitrate-as-loudness-proxy rationale, why peak-to-trough over std dev — copy the reasoning from design_decisions so the code is self-explanatory).

    Commit: `feat(monitoring): add pure bitrate-to-level meter helper with rolling history and variation`
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/helpers/audio_level_meter_test.dart</automated>
  </verify>
  <done>All behavior cases above pass; the helper file has no imports other than dart:math (verify: `grep -c "^import" lib/features/monitoring/helpers/audio_level_meter.dart` yields at most 1 and that import is dart:math).</done>
</task>

<task type="auto">
  <name>Task 2: Model field + poll-loop rewiring (level, variation, history, cleanup)</name>
  <files>lib/features/monitoring/models/player_state.dart, lib/features/monitoring/providers/audio_player_provider.dart</files>
  <action>
    **Model (`player_state.dart`):**
    - Add `final List<double> levelHistory;` to `CameraAudioState` (default `const []`), documented as "rolling pseudo-SPL samples, oldest first, capacity kLevelHistoryCapacity — feeds the waveform chart and the variation statistic". Add to the constructor and to `copyWith` using the existing `levelHistory ?? this.levelHistory` pattern (passing `const []` explicitly clears it, which the reconnect path relies on).
    - Update the doc comments on `audioLevel` ("0.0..1.0 absolute pseudo-SPL, log-mapped from AAC encoded bitrate") and `audioActivity` ("0.0..1.0 recent variation — peak-to-trough of levelHistory over ~5 s").

    **Provider (`audio_player_provider.dart`):** import the new helper (`../helpers/audio_level_meter.dart`), then:

    1. In `_pollAudioLevels`, move the `audio-bitrate` read (currently ~line 886, mid metadata block) UP so it happens right after the audio-pts flow computation — it now drives the level, not just debug info. Keep the `_zombieWatchdog.recordBitrateNonZero` feed exactly where the bitrate becomes available (same try/catch shape).
    2. Replace the old level computation (`final level = flowing ? (ptsDelta / 0.6).clamp(0.2, 1.0) : 0.0;`):
       - `flowing == false` → `level = 0.0` (pts flow detection keeps its silence/zombie role unchanged).
       - `flowing && bitrate valid (> 0)` → `level = bitrateToLevel(audioBitrate)`.
       - `flowing && bitrate null/<= 0` (mpv hasn't published a value yet — happens for ~1 s after open) → carry the previous level: `level = cam.audioLevel`. Do NOT drop to 0 here; a flowing stream with a not-yet-published bitrate must not flash as silent.
    3. Replace the EMA-baseline activity block (`prevBaseline`/`baseline`/`rawActivity`/peak-hold decay, ~lines 862-870) with:
       - `final newHistory = appendLevel(cam.levelHistory, level);`
       - `final activity = recentVariation(newHistory);`
       No peak-hold decay — the 10-sample sliding window IS the decay (a spike ages out of the border after ~5 s).
    4. Change the state-update condition: for a live camera that reached this point, ALWAYS emit the update (drop the `(level - cam.audioLevel).abs() > 0.05 || (activity ...) || (newSilence ...)` gating — a new history sample lands every tick, so gating is dead logic now). Keep computing `infoChanged`/`newInfo` as-is. Add `levelHistory: newHistory` to the `cam.copyWith(...)` call alongside audioLevel/audioActivity/silenceDuration/streamInfo. Set `changed = true`.
    5. Delete `_baselineLevel` entirely — the map declaration (line ~38) and ALL six touch-points: `build()` onDispose clear (~157), the poll-loop EMA block (replaced in step 3), `_applyReconnectStatus` remove (~1158), `stopMonitoring` clear (~1491), `removeCamera` remove (~1605). Leave every `_lastAudioPts` site untouched.
    6. In `_applyReconnectStatus`, in the existing `status == ReconnectStatus.playing` branch (where `_lastAudioPts.remove(cameraId)` already lives), also clear the history so a stale pre-outage waveform doesn't misrepresent the fresh stream: extend the `copyWith` that flips status to playing with `levelHistory: const []`, and reset `audioActivity: 0.0` there too. Note this copyWith happens earlier in the method (~line 1137) — pass the extra fields in that same call, keeping the method a single state emission.

    **Defensive rules (CLAUDE.md, non-negotiable):** all new work stays INSIDE the existing per-camera `try { ... } catch (_)` in `_pollAudioLevels`; helper calls must not be able to throw out of it (they can't — pure math — but do not restructure the try/catch). No `setProperty` calls are added. No new mpv properties are read (audio-bitrate is already read today). A failure computing level/history for one camera must not affect other cameras or the stream itself.

    Commit: `feat(monitoring): derive audio level from encoded bitrate with rolling history and variation-based activity`
  </action>
  <verify>
    <automated>flutter analyze lib/features/monitoring && flutter test test/features/monitoring</automated>
  </verify>
  <done>`_baselineLevel` no longer appears anywhere in the provider (`grep -c _baselineLevel lib/features/monitoring/providers/audio_player_provider.dart` returns 0 matches / non-zero exit); `levelHistory` flows poll → state; analyze is clean; existing monitoring tests pass.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Card UI — truthful bar, variation border, waveform chart; settings copy; widget tests</name>
  <files>lib/features/monitoring/widgets/camera_audio_card.dart, lib/features/settings/screens/settings_screen.dart, test/features/monitoring/widgets/camera_audio_card_test.dart</files>
  <behavior>
    Extend `camera_audio_card_test.dart` (reuse the existing `_pumpCard` harness and bounded-pump convention — do NOT use pumpAndSettle, see the comment at line 29):
    - Test 1: a `playing` state with `levelHistory: [0.1, 0.5, 0.9, 0.3]` renders the waveform chart (find.byKey(ValueKey('waveform-chart')) findsOneWidget)
    - Test 2: a non-live state (connecting) does NOT render the waveform chart (findsNothing)
    - Test 3: a `playing` state with `audioLevel: 0.02` and `isSuspiciouslySilent == false` shows the level bar in the online/green color, not amber (low absolute level is a normal quiet nursery, not a warning) — assert via the LinearProgressIndicator inside the level indicator having valueColor AppTheme.statusOnline
    - Test 4 (existing tests): all current tests in the file still pass unchanged
  </behavior>
  <action>
    **`camera_audio_card.dart`:**
    1. Border highlight: keep the existing gate + alpha formula (`cs.audioActivity > widget.activityThreshold`, alpha `((activity − threshold)/(1 − threshold)).clamp(0.15, 0.9)`) — the semantics change came from Task 2 (activity is now variation). Update the comment above it: it now visualizes recent variation in pseudo-SPL (baby crying = big swings), not deviation-from-baseline.
    2. `_AudioLevelIndicator`: the bar keeps showing `level` (now truthful absolute pseudo-SPL). Simplify the color logic: red (`AppTheme.statusOffline`) when `isSuspiciouslySilent`, otherwise green (`AppTheme.statusOnline`). DELETE the amber `level > 0.1` branch — a low absolute level is a normally quiet room, not a degraded state, and amber would glow all night.
    3. New private `_WaveformChart` widget: takes `List<double> history` and renders an Audacity-style chart — `RepaintBoundary(child: CustomPaint(key: ValueKey('waveform-chart'), size: Size(double.infinity, 40), painter: _WaveformPainter(...)))`. Painter draws: a 1 px horizontal center line at half height in `colorScheme.onSurface` alpha 0.15; then one mirrored vertical bar per history sample around the center line (bar half-height = sample * (height/2 − 1), minimum 1 px so silence still shows a tick). Fixed `kLevelHistoryCapacity` (import the helper for the constant) slot grid: slot width = width / capacity, samples right-aligned so a partially-filled history grows from the RIGHT edge (newest is always rightmost, oldest left, matching a scrolling recorder). Bar color `colorScheme.primary` with alpha ~0.8, ~2 px horizontal gap between bars. `shouldRepaint` returns true when the history list is not identical to the old painter's (each poll produces a new list instance, so identity comparison is correct and cheap).
    4. Mount it in `build()` inside the existing `if (cs.isLive)` block, directly below `_AudioLevelIndicator`, separated by `SizedBox(height: Spacing.xs)`, passing `cs.levelHistory`.

    **`settings_screen.dart`:** the `activityThreshold` setting keeps its name, key, persistence, range and slider wiring — ONLY interpretation copy changes. Update the 'Activity trigger' ListTile subtitle / `_activityLabel` helper so the copy describes variation, e.g. sensitivity of the card-border highlight to "changes in sound level" (most sensitive = reacts to small swings, least = only large swings like crying). Keep the same label-bucket structure `_activityLabel` already uses; just reword the strings.

    Write the three new widget tests FIRST (red), then implement. Test 3 pins the removed-amber-branch decision so a future refactor can't silently reintroduce a nightly amber glow.

    Commit: `feat(monitoring): waveform chart and variation-driven highlight on camera cards`
  </action>
  <verify>
    <automated>flutter test test/features/monitoring/widgets/camera_audio_card_test.dart && flutter analyze lib && flutter test</automated>
  </verify>
  <done>Waveform renders only for live cameras with the ValueKey('waveform-chart') finder; amber branch gone; settings copy describes variation; full test suite + analyze pass.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| mpv property values → app | `audio-bitrate` strings originate from the camera's stream via mpv; parsed with `double.tryParse`, may be empty/garbage |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-qsph-01 | DoS | _pollAudioLevels stream kill via bad property/filter | high | mitigate | No new mpv properties read, no setProperty/lavfi calls added (CLAUDE.md hard rule); all new math inside existing per-camera try/catch |
| T-qsph-02 | Tampering | Malformed audio-bitrate value → NaN/throw in log mapping | low | mitigate | bitrateToLevel guards null/≤0/NaN/infinite → 0.0; unit-tested in Task 1 |
| T-qsph-03 | DoS | Unbounded levelHistory growth over 8 h session | low | mitigate | appendLevel hard-caps at kLevelHistoryCapacity (20); capacity unit-tested |
</threat_model>

<verification>
- `flutter analyze lib` clean.
- `flutter test` full suite green (helper unit tests + monitoring widget tests + all pre-existing tests).
- Grep gates: `grep -v '^\s*//' lib/features/monitoring/providers/audio_player_provider.dart | grep -c _baselineLevel` returns 0 matches; `grep -c "ValueKey('waveform-chart')" lib/features/monitoring/widgets/camera_audio_card.dart` ≥ 1.
- Manual (optional, developer has hardware): run against a live camera — quiet room shows a low bar with small waveform ticks; talking near the camera raises the bar and lights the border; border fades ~5 s after noise stops; killing the camera network shows level 0 and the existing silence warning.
</verification>

<success_criteria>
- Level bar reflects absolute room loudness via the fixed log bitrate mapping — deterministic, identical bounds on every camera, no adaptive baseline anywhere.
- Border alpha ∝ 5 s peak-to-trough variation of pseudo-SPL, gated by the unchanged `activityThreshold` setting.
- 10 s / 20-sample mirrored waveform on every live card, RepaintBoundary-isolated, newest sample rightmost.
- audio-pts silence/zombie detection, watchdog feeds, and reconnect behavior byte-for-byte unchanged in semantics.
- Zero new mpv property reads or setProperty calls; no lavfi anywhere.
- 3 conventional commits on branch `claude/spl-indicator-redesign-255hgh` (no new branches).
</success_criteria>

<output>
Create `.planning/quick/260723-sph-redesign-spl-indicator-absolute-realtime/260723-sph-SUMMARY.md` when done.
</output>
