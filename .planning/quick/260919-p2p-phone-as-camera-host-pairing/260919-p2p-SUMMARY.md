---
phase: quick-260919-p2p
plan: 01
status: complete
date: 2026-09-19
commits:
  - feat(peer): add phone-to-phone protocol core — pairing codes, discovery beacon, WAV host server
  - feat(cameras): model paired phones as a third camera source
  - feat(peer): add host mode — share this phone's microphone as a camera
  - feat(peer): add monitor-side pairing — discovery list, QR scan, manual entry
  - feat(monitoring): play paired phones through the existing stream pipeline
  - test(peer): widget-test the host and pairing screens
files_modified:
  - pubspec.yaml (record, mobile_scanner, qr_flutter, crypto)
  - android/settings.gradle.kts (Kotlin 2.1.0 → 2.2.20)
  - android/app/src/main/AndroidManifest.xml
  - lib/features/peer/** (new feature: 17 files)
  - lib/features/cameras/{models/protect_camera,providers/camera_provider,providers/camera_state,widgets/camera_source_badge}.dart
  - lib/features/monitoring/{models/player_state,providers/audio_player_provider,screens/monitoring_screen,widgets/camera_audio_card}.dart
  - lib/core/{storage/storage_service,services/foreground_service,router/app_router}.dart
  - lib/app.dart, lib/features/auth/screens/login_screen.dart, lib/features/settings/screens/settings_screen.dart, lib/features/help/screens/help_screen.dart
  - README.md
  - test/features/peer/** (11 files), test/features/cameras/*, test/core/storage/storage_service_test.dart
---

# Quick Task 260919-p2p: Phone-to-phone — a spare phone as a camera, paired by code or QR

## Why

Not every nursery has an RTSP camera, but every household has an old phone.
The app already knew how to keep two streams alive all night; what it lacked
was a *source* that needs no console and no camera brand. Host mode makes any
phone running Roomtone that source.

## What was built

### Transport: an endless WAV over plain HTTP

The host captures PCM16 mono 16 kHz from its microphone (`record`) and serves it
as a never-ending WAV (`RIFF`/`data` sizes `0xFFFFFFFF`, which FFmpeg's demuxer
reads as "streaming") at `http://<host>:47831/roomtone/v1/audio.wav?token=…`.
That URL is handed to the *unchanged* media_kit pipeline on the monitor:
reconnect supervisor, zombie/drift watchdogs, alert policy, mix persistence and
session history all apply to a phone camera exactly as to a UniFi one —
including the PCM-tap loudness meter from quick task 260919-foa, which opens a
second connection to the host and meters the decoded stream like any other
camera. A `/status` side channel additionally carries the host's own dBFS
reading (`LevelSource.host`); it is the level *fallback* for phone cameras when
the tap is not delivering, because the bitrate proxy is blind on a
constant-bitrate PCM stream. The host counts distinct monitors, not
connections, so the tap's second connection does not show as a second
listener.

The audio endpoint writes to a **detached socket** rather than `HttpResponse`:
`dart:io` defers write errors until `close()`, so a monitor that vanished
mid-stream would never have been noticed and its listener would have leaked
until the host stopped. The raw socket reports the peer's FIN and a broken
pipe within a couple of writes (verified empirically before choosing it). A
listener more than five seconds behind is dropped so it reconnects at the live
edge — a gap beats growing delay on a baby monitor.

### Discovery: a dependency-free UDP beacon

The host answers JSON probes on UDP 47830 (unicast reply to the prober); the
monitor broadcasts to `255.255.255.255` and to each interface's `/24` broadcast.
Chosen over an mDNS plugin because it is deterministic, needs no native code,
and is exercised end-to-end on loopback in `flutter test`. QR and a typed
address remain as fallbacks for networks that block broadcast. The same beacon
lets the monitor **re-resolve a host by id** before every open and reconnect,
so a DHCP lease change never strands a paired phone (the last address stays
the fallback).

### Pairing: one-time codes, hashed tokens, throttled guessing

The host shows a crypto-random 6-digit code and a `roomtone://pair?…` QR that
carries host id, address, port and code. `POST /pair` with the right code
returns a 256-bit bearer token; the host stores only `SHA-256(token)` per
paired monitor and **rotates the code after every successful pairing**. Five
wrong codes in a minute lock pairing for sixty seconds; comparisons are
constant-time. Paired monitors are listed on the host screen and can be
revoked live (the next status poll or stream open gets 401). Re-pairing from
the same monitor replaces its old token on the host, and re-pairing with the
same host replaces the camera entry on the monitor while keeping its id, so
saved selection and mix state carry over.

### Background operation on the host

`ForegroundServiceManager` gained a second tenant. Host mode needs the
`microphone` service type (Android 14+ denies background mic access to a
media-playback-only service), so the one service is started with the union of
needed types, restarted when the second feature joins and needs a type the
running instance lacks, and *handed over* — never stopped — when only one of
monitoring/hosting ends. The monitor's own service now explicitly requests
`mediaPlayback` only; requesting `microphone` without `RECORD_AUDIO` granted
would throw on Android 14. A dead microphone stream is restarted with capped
exponential backoff while the server keeps serving; host mode auto-resumes on
the next app launch while the flag is set.

### UI

`/host` (reachable before login — the nursery phone needs no console) shows
name, start/stop, the code, the QR, the LAN addresses, a mic level meter, the
listener count and the paired monitors. `/pair` lists discovered hosts (tap →
code dialog), offers "Scan QR code" (`mobile_scanner`, with graceful
no-camera/no-permission fallback) and "Enter address and code manually".
Entry points: the setup screen, Settings → Phone cameras, and the Monitor tab's
"+" menu. `CameraSourceBadge` now labels UniFi / Manual / Phone and shows when
more than one source type is present. Every surface that used to print a
manual camera's URL prints `host:port` for a phone — the URL carries the token.

## Decisions worth remembering

- **Merged with main's PCM-tap meter (260919-foa).** The tap is primary for
  phone cameras too (same calibration, same 0..1 scale as every other card);
  the host-reported dBFS is only the fallback. Cost: one extra HTTP
  connection per monitor to the host phone, ~256 kbit/s on the LAN.
- **Kotlin Gradle plugin 2.1.0 → 2.2.20.** `record_android` and
  `mobile_scanner` build against Kotlin 2.2+/2.3 toolchains; 2.2.20 is the
  newest KGP officially paired with the project's AGP 8.11.1 / Gradle 8.13.
  **The Android build could not be run in this environment** (Android SDK
  downloads are blocked); the change is by-the-docs, not by-the-build.
- Token in a query parameter, not a header: the whole candidate/reconnect
  machinery works on URLs, and the LAN is the only surface.
- No `AuthMode.host`: hosting is orthogonal to how the *monitor* is set up.
  The login screen shows a banner while this phone is hosting instead of
  redirecting, so a hosting phone can still be logged in as a monitor.

## Verification

`flutter analyze --fatal-infos` clean; 563 tests green after merging main, including
loopback tests of the HTTP server (pairing, throttle, auth, streaming header +
PCM, listener bookkeeping, stop), the UDP beacon/scanner/resolver, the pairing
client, the host notifier (start/stop, pairing + code rotation + revoke, level
meter, mic restart, denied permission, auto-resume, live rename), the level
poller, and widget tests for the host and pairing screens. Untested here: a
real Android build and on-device microphone/QR behaviour.
