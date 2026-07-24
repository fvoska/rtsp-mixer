# RTSP Mixer

[![Release](https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml/badge.svg)](https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml) [![Latest release](https://img.shields.io/github/v/release/fvoska/rtsp-mixer)](https://github.com/fvoska/rtsp-mixer/releases/latest)

**A baby monitor that streams live audio from two (or more) RTSP cameras at once and keeps listening all night.** It runs reliably overnight on Android with the screen off, per-camera volume mixing in your ear — something the UniFi app and VLC simply can't do.

## Camera sources

Point it at whatever cameras you already have.

- **UniFi Protect** via the official integration API (`X-API-Key`) — automatic camera discovery and per-camera RTSPS stream URLs, no manual copy-paste.
- **Manual RTSP/RTSPS cameras** for everyone else — Reolink, Tapo, or any generic RTSP source. A skip-UniFi setup path lets non-UniFi users go straight to adding their own stream URLs.

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
- **Silent live-edge drift resync** keeps you at the live edge instead of slowly falling behind.
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

- Absolute **SPL-style level bar** per camera.
- **10-second rolling waveform** chart.
- **Variation-driven card highlighting** that lights up a camera when its room gets louder.

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
