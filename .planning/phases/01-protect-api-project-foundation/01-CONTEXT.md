# Phase 1: Protect API + Project Foundation - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Authenticate with Unifi Protect console, discover cameras, let user select 1-2 for monitoring, persist credentials and camera selection securely, and establish the Flutter project targeting macOS desktop for development iteration.

</domain>

<decisions>
## Implementation Decisions

### Login Screen
- **D-01:** Simple single-screen form with Console IP, Username, and Password fields plus a Connect button. No wizard or multi-step flow.
- **D-02:** Self-signed SSL certificates get a one-time warning on first connection. User accepts once, app remembers the choice.
- **D-03:** Login errors displayed inline under the relevant field (e.g. "Connection refused" under IP, "Invalid credentials" under password). Standard Material error pattern.

### Camera Selection
- **D-04:** Checkbox list showing all discovered cameras. User selects 1 or 2 cameras (not strictly 2 -- flexible for when one camera is offline or being moved).
- **D-05:** Each camera row shows name + online/offline status from Protect API.
- **D-06:** "Start Monitoring" button enabled when 1-2 cameras are checked, disabled otherwise.

### Auto-Connect Behavior
- **D-07:** On launch with saved credentials, auto-connect silently in the background. Show camera list once connected. If auth fails, fall back to login form with error message.
- **D-08:** Remember which cameras were last selected. On launch, auto-connect and go straight to monitoring view -- zero taps to resume overnight listening.

### Project Structure
- **D-09:** Feature-first folder organization: `lib/features/auth/`, `lib/features/cameras/`, `lib/features/monitoring/`. Each feature has its own screens/, providers/, models/ subdirectories.
- **D-10:** Shared code in `lib/core/` -- API client, secure storage, router.
- **D-11:** Single `ProtectApiClient` class handling auth, bootstrap, and camera discovery. The API surface is ~3 endpoints; no need to split into separate service classes.

### Claude's Discretion
- Navigation/routing approach (go_router vs manual Navigator)
- Riverpod provider structure details
- Specific Dio interceptor implementation for auth token management
- Flutter project configuration (build settings, platform targets)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Unifi Protect API
- `.planning/research/PROTECT-API.md` -- Protect API authentication, bootstrap, camera discovery (if exists from research phase)
- CLAUDE.md Technology Stack section -- Protect API endpoints, RTSP URLs, recommended packages

### Technology Decisions
- CLAUDE.md Recommended Stack section -- media_kit, flutter_foreground_task, dio, riverpod, flutter_secure_storage
- CLAUDE.md Key Version Constraints section -- minimum Flutter/Dart/Android SDK versions

### Reference Implementations
- `https://github.com/hjdhjd/unifi-protect` -- TypeScript reference for Protect API (noted in CLAUDE.md Sources)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None -- greenfield project, no existing code

### Established Patterns
- None yet -- this phase establishes the patterns

### Integration Points
- This phase creates the foundation that Phase 2 (RTSP streaming) will build on
- ProtectApiClient must expose camera IDs and RTSP URLs for Phase 2 to consume
- Credential storage must be available for auto-reconnect in Phase 4

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 01-protect-api-project-foundation*
*Context gathered: 2026-04-01*
