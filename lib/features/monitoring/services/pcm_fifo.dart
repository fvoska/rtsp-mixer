import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';

/// A non-blocking reader for a named pipe that another thread — here, mpv's
/// `ao=pcm` output inside the same process — writes raw PCM into. A POSIX
/// FIFO on Android, Linux, macOS and iOS; a Win32 named pipe on Windows.
///
/// Why a FIFO and not a file: `ao=pcm` writes forever, and 8 kHz mono s16
/// is 16 KB/s — ~460 MB over an 8 h night if it landed on disk. A pipe holds
/// at most 64 KB and hands the bytes straight to Dart.
///
/// Why FFI and not `dart:io`: `dart:io` cannot create a FIFO, and opening
/// one for reading blocks until a writer appears, which would pin an IO
/// thread (forever, if the metering player never manages to open). Opening
/// with `O_NONBLOCK` through libc returns immediately, and `read()` then
/// yields whatever has arrived — polled from the existing 250 ms level
/// tick, no threads, no callbacks.
///
/// Semantics of [readAvailable]:
/// * bytes arrived → they are returned;
/// * writer connected, nothing new → empty list (`EAGAIN`);
/// * no writer yet, or writer gone → empty list (`read` returns 0).
/// All three are "nothing to meter right now" to the caller.
///
/// On Windows there are no FIFOs in the filesystem, but mpv's `ao_pcm` opens
/// its output with a plain `CreateFileW(GENERIC_WRITE)` (mpv `osdep/io.c`),
/// which connects to a named pipe just as happily. So the Windows backend
/// creates `\\.\pipe\roomtone-…` with `CreateNamedPipeW` in `PIPE_NOWAIT`
/// mode and polls it with `PeekNamedPipe` + `ReadFile`, same semantics. Use
/// [pathFor] to get a path that is valid on the current platform.
///
/// Supported on Android, Linux, macOS, iOS and Windows. Elsewhere (web)
/// [isSupported] is false and [open] returns null; the level meter falls
/// back to the bitrate proxy. Nothing in this file can throw out to the
/// caller — every OS failure is logged and turns into a null/empty result.
class PcmFifo {
  PcmFifo._(this.path, this._reader);

  /// Filesystem path of the FIFO, or the `\\.\pipe\…` name on Windows.
  final String path;
  final _PipeReader _reader;

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isIOS ||
          Platform.isWindows);

  /// The pipe path for [name] on this platform: `<dir>/roomtone-<name>.pcm`
  /// for a POSIX FIFO, or `\\.\pipe\roomtone-<pid>-<name>` on Windows, where
  /// pipes live in their own namespace (not in [dir]) and are machine-wide,
  /// so the process id keeps two running instances apart. [windows] and
  /// [processId] exist for tests.
  static String pathFor(String dir, String name,
      {bool? windows, int? processId}) {
    if (windows ?? (!kIsWeb && Platform.isWindows)) {
      return '\\\\.\\pipe\\roomtone-${processId ?? pid}-$name';
    }
    return '$dir/roomtone-$name.pcm';
  }

  /// Create the pipe at [path] (replacing any stale POSIX file) and open its
  /// read side without blocking. Returns null — after logging — when the
  /// platform is unsupported or the OS refuses.
  static PcmFifo? open(String path) {
    if (!isSupported) return null;
    final reader =
        Platform.isWindows ? _WindowsPipe.create(path) : _PosixFifo.create(path);
    return reader == null ? null : PcmFifo._(path, reader);
  }

  bool get isOpen => _reader.isOpen;

  /// Drain everything currently in the pipe, up to [maxBytes]. Never
  /// blocks, never throws; an empty list means nothing was available.
  Uint8List readAvailable({int maxBytes = 64 * 1024}) =>
      _reader.readAvailable(maxBytes);

  /// Close the read side and remove the pipe. Call this only AFTER the
  /// writer has been shut down (see [PcmLevelTap]) so mpv never writes into
  /// a reader-less pipe. Idempotent.
  void close() => _reader.close();
}

/// One platform's non-blocking pipe reader. Implementations never throw.
abstract class _PipeReader {
  bool get isOpen;
  Uint8List readAvailable(int maxBytes);
  void close();
}

/// POSIX FIFO through libc: `mkfifo` + `open(O_RDONLY | O_NONBLOCK)`.
class _PosixFifo implements _PipeReader {
  _PosixFifo._(this.path, this._fd, this._libc);

  final String path;
  int _fd;
  final _Libc _libc;

  /// `O_NONBLOCK` differs per kernel: 0x800 on Linux/Android (every
  /// architecture Flutter ships for), 0x4 on Darwin.
  static int get _oNonBlock => (Platform.isMacOS || Platform.isIOS) ? 0x4 : 0x800;

  static const _oRdOnly = 0;

  /// `SIGPIPE` is 13 on Linux and Darwin. `SIG_IGN` is the address 1.
  static const _sigPipe = 13;

  static _PosixFifo? create(String path) {
    try {
      final libc = _Libc.load();
      if (libc == null) return null;
      // Writing to a pipe whose reader has gone away raises SIGPIPE, which
      // kills the process by default. Android's runtime and the Dart VM
      // both normally ignore it already; ignoring it again is harmless and
      // makes the teardown ordering in [close] a belt AND braces.
      try {
        libc.signal(_sigPipe, Pointer.fromAddress(1));
      } catch (e) {
        appLog('PCMTAP', 'signal(SIGPIPE, SIG_IGN) failed (continuing): $e');
      }
      final cPath = path.toNativeUtf8();
      try {
        // A leftover FIFO (or file) from a crashed session is unlinked
        // first so mkfifo starts clean.
        libc.unlink(cPath);
        // 0600: owner read/write only.
        if (libc.mkfifo(cPath, 0x180) != 0) {
          appLog('PCMTAP', 'mkfifo($path) failed');
          return null;
        }
        final fd = libc.open(cPath, _oRdOnly | _oNonBlock);
        if (fd < 0) {
          appLog('PCMTAP', 'open($path, O_RDONLY|O_NONBLOCK) failed');
          libc.unlink(cPath);
          return null;
        }
        return _PosixFifo._(path, fd, libc);
      } finally {
        malloc.free(cPath);
      }
    } catch (e) {
      appLog('PCMTAP', 'FIFO setup failed for $path: $e');
      return null;
    }
  }

  @override
  bool get isOpen => _fd >= 0;

  @override
  Uint8List readAvailable(int maxBytes) {
    if (_fd < 0) return Uint8List(0);
    final buf = malloc.allocate<Uint8>(maxBytes);
    try {
      var total = 0;
      while (total < maxBytes) {
        final n = _libc.read(_fd, buf + total, maxBytes - total);
        // 0 = no writer / EOF, negative = EAGAIN (or an error, which is
        // indistinguishable without errno and equally "nothing now").
        if (n <= 0) break;
        total += n;
      }
      if (total == 0) return Uint8List(0);
      // Copy out of native memory before freeing it.
      return Uint8List.fromList(buf.asTypedList(total));
    } catch (e) {
      appLog('PCMTAP', 'read($path) failed: $e');
      return Uint8List(0);
    } finally {
      malloc.free(buf);
    }
  }

  @override
  void close() {
    if (_fd < 0) return;
    try {
      _libc.close(_fd);
    } catch (e) {
      appLog('PCMTAP', 'close($path) failed: $e');
    }
    _fd = -1;
    final cPath = path.toNativeUtf8();
    try {
      _libc.unlink(cPath);
    } catch (e) {
      appLog('PCMTAP', 'unlink($path) failed: $e');
    } finally {
      malloc.free(cPath);
    }
  }
}

typedef _MkfifoC = Int32 Function(Pointer<Utf8>, Uint32);
typedef _MkfifoD = int Function(Pointer<Utf8>, int);
// `open` is variadic in C, but with no variadic arguments passed the fixed
// arguments travel in registers on every ABI we ship for, so a two-argument
// signature is correct.
typedef _OpenC = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenD = int Function(Pointer<Utf8>, int);
typedef _ReadC = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _ReadD = int Function(int, Pointer<Uint8>, int);
typedef _CloseC = Int32 Function(Int32);
typedef _CloseD = int Function(int);
typedef _UnlinkC = Int32 Function(Pointer<Utf8>);
typedef _UnlinkD = int Function(Pointer<Utf8>);
typedef _SignalC = Pointer<Void> Function(Int32, Pointer<Void>);
typedef _SignalD = Pointer<Void> Function(int, Pointer<Void>);

/// The handful of libc calls we need, looked up in the running process
/// (libc is always loaded). Resolved once and cached.
class _Libc {
  _Libc._(this.mkfifo, this.open, this.read, this.close, this.unlink,
      this.signal);

  final _MkfifoD mkfifo;
  final _OpenD open;
  final _ReadD read;
  final _CloseD close;
  final _UnlinkD unlink;
  final _SignalD signal;

  static _Libc? _cached;

  static _Libc? load() {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final lib = DynamicLibrary.process();
      final libc = _Libc._(
        lib.lookupFunction<_MkfifoC, _MkfifoD>('mkfifo'),
        lib.lookupFunction<_OpenC, _OpenD>('open'),
        lib.lookupFunction<_ReadC, _ReadD>('read'),
        lib.lookupFunction<_CloseC, _CloseD>('close'),
        lib.lookupFunction<_UnlinkC, _UnlinkD>('unlink'),
        lib.lookupFunction<_SignalC, _SignalD>('signal'),
      );
      _cached = libc;
      return libc;
    } catch (e) {
      appLog('PCMTAP', 'libc lookup failed — PCM tap unavailable: $e');
      return null;
    }
  }
}

/// Win32 named pipe through kernel32: the server (read) end of
/// `\\.\pipe\roomtone-…`, which mpv's `ao_pcm` opens as a client with
/// `CreateFileW(GENERIC_WRITE)`.
///
/// `PIPE_NOWAIT` keeps every call non-blocking, including the
/// `ConnectNamedPipe` that re-arms the pipe after a writer leaves. Each read
/// first asks `PeekNamedPipe` how many bytes are waiting, so `ReadFile` is
/// only ever asked for bytes that are already there. `GetLastError` is not
/// consulted — the Dart VM may clobber it between FFI calls — so a failed
/// peek is read as "no writer": either none connected yet, or (if one had
/// been) it went away, in which case the pipe is disconnected and put back
/// into the listening state for the next writer. Windows has no SIGPIPE: a
/// writer whose reader has gone gets a write error, nothing worse.
class _WindowsPipe implements _PipeReader {
  _WindowsPipe._(this.path, this._handle, this._k32);

  final String path;
  int _handle;
  final _Kernel32 _k32;

  /// True once a peek succeeded, i.e. a writer is (or was) connected.
  bool _connected = false;

  static const _invalidHandle = -1;

  // CreateNamedPipeW flags.
  static const _pipeAccessDuplex = 0x00000003;
  static const _fileFlagFirstPipeInstance = 0x00080000;
  static const _pipeTypeByte = 0x00000000;
  static const _pipeReadModeByte = 0x00000000;
  static const _pipeNoWait = 0x00000001;
  static const _pipeRejectRemoteClients = 0x00000008;
  static const _bufferSize = 64 * 1024;

  static _WindowsPipe? create(String path) {
    try {
      final k32 = _Kernel32.load();
      if (k32 == null) return null;
      final cPath = path.toNativeUtf16();
      try {
        // Duplex rather than inbound so the open succeeds whatever access
        // mask the writer asks for. FIRST_PIPE_INSTANCE fails the call if
        // the name is already taken instead of silently sharing it.
        final handle = k32.createNamedPipe(
          cPath,
          _pipeAccessDuplex | _fileFlagFirstPipeInstance,
          _pipeTypeByte |
              _pipeReadModeByte |
              _pipeNoWait |
              _pipeRejectRemoteClients,
          1,
          _bufferSize,
          _bufferSize,
          0,
          nullptr,
        );
        if (handle == _invalidHandle || handle == 0) {
          appLog('PCMTAP', 'CreateNamedPipeW($path) failed');
          return null;
        }
        // A fresh instance already accepts a client; no ConnectNamedPipe
        // is needed until a writer has come and gone.
        return _WindowsPipe._(path, handle, k32);
      } finally {
        malloc.free(cPath);
      }
    } catch (e) {
      appLog('PCMTAP', 'named pipe setup failed for $path: $e');
      return null;
    }
  }

  @override
  bool get isOpen => _handle != _invalidHandle;

  @override
  Uint8List readAvailable(int maxBytes) {
    if (_handle == _invalidHandle) return Uint8List(0);
    final avail = malloc<Uint32>();
    final got = malloc<Uint32>();
    Pointer<Uint8>? buf;
    try {
      avail.value = 0;
      if (_k32.peekNamedPipe(_handle, nullptr, 0, nullptr, avail, nullptr) ==
          0) {
        if (_connected) {
          // The writer went away (mpv reopened its output, or the tap is
          // shutting down): re-arm for the next one.
          _connected = false;
          _k32.disconnectNamedPipe(_handle);
          _k32.connectNamedPipe(_handle, nullptr);
        }
        return Uint8List(0);
      }
      _connected = true;
      final want = avail.value < maxBytes ? avail.value : maxBytes;
      if (want <= 0) return Uint8List(0);
      final b = malloc.allocate<Uint8>(want);
      buf = b;
      var total = 0;
      while (total < want) {
        got.value = 0;
        final ok = _k32.readFile(
          _handle,
          b + total,
          want - total,
          got,
          nullptr,
        );
        if (ok == 0 || got.value == 0) break;
        total += got.value;
      }
      if (total == 0) return Uint8List(0);
      // Copy out of native memory before freeing it.
      return Uint8List.fromList(b.asTypedList(total));
    } catch (e) {
      appLog('PCMTAP', 'read($path) failed: $e');
      return Uint8List(0);
    } finally {
      malloc.free(avail);
      malloc.free(got);
      if (buf != null) malloc.free(buf);
    }
  }

  @override
  void close() {
    if (_handle == _invalidHandle) return;
    try {
      _k32.disconnectNamedPipe(_handle);
    } catch (e) {
      appLog('PCMTAP', 'DisconnectNamedPipe($path) failed: $e');
    }
    try {
      _k32.closeHandle(_handle);
    } catch (e) {
      appLog('PCMTAP', 'CloseHandle($path) failed: $e');
    }
    // The pipe name disappears with its last handle; nothing to unlink.
    _handle = _invalidHandle;
  }
}

typedef _CreateNamedPipeC =
    IntPtr Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Uint32,
      Pointer<Void>,
    );
typedef _CreateNamedPipeD =
    int Function(Pointer<Utf16>, int, int, int, int, int, int, Pointer<Void>);
typedef _PeekNamedPipeC =
    Int32 Function(
      IntPtr,
      Pointer<Void>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _PeekNamedPipeD =
    int Function(
      int,
      Pointer<Void>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    );
typedef _ReadFileC =
    Int32 Function(
      IntPtr,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _ReadFileD =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _ConnectNamedPipeC = Int32 Function(IntPtr, Pointer<Void>);
typedef _ConnectNamedPipeD = int Function(int, Pointer<Void>);
typedef _HandleOpC = Int32 Function(IntPtr);
typedef _HandleOpD = int Function(int);

/// The kernel32 calls the Windows backend needs. Resolved once and cached.
class _Kernel32 {
  _Kernel32._(
    this.createNamedPipe,
    this.peekNamedPipe,
    this.readFile,
    this.connectNamedPipe,
    this.disconnectNamedPipe,
    this.closeHandle,
  );

  final _CreateNamedPipeD createNamedPipe;
  final _PeekNamedPipeD peekNamedPipe;
  final _ReadFileD readFile;
  final _ConnectNamedPipeD connectNamedPipe;
  final _HandleOpD disconnectNamedPipe;
  final _HandleOpD closeHandle;

  static _Kernel32? _cached;

  static _Kernel32? load() {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final lib = DynamicLibrary.open('kernel32.dll');
      final k32 = _Kernel32._(
        lib.lookupFunction<_CreateNamedPipeC, _CreateNamedPipeD>(
          'CreateNamedPipeW',
        ),
        lib.lookupFunction<_PeekNamedPipeC, _PeekNamedPipeD>('PeekNamedPipe'),
        lib.lookupFunction<_ReadFileC, _ReadFileD>('ReadFile'),
        lib.lookupFunction<_ConnectNamedPipeC, _ConnectNamedPipeD>(
          'ConnectNamedPipe',
        ),
        lib.lookupFunction<_HandleOpC, _HandleOpD>('DisconnectNamedPipe'),
        lib.lookupFunction<_HandleOpC, _HandleOpD>('CloseHandle'),
      );
      _cached = k32;
      return k32;
    } catch (e) {
      appLog('PCMTAP', 'kernel32 lookup failed — PCM tap unavailable: $e');
      return null;
    }
  }
}
