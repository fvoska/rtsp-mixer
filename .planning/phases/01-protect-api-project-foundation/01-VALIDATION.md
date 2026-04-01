---
phase: 1
slug: protect-api-project-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in) + mockito for mocking |
| **Config file** | None — Wave 0 must create test structure |
| **Quick run command** | `flutter test test/core/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test` + `flutter build macos --debug`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | AUTH-01 | unit | `flutter test test/core/api/protect_api_client_test.dart` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | AUTH-01 | unit | `flutter test test/core/api/dio_client_test.dart` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | AUTH-02 | unit | `flutter test test/features/cameras/camera_model_test.dart` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | AUTH-02 | unit | `flutter test test/features/cameras/camera_provider_test.dart` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 1 | AUTH-03 | unit | `flutter test test/core/storage/secure_storage_test.dart` | ❌ W0 | ⬜ pending |
| 01-03-02 | 03 | 1 | AUTH-03 | unit | `flutter test test/features/auth/auth_provider_test.dart` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 0 | PLAT-01 | smoke | `flutter build macos --debug` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/core/api/protect_api_client_test.dart` — stubs for AUTH-01 (login, CSRF)
- [ ] `test/core/api/dio_client_test.dart` — stubs for AUTH-01 (self-signed cert handling)
- [ ] `test/features/cameras/camera_model_test.dart` — stubs for AUTH-02 (model parsing)
- [ ] `test/features/cameras/camera_provider_test.dart` — stubs for AUTH-02 (camera selection)
- [ ] `test/core/storage/secure_storage_test.dart` — stubs for AUTH-03 (credential persistence)
- [ ] `test/features/auth/auth_provider_test.dart` — stubs for AUTH-03 (auto-connect)
- [ ] `pubspec.yaml` with mockito + build_runner dev dependencies
- [ ] Bootstrap JSON fixture file for deterministic test data

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Self-signed cert prompt UI | AUTH-01 | Requires visual verification of dialog | 1. Connect to Protect console with self-signed cert 2. Verify cert warning dialog appears 3. Accept and verify connection proceeds |
| macOS build runs | PLAT-01 | Smoke test requires running app | 1. `flutter run -d macos` 2. Verify app launches without crash |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
