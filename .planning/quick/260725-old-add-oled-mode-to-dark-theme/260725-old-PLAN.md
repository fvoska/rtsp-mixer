---
phase: quick-260725-old
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/core/theme/app_theme.dart
  - lib/core/providers/settings_provider.dart
  - lib/app.dart
  - lib/features/settings/screens/settings_screen.dart
  - test/core/theme/app_theme_test.dart
  - test/core/theme/light_theme_smoke_test.dart
  - test/core/theme/oled_mode_wiring_test.dart
  - test/core/providers/settings_provider_test.dart
  - test/features/settings/oled_toggle_test.dart
autonomous: true
requirements: [QUICK-260725-old]

must_haves:
  truths:
    - "An OLED toggle exists alongside the System/Light/Dark control, and turning it on drops the dark theme's background layers to (near-)black so an OLED panel emits as little light as possible overnight."
    - "The toggle is respected however dark mode was reached: an explicit Dark choice AND ThemeMode.system resolving dark from the OS. It is a property of the dark theme, not a fourth theme mode."
    - "Light mode is byte-identical with the toggle on or off — there is no low-luminance variant of a light theme."
    - "The scaffold ground and the bottom navigation bar — the two largest always-on areas — are exactly #000000, because a black OLED pixel draws no current at all."
    - "Cards, sheets and the app bar stay *near*-black rather than black, so the Nightwatch ground/surface/inset stack keeps its depth cues; a card that collapsed onto the ground would be a worse trade than a few microwatts."
    - "Brand accents, status colours and every on* pairing are shared with the standard dark theme, not re-authored, so the OLED variant cannot drift from the identity as those evolve."
    - "Body text clears 7:1 against the black ground and dividers stay visible against it — the parent reading a camera name half-asleep is the reason the mode exists at all."
    - "The preference persists across restarts under a stable JSON key, and a malformed or absent value degrades to off instead of throwing (a throw inside fromJson is swallowed by _loadFromStorage, which would silently reset EVERY setting)."
  artifacts:
    - "lib/core/theme/app_theme.dart — _Roomtone OLED near-black ramp, _oledScheme() derived from _darkScheme() via copyWith, AppTheme.darkOled, AppTheme.darkFor({required bool oled})."
    - "lib/core/providers/settings_provider.dart — AppSettings.oledDark (default false, persisted as 'oledDark'), SettingsNotifier.setOledDark, tolerant _boolOrFalse decode."
    - "lib/app.dart — darkTheme: AppTheme.darkFor(oled: settings.oledDark)."
    - "lib/features/settings/screens/settings_screen.dart — 'OLED black' SwitchListTile under Appearance with brightness-aware subtitle copy."
    - "test/core/theme/oled_mode_wiring_test.dart — pins that darkTheme is what Flutter resolves for BOTH ThemeMode.dark and OS-resolved system dark."
    - "test/features/settings/oled_toggle_test.dart — the switch renders, writes the setting, sits under the theme picker, and tells the truth while light is on screen."
  key_links:
    - "SwitchListTile → SettingsNotifier.setOledDark → AppSettings.oledDark → storage."
    - "AppSettings.oledDark → AppTheme.darkFor(oled:) → MaterialApp.darkTheme → resolved by Flutter for ThemeMode.dark and for ThemeMode.system when the OS is dark."
    - "_darkScheme() → _oledScheme() via copyWith (surface family only) → _build(Brightness.dark, oled: true)."
---

<objective>
Add an OLED mode to the existing dark theme: an extra toggle that drops the
theme's background layers to black for minimal display luminance on OLED
screens, where a fully black pixel emits no light at all.

Purpose: this app is left running overnight, in a dark room, often propped on a
nightstand with the screen on. The Roomtone dark palette is a petrol near-black
(`#0B1618`) — deliberately not black, so the ground/surface/inset stack reads as
layers. On an OLED panel that choice costs real light output across the whole
screen. Parents who want the screen visible but as dark as physically possible
have no way to get there today.

Constraint that shapes the whole design: the toggle must apply whenever dark
mode is *active*, whether the user picked Dark explicitly in Settings or left
the app on System and the OS resolved dark. That rules out modelling it as a
fourth `ThemeMode`; it belongs to the dark theme itself.

Output: a persisted `oledDark` preference, an `AppTheme.darkOled` variant
selected at the `MaterialApp.darkTheme` seam, and an "OLED black" switch under
Appearance whose subtitle is honest about when the flip takes effect.
</objective>

<tasks>

### Task 1: A true-black variant of the dark theme

files:
  - lib/core/theme/app_theme.dart
  - test/core/theme/app_theme_test.dart
  - test/core/theme/light_theme_smoke_test.dart

action:
- Add an OLED ramp to `_Roomtone`: `oledGround`/`oledNav` at `#000000` (the two
  largest always-on areas, where the saving actually lives), `oledSurface`
  `#0A1213` for cards/sheets/app bar, `oledInset` `#141F20` for wells and
  inputs, `oledHairline` `#1E2C2D`.
- Derive `_oledScheme()` from `_darkScheme().copyWith(...)`, overriding *only*
  the surface family (`surface`, the four `surfaceContainer*` steps,
  `surfaceContainerLowest`, `outlineVariant`, `onInverseSurface`). Deriving
  rather than re-authoring is what keeps the accents from drifting.
- Widen `_build` to `_build(Brightness, {bool oled = false})`; `oled` is
  ignored for light. Expose `AppTheme.darkOled` and
  `AppTheme.darkFor({required bool oled})`.

verify:
- `flutter analyze` clean.
- OLED theme added to the existing per-theme test matrices (app-bar pinning,
  card-off-the-ground invariant, camera-card smoke test).
- New assertions: ground/canvas/nav are exactly `#000000`; every background
  layer is strictly less luminous than its standard-dark counterpart; accents
  and `on*` roles are identical to `AppTheme.dark`; `onSurface` clears 7:1
  against the black ground; the divider clears 1.15:1 against it.

done: `AppTheme.darkOled` renders every Roomtone layer at minimum luminance
without losing contrast or the layer separation.

### Task 2: Persist the preference and expose it in Appearance

files:
  - lib/core/providers/settings_provider.dart
  - lib/app.dart
  - lib/features/settings/screens/settings_screen.dart
  - test/core/providers/settings_provider_test.dart
  - test/core/theme/oled_mode_wiring_test.dart
  - test/features/settings/oled_toggle_test.dart

action:
- `AppSettings.oledDark` (default `false`) threaded through `copyWith`, `==`,
  `hashCode`, `toJson`, `fromJson`, plus `SettingsNotifier.setOledDark`. Decode
  through a tolerant `_boolOrFalse` rather than an `as bool?` cast.
- `lib/app.dart`: `darkTheme: AppTheme.darkFor(oled: settings.oledDark)`,
  leaving `themeMode` untouched. Choosing the variant at this seam is precisely
  what makes the preference independent of how dark mode was reached.
- Settings: an "OLED black" `SwitchListTile` directly under the theme picker it
  qualifies. Subtitle keys off the *rendered* `Theme.brightness`, so under light
  (explicit or OS-resolved) it says the flip applies once dark mode is active
  instead of looking like a broken toggle.

verify:
- Round-trip and malformed-payload tests (absent / null / wrong-typed) for
  `oledDark`, and that it survives being stored under every `ThemeMode`.
- Widget test resolving the real wiring under a faked platform brightness:
  black ground for `ThemeMode.dark` with a light OS, black ground for
  `ThemeMode.system` with a dark OS, standard petrol with the toggle off, and
  light untouched either way.
- Widget test on the Settings screen: switch present, writes the setting,
  ordered under the theme picker, honest copy under light.

done: flipping the switch changes the dark theme immediately, survives a
restart, and behaves identically whether dark came from Settings or the OS.

</tasks>
