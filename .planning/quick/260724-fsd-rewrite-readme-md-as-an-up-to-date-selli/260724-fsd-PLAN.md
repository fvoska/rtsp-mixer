---
phase: quick-260724-fsd
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - README.md
autonomous: true
requirements: []
quick_task: true

must_haves:
  truths:
    - "README opens with the app's purpose and keeps the existing badge line intact"
    - "README lists real, shipped features grouped into readable sections — no invented capabilities"
    - "README states the honest platform story: Android primary; desktop scaffolds present; web cannot play RTSP"
  artifacts:
    - "README.md — rewritten as a feature-overview landing document"
  key_links:
    - "Every feature claim traces to CHANGELOG.md or the scouted lib/ catalog"
---

<objective>
Rewrite `README.md` from a 5-line stub into an up-to-date, selling-point-style overview of what RTSP Mixer actually does, organized into scannable feature sections.

Purpose: The current README undersells the app — it mentions only "two rooms" audio mixing and UniFi, but the app now supports manual RTSP cameras, multi-camera mixing, overnight reliability watchdogs, health/observability screens, audio-activity visualization, remote-URL fallback, and rich UX. A newcomer should understand the app's value at a glance.

Output: A single rewritten `README.md`.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@README.md
@CHANGELOG.md
@CLAUDE.md

The task background in the dispatch already contains a verified feature catalog (cross-checked against CHANGELOG.md and lib/). Treat that catalog as the source of truth for feature claims. Do NOT invent features beyond it. Do NOT read the codebase further — the catalog is sufficient.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Rewrite README.md as a feature-overview landing document</name>
  <files>README.md</files>
  <action>
    Replace the body of `README.md` (everything after the badge line) with a structured, selling-point overview of the app's shipped features.

    PRESERVE EXACTLY (do not modify):
    - The `# RTSP Mixer` H1 title (line 1).
    - The badges line (line 3) — the Release workflow badge and the Latest release shields.io badge, including their existing markdown image-in-link syntax.

    Open with a punchy 1-2 sentence tagline capturing the core value: a baby monitor that streams audio from two (or more) RTSP cameras simultaneously and runs reliably overnight on Android with the screen off — something the UniFi app and VLC can't do.

    Then organize the shipped features into scannable sections with headings and bullet lists. Use these groupings (drawn from the verified catalog in the dispatch context):
    - Camera sources: UniFi Protect via the official integration API (X-API-Key), automatic camera list, per-camera RTSPS stream URLs; AND manual RTSP/RTSPS cameras for non-UniFi users (Reolink, Tapo, generic) with a skip-UniFi setup path.
    - Listening & mixing: multi-camera simultaneous listening, per-camera volume mixing and mute, more than two cameras allowed (with a performance warning), quick-add cameras to a live session.
    - Audio-first: audio-only by default (video decoding off, vid=no) to save CPU/battery, with an optional per-camera video preview toggle.
    - Overnight reliability: auto-reconnect with exponential backoff (retry-forever), zombie-stream detection (TCP-open-but-silent), silent live-edge drift resync, WiFi-drop detection, and stream liveness verification — framed as "never silently dies."
    - Android background operation: foreground service with persistent notification, lock-screen media controls, wakelock, battery-optimization and notification permission prompts, auto-resume monitoring after restart.
    - Health & observability: health-summary screen with per-camera event log, persisted session history (up to 100 sessions), active-session mini-bar, live log viewer with filtering/color coding, and local notifications for stream problems.
    - Audio activity at a glance: absolute SPL-style level bar, 10-second waveform chart, and variation-driven card highlighting.
    - Connectivity flexibility: local console address plus remote-URL (VPN/Tailscale) fallback per console and per camera, RTSPS by default with a plain-RTSP option, quality selection (defaults to lowest since audio is identical).
    - Persistence & UX: volume/mute persisted across restarts, cached cameras for instant startup with background refresh, credentials in platform secure storage (in-memory fallback), responsive phone/tablet/desktop layout, Material 3, a Settings tab, in-app Help & Setup guides (UniFi API key, Reolink, Tapo, VPN/Tailscale, general RTSP tips), and an About page (version, changelog, licenses).

    Add a "Platforms" section stating the honest platform story: Android is the primary and fully-supported target; macOS/Windows/Linux desktop scaffolds exist in the repo; web is NOT supported for streaming because browsers cannot play RTSP (do not oversell web). Reference the built-with stack briefly (Flutter/Dart, media_kit/libmpv) if it reads naturally, but keep the focus on features, not a dependency dump.

    Tone: confident and benefit-oriented ("selling point") but strictly accurate — every claim must trace to the verified catalog. Do NOT claim features that are not in the catalog (e.g., no cry/smart-detection alerting as a shipped headline feature beyond the local stream-problem notifications actually listed; no L/R stereo panning — it is deferred). Keep it readable: prefer short intro lines under each heading plus tight bullets. Use standard GitHub-flavored markdown only.
  </action>
  <verify>
    <automated>test "$(node -e "const b=require('fs').readFileSync('README.md','utf8').split('\n').length; process.stdout.write(String(b>=25))")" = "true" && node -e "const s=require('fs').readFileSync('README.md','utf8'); const ok = s.includes('badge.svg') && s.includes('img.shields.io/github/v/release') && s.includes('# RTSP Mixer') && /## /.test(s) && !/stereo pan/i.test(s); process.exit(ok?0:1)"</automated>
  </verify>
  <done>
    README.md retains the H1 title and both badges from the original line 3, has grown into a multi-section feature overview (multiple `##` headings, 25+ lines), includes a Platforms section that does not claim web RTSP support, and makes no claims outside the verified feature catalog (no stereo-panning claim).
  </done>
</task>

</tasks>

<verification>
- Original badge line preserved verbatim (Release workflow badge + shields.io latest-release badge).
- Feature sections present and each claim maps to the verified catalog / CHANGELOG.md.
- Platforms section is honest about web (no RTSP in browsers) and desktop being scaffolds.
- No invented features; no deferred features (stereo panning) presented as shipped.
- File is valid GitHub-flavored markdown.
</verification>

<success_criteria>
README.md reads as a clear, accurate, selling-point overview of RTSP Mixer's real capabilities, keeps the existing badges, and correctly frames platform support.
</success_criteria>

<output>
Create `.planning/quick/260724-fsd-rewrite-readme-md-as-an-up-to-date-selli/260724-fsd-SUMMARY.md` when done.
Commit with: `docs(readme): rewrite as up-to-date feature overview`
</output>
