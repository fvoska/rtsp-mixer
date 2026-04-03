---
phase: 3
slug: android-background-operation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in) |
| **Config file** | None (default Flutter test runner) |
| **Quick run command** | `flutter analyze && flutter build apk --debug` |
| **Full suite command** | `flutter test && flutter build apk --debug` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze && flutter build apk --debug`
- **After every plan wave:** Run `flutter test && flutter build apk --debug`
- **Before `/gsd:verify-work`:** Full suite must be green + physical device overnight test
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 0 | PLAT-02 | smoke | `flutter build apk --debug` | N/A | ⬜ pending |
| 03-02-01 | 02 | 1 | BGND-01 | manual | Physical device: check notification shade | N/A | ⬜ pending |
| 03-02-02 | 02 | 1 | BGND-02 | manual | `adb shell dumpsys power` + `adb shell dumpsys wifi` | N/A | ⬜ pending |
| 03-02-03 | 02 | 1 | BGND-03 | manual | Physical device: lock screen, listen for audio | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `flutter build apk --debug` — verify Android build succeeds after dependency and manifest changes
- [ ] No unit tests possible for foreground service behavior — platform-level integrations require physical device

*Existing test infrastructure covers build verification. Physical device required for runtime behavior.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Foreground service starts with notification showing camera names | BGND-01 | Android notification requires physical device | Start monitoring, pull down notification shade, verify camera names shown |
| Wake lock and WiFi lock acquired | BGND-02 | Platform-level resource acquisition | `adb shell dumpsys power \| grep "Wake Locks"` and `adb shell dumpsys wifi \| grep "Locks"` |
| Audio continues with screen off | BGND-03 | Physical audio playback verification | Start monitoring, lock screen, verify audio continues for 5+ minutes |
| App builds and runs on Android | PLAT-02 | Requires physical device | `flutter run` on connected Android device, verify app launches and functions |
| Overnight 8+ hour session | BGND-03 | Long-duration real-world test | Start monitoring at night, check in morning: audio still playing, notification still present |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
