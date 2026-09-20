# Roomtone

[![Release](https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml/badge.svg)](https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml) [![Latest release](https://img.shields.io/github/v/release/fvoska/rtsp-mixer)](https://github.com/fvoska/rtsp-mixer/releases/latest)

**A baby monitor that streams live audio from two (or more) RTSP cameras at once and keeps listening all night.** It runs reliably overnight on Android with the screen off, per-camera volume mixing in your ear — something the UniFi app and VLC simply can't do.

## Camera sources

Point it at whatever cameras you already have.

- **UniFi Protect** via the official integration API (`X-API-Key`) — automatic camera discovery and per-camera RTSPS stream URLs, no manual copy-paste.
- **Manual RTSP/RTSPS cameras** for everyone else — Reolink, Tapo, or any generic RTSP source. A skip-UniFi setup path lets non-UniFi users go straight to adding their own stream URLs.
- **A spare phone as a camera** — run Roomtone on the phone in the nursery, tap "Use this phone as a camera", and it shares its microphone over Wi‑Fi. See *Phone-to-phone* below.

## Phone-to-phone

No camera at all? Two phones are enough.

- **Host mode** turns any phone running Roomtone into a camera: it captures its microphone and serves it on the local network, and keeps doing so overnight with the screen off (foreground service, wake + Wi‑Fi lock, automatic microphone recovery).
- **Auto-discovery** — the monitoring phone finds hosts on the same Wi‑Fi by itself; no IP addresses to type.
- **Pairing by code or QR** — the host shows a one-time 6-digit code and a QR code; type the code or scan it once, and the pairing is remembered on both ends. Wrong-code guessing is throttled, each code is spent after use, and the host lists paired monitors and can unpair them any time.
- **Same pipeline as every other camera** — a paired phone is just another camera in the mix: per-camera volume, reconnect-forever, zombie detection, alerts, and session history all apply. If the host's Wi‑Fi address changes, the monitor finds it again by id.
- **Host battery on the monitor** — the phone in the nursery reports its battery level and whether it is plugged in; the monitoring phone shows it on that camera's card and warns before you fall asleep if the host is running down unplugged.
- Everything stays on your LAN; nothing is relayed through the cloud.

## Listening & mixing

Your ears, your mix.

- Listen to multiple cameras **simultaneously** — the OS mixes the streams so you hear every room at once.
- **Per-camera volume and mute** — turn one room down, silence another, all live.
- More than two cameras allowed (with a gentle performance warning when you go higher).
- **Quick-add** a camera to a session that's already running, without interrupting the streams you're already listening to.

## Audio-first by design

- **Audio-only by default** — video decoding is turned off (`vid=no`) to save CPU and battery, which is what matters for an all-night monitor.
- Optional **per-camera video preview** toggle for when you want to peek — it stays off unless you ask for it.

## Overnight reliability — never silently dies

The whole point: you fall asleep trusting it's still listening.

- **Auto-reconnect** with exponential backoff and retry-forever — a dropped stream comes back on its own.
- **Zombie-stream detection** catches connections that are TCP-open but silently dead and forces a real reconnect.
- **Live-edge catch-up** — every stall leaves a little backlog; the player quietly speeds up (pitch-corrected) until it's back at the live edge, and only rebuilds the connection if the backlog is too big to trim.
- **Realtime or Buffered** — lowest delay that plays straight through jitter, or a jitter buffer of your chosen depth that never interrupts on a flaky WiFi.
- **WiFi-drop detection** and **stream liveness verification** so a flaky network doesn't leave you listening to nothing.

## Android background operation

- **Foreground service** with a persistent notification so Android won't kill the app while you sleep.
- **Lock-screen media controls** and a **wakelock** to keep the CPU alive through the night.
- Guided **battery-optimization** and **notification permission** prompts to get past OEM power management.
- **Auto-resume** monitoring after an app or device restart.

## Health & observability

Know it's working — and know why if it isn't.

- **Health-summary screen** with a per-camera event log.
- **Persisted session history** (up to 100 sessions) you can review later.
- **Active-session mini-bar** that keeps the current session in reach as you move between tabs.
- **Live log viewer** with filtering and color-coded severity.
- **Local notifications** when a stream runs into trouble.

## Audio activity at a glance

See sound without turning the volume up.

- A **real level meter** per camera, measured from the decoded audio itself: a second, silent decoder taps each stream and reads its true loudness. It learns how quiet the nursery normally is and shows how far above that the sound is right now — no per-camera calibration, no false glow from a noisy microphone.
- **Cards that glow with the sound.** The border and halo brighten as the level rises and fade as the room settles, so a cry reads from across the room and a steady hum stays dark.
- A **60-second waveform** of that same level, with the parts that lit the card drawn in green and the trigger threshold marked, so you can see what happened while you dozed.
- One **sensitivity slider** in Settings that sets how far above the room's quiet level a card lights up.

## Connectivity flexibility

- Local console address **plus an optional remote-URL fallback** (VPN / Tailscale) — configurable per console and per camera. It tries local first, then remote, so you keep working on the road.
- **RTSPS by default**, with a plain-RTSP option when you need it.
- **Quality selection** — defaults to the lowest stream since the audio is identical across qualities, saving bandwidth and battery.

## Persistence & UX

- **Volume and mute persisted** across restarts.
- **Cached cameras** for instant startup, refreshed in the background.
- Credentials stored in **platform secure storage** (with an in-memory fallback).
- **Responsive layout** for phone, tablet, and desktop, built with **Material 3**.
- A dedicated **Settings** tab.
- In-app **Help & Setup** guides — UniFi API key, Reolink, Tapo, VPN/Tailscale, and general RTSP tips.
- An **About** page with the app version, changelog, and open-source licenses.

## Platforms

- **Android** — the primary, fully-supported target. Streaming, background operation, and overnight reliability are all built and tested here.
- **macOS / Windows / Linux** — desktop scaffolds exist in the repo and are useful for development, but Android is where the app is meant to run.
- **Web** — **not supported for streaming**. Browsers cannot play RTSP directly, so there is no web monitor.

Built with **Flutter / Dart** and **media_kit** (libmpv/FFmpeg) for the RTSP audio pipeline.
