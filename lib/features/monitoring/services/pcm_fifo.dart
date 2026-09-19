import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';

/// A non-blocking reader for a POSIX named pipe (FIFO) that another process
/// thread — here, mpv's `ao=pcm` output inside the same process — writes raw
/// PCM into.
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
/// Supported on Android, Linux, macOS and iOS. On other platforms
/// [isSupported] is false and [open] returns null; the level meter falls
/// back to the bitrate proxy. Nothing in this file can throw out to the
/// caller — every libc failure is logged and turns into a null/empty result.
class PcmFifo {
  PcmFifo._(this.path, this._fd, this._libc);

  /// Filesystem path of the FIFO.
  final String path;
  int _fd;
  final _Libc _libc;

  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isIOS);

  /// `O_NONBLOCK` differs per kernel: 0x800 on Linux/Android (every
  /// architecture Flutter ships for), 0x4 on Darwin.
  static int get _oNonBlock => (Platform.isMacOS || Platform.isIOS) ? 0x4 : 0x800;

  static const _oRdOnly = 0;

  /// `SIGPIPE` is 13 on Linux and Darwin. `SIG_IGN` is the address 1.
  static const _sigPipe = 13;

  /// Create the FIFO at [path] (replacing any stale file) and open its read
  /// side without blocking. Returns null — after logging — when the
  /// platform is unsupported or libc refuses.
  static PcmFifo? open(String path) {
    if (!isSupported) return null;
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
        return PcmFifo._(path, fd, libc);
      } finally {
        malloc.free(cPath);
      }
    } catch (e) {
      appLog('PCMTAP', 'FIFO setup failed for $path: $e');
      return null;
    }
  }

  bool get isOpen => _fd >= 0;

  /// Drain everything currently in the pipe, up to [maxBytes]. Never
  /// blocks, never throws; an empty list means nothing was available.
  Uint8List readAvailable({int maxBytes = 64 * 1024}) {
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

  /// Close the read side and remove the FIFO. Call this only AFTER the
  /// writer has been shut down (see [PcmLevelTap]) so mpv never writes into
  /// a reader-less pipe. Idempotent.
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
