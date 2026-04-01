# Phase 1: Protect API + Project Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 01-protect-api-project-foundation
**Areas discussed:** Login screen UX, Camera selection UX, Auto-connect behavior, Project structure

---

## Login Screen UX

### Login screen structure

| Option | Description | Selected |
|--------|-------------|----------|
| Simple form | Single screen with IP, username, password fields and Connect button | ✓ |
| Step-by-step wizard | First screen: enter IP and test connection. Second screen: credentials | |

**User's choice:** Simple form
**Notes:** None

### Self-signed certificate handling

| Option | Description | Selected |
|--------|-------------|----------|
| Accept silently | Trust all certs on LAN, no validation | |
| Show warning once | First connection shows warning with Accept button, remembers choice | ✓ |
| You decide | Claude picks | |

**User's choice:** Show warning once
**Notes:** None

### Login error display

| Option | Description | Selected |
|--------|-------------|----------|
| Inline under fields | Red text below relevant field, standard Material pattern | ✓ |
| Snackbar / toast | Brief notification at bottom of screen | |
| You decide | Claude picks | |

**User's choice:** Inline under fields
**Notes:** None

---

## Camera Selection UX

### Camera selection interaction

| Option | Description | Selected |
|--------|-------------|----------|
| Checkbox list | List of camera names with checkboxes, select exactly 2 | ✓ |
| Tap-to-select cards | Card per camera with name and status, tap to toggle | |

**User's choice:** Checkbox list
**Notes:** None

### Camera count enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Exactly 2 required | Button disabled until 2 selected, strict | |
| 1 or 2 allowed | Can start with 1 or 2 cameras, flexible | ✓ |
| You decide | Claude picks | |

**User's choice:** 1 or 2 allowed
**Notes:** None

### Camera list info

| Option | Description | Selected |
|--------|-------------|----------|
| Name only | Just camera name, clean and simple | |
| Name + status | Camera name plus online/offline indicator | ✓ |
| Name + model + status | Name, model type, and online/offline | |

**User's choice:** Name + status
**Notes:** None

---

## Auto-Connect Behavior

### Launch behavior with saved credentials

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-connect silently | Immediately connect in background, show camera list once done | ✓ |
| Show last state, connect on tap | Show camera selection, user taps to reconnect | |
| Always show login first | Pre-fill credentials but require user to hit Connect | |

**User's choice:** Auto-connect silently
**Notes:** None

### Remember camera selection

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, auto-resume | Remember cameras, go straight to monitoring on launch | ✓ |
| Remember but confirm | Remember selection but show list for confirmation | |
| No, pick every time | Always show full camera list | |

**User's choice:** Yes, auto-resume
**Notes:** Zero taps to resume overnight listening was the deciding factor

---

## Project Structure

### App organization

| Option | Description | Selected |
|--------|-------------|----------|
| Feature-first | lib/features/auth/, cameras/, monitoring/ with own screens/providers/models | ✓ |
| Layer-first | lib/screens/, providers/, models/, services/ | |
| You decide | Claude picks | |

**User's choice:** Feature-first
**Notes:** None

### API client structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single service class | One ProtectApiClient for auth, bootstrap, camera discovery | ✓ |
| Separate services per concern | ProtectAuthService, ProtectCameraService, etc. | |
| You decide | Claude picks | |

**User's choice:** Single service class
**Notes:** Only ~3 endpoints needed, can split later if it grows

---

## Claude's Discretion

- Navigation/routing approach (go_router vs manual Navigator)
- Riverpod provider structure details
- Specific Dio interceptor implementation for auth token management
- Flutter project configuration (build settings, platform targets)

## Deferred Ideas

None -- discussion stayed within phase scope
