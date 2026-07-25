---
phase: quick-260725-old
plan: 01
status: complete
date: 2026-07-25
commits:
  - 70a7c90 feat(theme) - add a true-black OLED variant of the dark theme
  - 90d6745 feat(settings) - add an OLED black toggle that follows dark mode from either source
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
---

# Quick Task 260725-old: Add an OLED mode to the dark theme

## Why

Roomtone's dark theme grounds on a petrol near-black (`#0B1618`), chosen so the
ground/surface/inset stack reads as distinct layers rather than a flat void. On
an OLED panel that choice costs light across the entire screen, and this is an
app that sits on a nightstand with the screen on for eight hours. A fully black
pixel on OLED draws no current at all, so there was a real win available to any
parent who wants the screen visible but as dark as physically possible.

## What changed

### The variant — `AppTheme.darkOled`

`_Roomtone` gained an OLED ramp. The two largest always-on areas go to exactly
`#000000`: the scaffold ground and the bottom navigation bar. Everything above
them is *near*-black instead — `oledSurface #0A1213` for cards, sheets and the
app bar, `oledInset #141F20` for wells and inputs, `oledHairline #1E2C2D` for
dividers. Pushing cards to black too would have collapsed them onto the ground
and erased the Nightwatch depth cues, which is a worse trade than the microwatts
it would have saved.

`_oledScheme()` is `_darkScheme().copyWith(...)` over the surface family alone.
That is deliberate: the petrol/teal accents, the status ambers and reds, and
every `on*` pairing stay shared with standard dark, so the OLED variant cannot
drift away from the brand as those evolve. `_build` grew a `{bool oled = false}`
parameter that is ignored for light — there is no low-luminance variant of a
light theme, and the light build stays byte-identical.

### The seam — why not a fourth `ThemeMode`

The requirement was that the toggle be respected "when dark mode is set by OS or
explicitly in app settings". Modelling OLED as a `ThemeMode` value would have
handled the explicit Dark choice and silently ignored the OS one.

Instead the variant is selected where the dark theme is *supplied*:

```dart
darkTheme: AppTheme.darkFor(oled: settings.oledDark),
themeMode: settings.themeMode,   // untouched
```

Flutter resolves `darkTheme` both for `ThemeMode.dark` and for `ThemeMode.system`
when the platform brightness is dark, so one swap covers both paths and nothing
downstream needs to know the preference exists.
`test/core/theme/oled_mode_wiring_test.dart` pins that resolution against a
faked platform brightness, so a future refactor that reaches for `ThemeMode`
fails there.

### The control

An "OLED black" `SwitchListTile` sits directly under the System/Light/Dark
segmented control it qualifies — it only makes sense in that context.

It stays *usable* under light mode, because the preference belongs to the dark
theme rather than being a mode of its own, and a user on System will hit dark at
sunset regardless. That makes the copy load-bearing: the subtitle keys off the
**rendered** `Theme.brightness`, not the stored `ThemeMode`, and under light says
"Applies once dark mode is active." Reading the live brightness is what keeps
that honest under System, where the stored mode alone cannot tell you which
theme is on screen.

### One defect found while testing

`oledDark` initially decoded as `json['oledDark'] as bool?`. The malformed-payload
test (mirroring the existing `themeMode` ones) caught that a wrong-typed value
throws — and `_loadFromStorage` swallows exceptions, so a single bad field would
have silently reset **every** setting, not just this one. Replaced with a
tolerant `_boolOrFalse`. The pre-existing casts on `useRtsp` and the two doubles
have the same shape and were left alone as out of scope.

## Verification

- `flutter analyze` — no issues.
- `flutter test` — 441 passing (409 → 441; +32).
- Contrast pinned numerically rather than by eye: `onSurface` clears 7:1 against
  the black ground, dividers clear 1.15:1, and every OLED background layer is
  asserted strictly less luminous than its standard-dark counterpart.
- The OLED theme was added to the existing per-theme matrices (app-bar tint
  pinning, the card-off-the-ground invariant, the camera-card smoke test), so the
  invariants the earlier redesign established now cover three themes.

## Deliberately not done

- **No divider above the bottom nav bar.** With nav and ground both pure black
  the seam between body and bottom bar disappears; the selected indicator pill
  and labels still delineate it, and adding a border would mean restructuring
  `main_shell.dart` for a cosmetic edge.
- **Android system bars untouched.** Nothing in the app sets
  `SystemUiOverlayStyle` today, so the status/navigation bar backgrounds are
  outside this change's surface.
- **No screenshot verification.** The theming is asserted numerically instead;
  the container has no display and the app's media_kit native stack does not
  come up headless.
