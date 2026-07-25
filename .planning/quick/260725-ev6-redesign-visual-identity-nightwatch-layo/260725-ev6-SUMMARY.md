---
phase: quick-260725-ev6
plan: 01
subsystem: presentation
tags: [theme, typography, branding, design-system, android]
status: complete
requires:
  - lib/core/theme/app_theme.dart
  - lib/core/providers/settings_provider.dart
  - lib/features/monitoring/widgets/camera_audio_card.dart
provides:
  - AppTheme.light / AppTheme.dark (explicit Roomtone ColorSchemes)
  - StatusColors ThemeExtension + context.statusColors / theme.statusColors
  - AppTypography (Outfit / Nunito Sans / Roboto Mono, tabular numerics)
  - AppSettings.themeMode (persisted, user-selectable)
  - Radii + Touch scales in lib/core/theme/spacing.dart
  - formatUptime() shared pure helper
  - Crescent level-meter mark, adaptive launcher icons, themed splash
affects:
  - Every screen (theme, typography)
  - Monitor screen, camera cards, health summary, active session bar
  - Android launcher icon, splash, foreground-service notification
tech-stack:
  added:
    - flutter_launcher_icons ^0.14.4 (dev)
    - flutter_native_splash ^2.4.6 (dev)
    - 6 vendored static TTFs (Outfit, Nunito Sans, Roboto Mono)
    - Pillow 12.3.0 (build-time only, not a Dart dependency)
  patterns:
    - ThemeExtension for domain colours instead of fixed const Colors
    - Committed Python gates for downloaded/generated binary assets
    - Enum persisted by stable name, never by index
key-files:
  created:
    - lib/core/theme/status_colors.dart
    - lib/core/theme/app_typography.dart
    - lib/features/monitoring/helpers/uptime_format.dart
    - tool/branding/verify_fonts.py
    - tool/branding/generate_mark.py
    - tool/branding/verify_assets.py
    - assets/fonts/*.ttf (6)
    - assets/branding/ (2 SVG masters + 5 PNG sources)
    - test/core/theme/status_colors_test.dart
    - test/core/theme/light_theme_smoke_test.dart
    - test/features/monitoring/helpers/uptime_format_test.dart
  modified:
    - lib/core/theme/app_theme.dart
    - lib/core/theme/spacing.dart
    - lib/core/providers/settings_provider.dart
    - lib/core/services/foreground_service.dart
    - lib/app.dart
    - lib/features/settings/screens/settings_screen.dart
    - lib/features/monitoring/widgets/camera_audio_card.dart
    - lib/features/monitoring/widgets/active_session_bar.dart
    - lib/features/monitoring/screens/monitoring_screen.dart
    - lib/features/monitoring/screens/health_summary_screen.dart
    - pubspec.yaml
    - android/app/src/main/AndroidManifest.xml
    - android/app/src/main/res/ (icons, splash, styles, colors)
decisions:
  - "Roomtone neutrals beyond the pitch's locked anchors were derived, not invented from a different palette — see Deviations D-01."
  - "Bars run inward from radius 40 so the crescent's outer rim is a clean arc and nothing clips the 100x100 canvas."
  - "PNG framing fits the mark's ink bounding box, not the arc centre, so the launcher icon is optically centred."
  - "Notification icon travels on startService/updateService NotificationIcon — AndroidNotificationOptions 9.2.2 has no icon field (verified in pub cache)."
  - "Theme mode persisted as 'system'/'light'/'dark', never the enum index."
metrics:
  duration: ~45 min
  completed: 2026-07-25
  tasks: 5
  commits: 6
  files_changed: 93
  tests: 356 -> 409 (+53)
---

# Quick Task 260725-ev6: Nightwatch / Roomtone Visual Identity Summary

Replaced the stock seeded-Material look with an owned identity: explicit Roomtone petrol/teal light **and** dark themes, a persisted user-selectable theme mode, three vendored typefaces with tabular numerics, the Nightwatch card shape with a live activity halo, and a crescent level-meter logo in place of the default Flutter icon.

## What the user will see

**Everywhere**

- The app is no longer indigo-seeded Material. It is petrol and teal: a near-black blue-green ground (`#0B1618`) with teal accents in dark mode, and a soft grey-green ground with white cards and a deeper teal in light mode.
- Type changed. Screen titles and headlines render in **Outfit SemiBold**; all body, label, and control text in **Nunito Sans**; every number in **Roboto Mono with tabular figures**. Fonts ship inside the app, so they render identically with the WiFi down.
- Sliders got physically bigger — a ~17px thumb on a 6px track, everywhere at once (camera cards and Settings).
- The bottom navigation bar now sits visually *below* the body in dark mode (darker than the ground) instead of floating at the same shade.

**Settings**

- A new **Appearance** section is the first thing on the screen, with a full-width **System / Light / Dark** segmented control. Tapping a segment reflows the entire app instantly, and the choice survives a restart.

**Monitor screen**

- A calm status line under the toolbar while a session is live: a slowly pulsing teal dot and `Listening · 6h 12m`, with the duration in tabular mono so it does not shuffle sideways as the minutes tick. Nothing renders at all when idle.
- Camera cards are visibly softer and roomier: 20px corners (was 12), 24px internal padding (was 16), and one more step of breathing room between every internal row.
- Making noise near a camera now raises a **soft teal glow** around the card, not just a 2px outline — and the glow's spread and blur scale with how loud the swing was, then fade back down.
- Tap targets grew: the mute / video / remove buttons in the card header, the quality dropdown, and the zoom-and-pan buttons over the video preview are all at least 48dp now (the header buttons were 36dp).
- Everything that was there is still there and still works: status banner, status dot, camera name, source badge, video toggle, debug toggle, remove, Live/Connecting line, level bar, waveform, volume slider, mute, quality selector, video preview with zoom/pan/reset, and the stream info panel.

**Sessions / Health / mini-bar**

- Session uptime, downtime, and reconnect counts render in tabular mono. The "Monitoring · 7m" mini-bar's duration does too.
- Status colours are now brightness-aware. In light mode the old mid-green (`#81C784`) measured **1.75:1** against a white card — effectively invisible. It is now `#0B8578` at **4.5:1**. Every status colour clears 3:1 in both brightnesses, which is pinned by a test.

**Android**

- The launcher icon is the crescent level-meter mark — teal bars fanned across an arc over a centre dot, on petrol. The stock Flutter logo is gone from all five density folders (proven by md5).
- Adaptive icon with a proper foreground/background split, plus an Android 13 monochrome layer so themed icons pick up the wallpaper tint.
- The splash screen matches the theme: light grey in light mode, petrol in dark, including the Android 12+ splash API.
- The ongoing monitoring notification uses a dedicated crescent status-bar icon with a teal accent instead of the app icon.

## Task Breakdown

| # | Task | Commit |
|---|------|--------|
| 1 | Roomtone light+dark themes and StatusColors extension | `61891ed` |
| 2 | Persisted themeMode wired end-to-end | `4e97cb6` |
| 3 | Vendor Outfit / Nunito Sans / Roboto Mono, build TextTheme | `28fd113` |
| 4 | Nightwatch shape — card restyle, activity halo, Monitor status line | `5252c1e` |
| 5 | Crescent logo, launcher icons, splash, notification icon | `6e9fc45` |
| + | Light-theme smoke coverage (added during verification) | `8395651` |

The sixth commit is test-only. Light mode is new and nothing else in the suite rendered under it, so a light-only regression (an unreadable pairing, a null extension lookup) would have gone unnoticed; it pins that the camera card builds cleanly in both brightnesses across live, reconnecting, and error states.

## Verification

| Gate | Result |
|------|--------|
| `flutter analyze --fatal-infos` | Clean after every task |
| `flutter test` | 409 passing (was 356) |
| No `AppTheme.status*` in `lib/` or `test/` | Confirmed, zero matches |
| `python3 tool/branding/verify_fonts.py` | 6/6 real TTFs, magic `00010000`, 48–107 KB |
| `python3 tool/branding/verify_assets.py` | 10/10 PNGs valid, sized, non-blank |
| Stock launcher md5s under `mipmap-*` | All 5 gone |
| `mipmap-anydpi-v26/ic_launcher.xml` | Present with background + foreground + monochrome |
| Generator determinism | Two consecutive runs byte-identical |
| Audio / RTSP / reconnect / watchdog | **Zero diff** in `providers/`, `services/`, `zombie/`, `reconnect/` |

## Defensive-error-handling compliance (CLAUDE.md)

Every new presentation path degrades rather than throws:

- **Theme lookup** — `StatusColors.of()` falls back to the brightness-matched instance and logs once if the extension is missing or there is no `Theme` in scope. A card built under a bare `ThemeData` cannot crash. Covered by four tests.
- **Activity halo** — `_activityIntensity()` rejects NaN, infinity, and a threshold of 1.0 (divide-by-zero), returning null so the card renders with no halo. `audioActivity` is written by a twice-a-second mpv poll, so this is a live risk during an 8-hour session. Covered by three tests.
- **Uptime ticker** — the `Timer.periodic` body is wrapped; the uptime read is wrapped and returns null (renders nothing) on any failure; `formatUptime` is total over negative durations (`0s`, never `-1h -3m`). Covered by tests.
- **Notification icon** — resolved natively through a manifest meta-data lookup that the plugin already wraps in try/catch, falling back to the app icon. Cannot affect service start/stop.
- Fallback logging is one-shot in both hot paths, so a degraded state cannot spam the log file all night.

## Deviations from Plan

### 1. [Plan gap] Font URLs were not actually recorded in the plan

Task 3 said to "copy the six URLs verbatim from the locked decision recorded in the task description", but the plan text contains only the *directory prefixes*, not the hashed filenames. Resolved them from the Google Fonts CSS API with a legacy user-agent (which yields TTF rather than WOFF2). Every resolved URL landed under exactly the version paths the plan pinned — `/s/outfit/v15/`, `/s/nunitosans/v19/`, `/s/robotomono/v31/` — confirming they are the same assets that were verified during planning. All six verify as real TrueType.

### 2. [Plan gap] Only the palette *anchors* were specified; neutrals were derived

The plan pinned the five status colours per brightness, petrol `#0B1618`, light ground `#EBF0EF`, teal `#3FBFAD`, and mono `#0F1F21`, but not the card, inset, ink, muted, hairline, or nav values it asks to be mapped onto scheme roles. Those were derived to sit on the same petrol/teal axis (all neutrals are blue-green-biased, not neutral grey) and are collected in one `_Roomtone` block in `app_theme.dart`. No colour from a different palette family was introduced.

### 3. [Correction] Splash config key `color_light` does not exist

The plan specified `color: "#0B1618"` and `color_light: "#EBF0EF"`. `flutter_native_splash` has no `color_light` key — it uses `color` for light mode and `color_dark` for dark. Implemented the stated *intent* (petrol in dark, light ground in light) with the real keys: `color: "#EBF0EF"`, `color_dark: "#0B1618"`. Also added a per-brightness splash image, since the dark-mode teal reads at only ~2.2:1 on the light ground.

### 4. [API reality] Notification icon lives on `startService`, not `AndroidNotificationOptions`

As the plan anticipated, `AndroidNotificationOptions` in flutter_foreground_task 9.2.2 exposes **no** icon or accent-colour parameter — verified by reading the installed pub-cache source, per the plan's explicit warning about the `isSticky` incident. Rather than leaving the notification unbranded, used the real API this version does expose: `startService(notificationIcon: NotificationIcon(...))` and the same on `updateService`. `AndroidNotificationOptions` is unchanged and service start/stop behaviour is untouched. Note the icon is addressed by an AndroidManifest `<meta-data>` name, not a resource path, so a manifest entry was added.

### 5. [Geometry] Bars run inward from radius 40; PNGs frame the ink, not the arc centre

Two adjustments were needed to make the specified geometry produce a usable icon:

- Bars *centred* on radius 40 with a max length of 24 would reach radius 52 on a 100-unit canvas and clip. They run **inward** from radius 40 instead, so the crescent's outer rim is a clean arc and nothing spills. All pinned values (22 bars, −118°→+118°, radius 40, length 7→24 sin-eased, stroke 5.4, round caps, dot r=6.5) are unchanged.
- The crescent's *ink* is top-heavy relative to the arc centre (the gap is at the bottom), so framing PNGs on (50,50) put the launcher icon visibly high in its mask. Each PNG is fitted to the ink bounding box instead. Verified visually.

### 6. [Improvement] The SVG master is generated from the same constants

The plan asked for a hand-authored `mark.svg` plus a numerically-equivalent Python script. Instead `generate_mark.py` emits **both** from one geometry block, so the SVG and the PNGs cannot drift. The SVG is still plain, readable, hand-editable markup; it just carries a "regenerate, don't hand-edit" header.

### 7. [Test shape] `ActiveSessionBar` label became rich text

Rendering only the duration in tabular mono (keeping "Monitoring" in the UI face) required `Text.rich`. The three existing assertions were updated from `find.text(...)` to `find.text(..., findRichText: true)` — same expected strings, same count. No test was deleted or weakened.

### 8. [Observation] There is no pan slider to preserve

The plan's control inventory lists a "pan slider". Confirmed against `HEAD~3` that `camera_audio_card.dart` has only ever had **one** `Slider` (volume) — L/R panning is deferred because the prebuilt media_kit FFmpeg ships no `pan` filter (CLAUDE.md). Nothing was removed. The widget's stale doc comment, which promised a pan slider and would have made the next reader think this restyle deleted one, was corrected to match reality.

### 9. [Minor] Separator glyph and segmented-button icons

- Used `Listening · 6h 12m` (middle dot) rather than the plan's `Listening - 6h 12m`, matching the app's existing separator convention (`Monitoring · 7m`, `Device: id · model · mac`).
- The Appearance segmented control uses labels only, no leading icons — with icons the three segments overflow at ~320dp. The plan specified "System / Light / Dark" and did not require icons.

## Known Stubs

None. No placeholder values, hardcoded empties, or TODO markers were introduced.

## Not Verified Here (requires a device)

The two `<human-check>` items in the plan need a real Android install and cannot be exercised in this environment:

- Fonts and the non-jittering uptime as rendered on-device.
- Launcher icon in the launcher, themed-icon setting rendering the monochrome layer, splash in both brightnesses, and the notification small icon.

Everything checkable without a device — asset validity, dimensions, md5 replacement, adaptive-layer presence, analyze, and the test suite — passes. The generated 1024px sources and one generated `mipmap-xxxhdpi/ic_launcher.png` were also inspected visually and render the intended crescent.

## Self-Check: PASSED

All created files exist on disk and all five commit hashes resolve in `git log`.
