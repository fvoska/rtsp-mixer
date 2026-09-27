---
quick_id: 260927-qqp
status: complete
commit: bbc1597
---

# Quick Task 260927-qqp: Windows support for the PCM level tap — Summary

**Cause:** `PcmFifo.isSupported` excluded Windows, so `_sampleTap` returned
early, no `PcmLevelTap` ever started (no `PCMTAP` log lines), and the meter
ran on the `audio-bitrate` proxy, which is near-flat for Unifi AAC.

**Fix (bbc1597):**
- `PcmFifo` now wraps a platform backend: `_PosixFifo` (unchanged libc
  mkfifo code) and `_WindowsPipe` (kernel32 `CreateNamedPipeW` with
  `PIPE_NOWAIT`, `PeekNamedPipe` + `ReadFile`, re-arm via
  `DisconnectNamedPipe` + `ConnectNamedPipe` when a writer leaves; no
  `GetLastError` reliance).
- `PcmFifo.pathFor(dir, name)` returns `\\.\pipe\roomtone-<pid>-<name>` on
  Windows, the same `<dir>/roomtone-<name>.pcm` as before elsewhere.
- mpv's `ao_pcm` opens `ao-pcm-file` with `CreateFileW(GENERIC_WRITE)`
  (verified in mpv `osdep/io.c`), so it connects to the pipe unchanged.
- Tests: `pcm_fifo_path_test.dart` (runs in CI) and
  `pcm_fifo_windows_test.dart` (`@TestOn('windows')`, local only).

**Verification:** `flutter analyze --fatal-infos` clean; monitoring tests
pass on Linux. The Windows backend is not executed in CI — it needs a
real run on Windows (look for `PCMTAP ... tap opened on \\.\pipe\...` and
`level source → pcm`).
