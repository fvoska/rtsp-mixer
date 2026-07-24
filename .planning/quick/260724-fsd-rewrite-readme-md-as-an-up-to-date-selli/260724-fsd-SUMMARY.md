---
phase: quick-260724-fsd
plan: 01
subsystem: docs
tags: [readme, documentation, marketing]
status: complete
requires: []
provides:
  - "README.md as a feature-overview landing document"
affects:
  - README.md
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - README.md
decisions:
  - "Kept H1 title and both badges from line 3 verbatim; rewrote everything below."
  - "Framed reliability features under a 'never silently dies' heading to match the core project value."
  - "Platforms section states web is unsupported for streaming; desktop is scaffold-only; Android is primary."
metrics:
  duration: ~3min
  completed: 2026-07-24
---

# Quick Task 260724-fsd: Rewrite README.md as an up-to-date selling-point overview Summary

Rewrote `README.md` from a 5-line stub into a scannable, benefit-oriented feature overview organized into ten sections, preserving the H1 title and both release badges verbatim.

## What Was Done

**Task 1: Rewrite README.md as a feature-overview landing document** (commit `7cf79a7`)

Replaced the single descriptive paragraph below the badge line with a full feature landing page. Content:

- Punchy tagline capturing the core value (multi-camera simultaneous audio, reliable overnight on Android with the screen off, beats UniFi app + VLC).
- Feature sections drawn from the verified dispatch catalog: Camera sources (UniFi Protect integration API + manual RTSP for Reolink/Tapo/generic), Listening & mixing (multi-camera, per-camera volume/mute, >2 cameras with warning, quick-add), Audio-first (audio-only `vid=no` default + optional video preview), Overnight reliability (auto-reconnect/backoff, zombie-stream detection, drift resync, WiFi-drop detection, liveness verification), Android background operation (foreground service, lock-screen controls, wakelock, permission prompts, auto-resume), Health & observability (health summary, session history up to 100, active-session mini-bar, live log viewer, local notifications), Audio activity (SPL level bar, 10s waveform, variation-driven highlight), Connectivity flexibility (remote-URL fallback, RTSPS/RTSP, quality selection), Persistence & UX (persisted volume/mute, cached cameras, secure storage, responsive Material 3, Settings tab, Help & Setup guides, About page).
- Honest Platforms section: Android primary/fully-supported; macOS/Windows/Linux desktop scaffolds; web NOT supported for streaming (browsers can't play RTSP).
- Brief built-with mention (Flutter/Dart, media_kit/libmpv).

Every claim traces to the verified catalog and CHANGELOG.md. No invented features. No stereo-panning claim (deferred). No cry/smart-detection alerting sold as a headline feature.

## Verification

Plan's automated `<verify>` passed:
- README is >= 25 lines.
- Contains `badge.svg`, `img.shields.io/github/v/release`, `# RTSP Mixer`, at least one `## ` heading.
- Contains no `stereo pan` text.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- README.md exists and modified (commit `7cf79a7`, 80 insertions, 1 deletion).
- Commit `7cf79a7` present in git log on branch `claude/update-project-readme-tca2fl`.
- No unexpected file deletions.
