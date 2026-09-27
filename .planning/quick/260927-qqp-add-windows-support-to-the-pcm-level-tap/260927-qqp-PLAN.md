---
quick_id: 260927-qqp
mode: quick
---

# Quick Task 260927-qqp: Windows support for the PCM level tap

Activity meter / waveform is dead on Windows. Cause: `PcmFifo.isSupported`
excludes Windows, so `_sampleTap` never starts a `PcmLevelTap` and the level
falls back to the `audio-bitrate` proxy, which is near-flat for Unifi AAC
(log shows `level source → bitrate`, no `PCMTAP` lines at all).

## Task 1 — Windows named-pipe backend in `PcmFifo`

- files: `lib/features/monitoring/services/pcm_fifo.dart`,
  `lib/features/monitoring/services/pcm_level_tap.dart`
- action:
  - Split `PcmFifo` into a POSIX backend (existing libc mkfifo code) and a
    Windows backend via `kernel32.dll` FFI: `CreateNamedPipeW`
    (duplex, `FILE_FLAG_FIRST_PIPE_INSTANCE`, byte mode, `PIPE_NOWAIT`,
    `PIPE_REJECT_REMOTE_CLIENTS`, 1 instance, 64 KB buffer),
    `PeekNamedPipe` + `ReadFile` for non-blocking reads, and
    `DisconnectNamedPipe` + `ConnectNamedPipe` to re-listen when a writer
    goes away. No reliance on `GetLastError` (unreliable across Dart FFI).
  - mpv's `ao_pcm` opens the path via `CreateFileW(GENERIC_WRITE,
    CREATE_ALWAYS)` (osdep/io.c `mp_open`), which connects to a named pipe.
  - Add `PcmFifo.pathFor(dir, name)`: `\\.\pipe\roomtone-<pid>-<name>` on
    Windows, `<dir>/<name>.pcm` elsewhere; use it in `PcmLevelTap.start`.
  - `isSupported` includes Windows.
- verify: `flutter analyze`, `flutter test test/features/monitoring`
- done: tap starts on Windows; POSIX path unchanged.

## Task 2 — docs

- Update CLAUDE.md's metering row to mention the Windows named pipe.
