---
phase: quick-260516-vgb
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/features/cameras/providers/camera_state.dart
  - lib/features/cameras/providers/camera_provider.dart
  - lib/features/monitoring/screens/monitoring_screen.dart
autonomous: true
requirements:
  - QUICK-260516-VGB
must_haves:
  truths:
    - "User can select 3 or more cameras in the idle picker without checkboxes being disabled or muted."
    - "Start monitoring button is enabled whenever at least one camera is selected, regardless of count."
    - "When more than 2 cameras are selected in the picker, an inline warning banner appears under the camera list with copy 'More than 2 cameras may degrade performance and battery life.'"
    - "When monitoring is active with more than 2 cameras, a compact warning chip appears in the monitoring toolbar/header with the same warning copy."
    - "When 1 or 2 cameras are selected/active, no warning UI is shown anywhere."
    - "Existing audio streams remain untouched by these UI/state changes (no new mutations to Player loop)."
  artifacts:
    - path: "lib/features/cameras/providers/camera_state.dart"
      provides: "canStartMonitoring without 2-cap; new hasPerformanceRisk getter."
      contains: "hasPerformanceRisk"
    - path: "lib/features/cameras/providers/camera_provider.dart"
      provides: "toggleCamera that always allows additions when not already selected."
    - path: "lib/features/monitoring/screens/monitoring_screen.dart"
      provides: "Idle picker without atLimit muting + inline warning banner; live toolbar warning chip when >2 cameras."
      contains: "More than 2 cameras may degrade performance"
  key_links:
    - from: "camera_state.dart hasPerformanceRisk"
      to: "_IdleCameraPicker inline warning banner"
      via: "ref.watch(cameraNotifierProvider) -> state.hasPerformanceRisk"
      pattern: "hasPerformanceRisk"
    - from: "audioPlayerProvider state.cameras.length > 2"
      to: "_LiveToolbar warning chip"
      via: "conditional render in monitoring screen"
      pattern: "cameras.length > 2"
---

<objective>
Relax the hard 2-camera cap in the picker and selection state, and surface a non-blocking performance/battery warning when the user picks (or is monitoring) more than 2 cameras.

Purpose: Some users want 3+ rooms covered overnight. The 2-cap is a soft recommendation, not a technical requirement — the rest of the stack is already N-agnostic (CameraAudioCard loop, persistence). We replace the gate with an advisory.

Output: One plan, one task. State + provider + UI updated; no playback paths touched; no new dependencies.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md

<interfaces>
<!-- Contracts the executor will modify. Extracted from current source so no
     codebase exploration is needed. -->

From lib/features/cameras/providers/camera_state.dart (current):
```dart
class CameraState {
  final List<ProtectCamera> cameras;
  final Set<String> selectedIds;
  const CameraState({this.cameras = const [], this.selectedIds = const {}});
  bool get canStartMonitoring => selectedIds.isNotEmpty && selectedIds.length <= 2;
  List<ProtectCamera> get selectedCameras =>
      cameras.where((c) => selectedIds.contains(c.id)).toList();
  CameraState copyWith({List<ProtectCamera>? cameras, Set<String>? selectedIds}) => ...;
}
```

From lib/features/cameras/providers/camera_provider.dart (current toggleCamera):
```dart
void toggleCamera(String cameraId) {
  final current = state.value;
  if (current == null) return;
  final newIds = Set<String>.from(current.selectedIds);
  if (newIds.contains(cameraId)) {
    newIds.remove(cameraId);
    appLog('CAM', 'Deselected camera $cameraId (${newIds.length} selected)');
  } else if (newIds.length < 2) {
    newIds.add(cameraId);
    appLog('CAM', 'Selected camera $cameraId (${newIds.length} selected)');
  } else {
    return;
  }
  state = AsyncData(current.copyWith(selectedIds: newIds));
  ref.read(storageProvider).saveSelectedCameraIds(newIds.toList());
}
```

From lib/features/monitoring/screens/monitoring_screen.dart (relevant regions):
- Line 366: doc comment `/// Idle state: pick up to 2 cameras + Start Monitoring.`
- Line 424: `final atLimit = state.selectedIds.length >= 2;`
- Line 460: `final muted = atLimit && !selected;` then `Opacity(opacity: muted ? 0.5 : 1.0, child: CheckboxListTile(...))`
- Line 434: header copy `'Choose 1 or 2 cameras to monitor'`
- `_LiveToolbar` (lines 330-364): always-visible header during active monitoring; currently a `Row` with title `'Cameras'` + two `TextButton.icon` controls. Receives no camera count today.
- `_LiveMonitoringView.build` (line 289): has `state.cameras` in scope — this is the camera count source for the toolbar warning.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Drop 2-cap and add performance warning (state, provider, UI)</name>
  <files>lib/features/cameras/providers/camera_state.dart, lib/features/cameras/providers/camera_provider.dart, lib/features/monitoring/screens/monitoring_screen.dart</files>
  <action>
Make three coordinated edits. Do NOT add code comments explaining the change (per project convention — comments only for non-obvious WHY). Do NOT touch any audio/Player code paths.

1. camera_state.dart:
   - Change `canStartMonitoring` to: `bool get canStartMonitoring => selectedIds.isNotEmpty;`
   - Add new getter directly below it: `bool get hasPerformanceRisk => selectedIds.length > 2;`

2. camera_provider.dart `toggleCamera` (around line 87):
   - Replace the `else if (newIds.length < 2) { ... } else { return; }` branches with a single unconditional add branch. The result should be:
     - If `newIds.contains(cameraId)` -> remove + log Deselected.
     - Else -> always add + log Selected.
   - Keep the existing appLog tags ('CAM') and message format with the running count.
   - State assignment and storage save call stay unchanged.

3. monitoring_screen.dart:
   - Line ~366: update doc comment to `/// Idle state: pick cameras to monitor + Start Monitoring.` (so it stops claiming "up to 2").
   - Line ~424: delete `final atLimit = state.selectedIds.length >= 2;`.
   - In the ListView.builder itemBuilder (around line 457-481): delete `final muted = atLimit && !selected;` and remove the `Opacity` wrapper around `CheckboxListTile`. The item becomes simply the `CheckboxListTile(...)` directly. Checkboxes for non-selected items are always enabled.
   - Line ~434: change picker header text to `'Choose cameras to monitor — 2 recommended'`.
   - Insert a new warning banner widget between the `Expanded(child: ListView.builder(...))` block and the `SafeArea(...)` bottom Start button — i.e. as a sibling in the `_IdleCameraPicker`'s outer `Column`, directly below `Expanded`. Render conditionally: only when `state.hasPerformanceRisk` is true. Use a tonal warning style sourced from the current theme — no new dependencies:
     - Container with `color: theme.colorScheme.tertiaryContainer` (Material 3 tonal surface; the project does not define a dedicated warning role).
     - Horizontal padding `Spacing.lg`, vertical padding `Spacing.sm`.
     - Row with `Icon(Icons.warning_amber_outlined, size: 18, color: theme.colorScheme.onTertiaryContainer)`, `SizedBox(width: Spacing.sm)`, then `Expanded(child: Text('More than 2 cameras may degrade performance and battery life.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer)))`.
     - The Row uses `crossAxisAlignment: CrossAxisAlignment.center` so it stays one line on wide layouts and wraps gracefully on narrow.
   - Add the same warning to the active-monitoring header. The cleanest hook is `_LiveToolbar`: extend its constructor with `final int cameraCount;` (required), pass `state.cameras.length` from `_LiveMonitoringView.build` (we already have `state` in scope at line 289 within the `data:` callback). In `_LiveToolbar.build`, when `cameraCount > 2`, render a compact warning chip as the first child of the toolbar Row (before the title `Expanded`). Use Material 3 `Chip` or a small `Container` styled the same way as the picker banner but compact:
     - Prefer `Chip(avatar: Icon(Icons.warning_amber_outlined, size: 16, color: theme.colorScheme.onTertiaryContainer), label: Text('More than 2 cameras may degrade performance and battery life.', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onTertiaryContainer)), backgroundColor: theme.colorScheme.tertiaryContainer, visualDensity: VisualDensity.compact)` followed by `SizedBox(width: Spacing.sm)`.
     - The existing `Expanded(child: Text('Cameras', ...))` and the two `TextButton.icon`s stay after it.
   - Wire-up: in `_LiveMonitoringView.build` where `_LiveToolbar(...)` is constructed (around line 301-306), pass `cameraCount: state.cameras.length`.

After edits, run a quick textual sweep (grep) of these three files to confirm no other `<= 2`, `< 2`, or `>= 2` literals tied to the camera-count cap remain. Persistence and CameraAudioCard rendering are already generic (per task spec) and need no change.
  </action>
  <verify>
    <automated>cd /Users/fvoska/projects/personal/rtsp-audio-mixer &amp;&amp; flutter analyze lib/features/cameras/providers/camera_state.dart lib/features/cameras/providers/camera_provider.dart lib/features/monitoring/screens/monitoring_screen.dart 2>&amp;1 | tail -20 &amp;&amp; grep -nE '(&lt;= ?2|&lt; ?2|&gt;= ?2)' lib/features/cameras/providers/camera_state.dart lib/features/cameras/providers/camera_provider.dart lib/features/monitoring/screens/monitoring_screen.dart || true &amp;&amp; grep -n 'More than 2 cameras may degrade performance and battery life' lib/features/monitoring/screens/monitoring_screen.dart &amp;&amp; grep -n 'hasPerformanceRisk' lib/features/cameras/providers/camera_state.dart lib/features/monitoring/screens/monitoring_screen.dart</automated>
  </verify>
  <done>
    - `canStartMonitoring` no longer enforces `length <= 2`.
    - `hasPerformanceRisk` getter exists on CameraState and returns `length > 2`.
    - `toggleCamera` no longer rejects additions past 2.
    - Idle picker: no `atLimit` / `Opacity` muting; header copy updated; warning banner renders only when selection > 2.
    - Live monitoring toolbar: warning chip renders only when active camera count > 2.
    - `flutter analyze` reports no new errors in the three files.
    - Audio playback paths and providers (audio_player_provider, audio_handler, etc.) are untouched.
  </done>
</task>

</tasks>

<verification>
Manual smoke (developer):
1. Launch app, navigate to Monitor tab idle picker.
2. Select 1 camera -> no warning banner, Start enabled.
3. Select 2 cameras -> no warning banner, Start enabled.
4. Select a 3rd camera -> checkbox accepts the tap; warning banner appears under the list; Start still enabled.
5. Deselect back to 2 -> warning banner disappears.
6. Start monitoring with 3 cameras -> toolbar shows compact warning chip; all three CameraAudioCards render.
7. Stop monitoring -> picker returns; selection persists with warning still visible.
</verification>

<success_criteria>
- All three files compile (`flutter analyze` clean for them).
- Selection of any positive count is allowed; warning UI driven by `hasPerformanceRisk` (picker) and `state.cameras.length > 2` (live toolbar) with the exact copy "More than 2 cameras may degrade performance and battery life."
- No regression in 1- and 2-camera flows (no warning shown, Start button behaves identically to before).
- No edits to audio/Player code paths.
</success_criteria>

<output>
After completion, create `.planning/quick/260516-vgb-allow-more-than-2-cameras-with-performan/260516-vgb-01-SUMMARY.md`
</output>
