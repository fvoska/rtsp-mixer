import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../helpers/pcm_level.dart';
import 'pcm_fifo.dart';

/// A real loudness meter for one camera, built from parts this app already
/// ships: a SECOND, silent mpv player that decodes the same RTSP stream and
/// writes 8 kHz mono PCM into a named pipe, and [PcmLevelMeter] reading it.
///
/// Why a second player: the prebuilt FFmpeg inside media_kit has no audio
/// analysis filters on any platform (`--disable-filters` on Android, only
/// `overlay`/`equalizer` re-enabled), and the encoded bitrate of the
/// camera's AAC barely moves with loudness. The only loudness signal that
/// exists in this process is the decoded PCM, and mpv's `ao=pcm` output is
/// the one way to get at it. It cannot be the main player's output — the
/// parent needs to hear the stream — so the tap decodes it a second time.
/// AAC decode at 8 kHz mono is a rounding error on CPU; the extra RTSP
/// session to the console is the real cost, and the NVR serves several
/// viewers per camera routinely.
///
/// Why this never endangers the audio stream (CLAUDE.md's hard rule): the
/// tap is a separate `Player` with no filters and no shared state. If it
/// fails to open, dies, stalls, or the pipe cannot be created, the level
/// meter falls back to the bitrate proxy and the main player is untouched.
/// Every method here catches its own failures and reports them through
/// [failure]; nothing throws to the caller.
class PcmLevelTap {
  PcmLevelTap({
    required this.cameraId,
    required this.cameraName,
    required this.url,
    required this.tune,
  });

  final String cameraId;
  final String cameraName;

  /// The stream URL this tap is metering — the candidate the main player
  /// settled on. A tap for a different URL is stale and is replaced.
  final String url;

  /// Applies the app's RTSP tuning (TCP transport, small cache) to a
  /// freshly created native player. Shared with the main player so both
  /// speak to the console the same way.
  final Future<void> Function(NativePlayer) tune;

  /// How long an open may take before the tap is declared failed.
  static const openTimeout = Duration(seconds: 15);

  final PcmLevelMeter _meter = PcmLevelMeter();
  Player? _player;
  PcmFifo? _fifo;
  StreamSubscription<String>? _errorSub;
  final DateTime startedAt = DateTime.now();
  DateTime? _lastDataAt;
  String? _failure;
  bool _disposed = false;

  /// Non-null once the tap has given up (open failed, mpv error, FIFO
  /// unavailable). The owner disposes it and retries after a cooldown.
  String? get failure => _failure;
  bool get isFailed => _failure != null;

  /// True once at least one PCM byte has come through the pipe.
  bool get hasDelivered => _lastDataAt != null;

  /// Time since PCM last arrived, or since start if none has.
  Duration get sinceData =>
      DateTime.now().difference(_lastDataAt ?? startedAt);

  /// Create the pipe and the player and open the stream. Resolves when the
  /// open call returns (or fails); PCM starts flowing shortly after. Never
  /// throws.
  Future<void> start() async {
    try {
      final dir = await _tempDir();
      final safeId = cameraId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final fifo = PcmFifo.open('${dir.path}/roomtone-tap-$safeId.pcm');
      if (fifo == null) {
        _fail('named pipe unavailable');
        return;
      }
      _fifo = fifo;
      if (_disposed) {
        fifo.close();
        return;
      }

      final player = Player(
        configuration: const PlayerConfiguration(
          // No video surface, no OSD, no controls: this player exists only
          // to decode audio into the pipe.
          vo: 'null',
          osc: false,
          title: 'roomtone-level-tap',
          protocolWhitelist: [
            'udp', 'rtp', 'tcp', 'tls', 'data', 'file',
            'http', 'https', 'crypto', 'rtsp', 'rtsps',
          ],
          bufferSize: 512 * 1024,
        ),
      );
      _player = player;
      _errorSub = player.stream.error.listen((message) {
        appLog('PCMTAP', '$cameraName: tap player error: $message');
        _fail(message);
      });

      final np = player.platform as NativePlayer;
      await tune(np);
      await np.setProperty('vid', 'no');
      // The whole point: decoded audio goes to a raw PCM file writer aimed
      // at our pipe instead of a sound device. media_kit set `ao=opensles`
      // at construction; `ao` is a runtime option and this overrides it
      // before the first audio output is created.
      await np.setProperty('ao', 'pcm');
      await np.setProperty('ao-pcm-file', fifo.path);
      await np.setProperty('ao-pcm-waveheader', 'no');
      // Tiny, fixed format so the meter maths is trivial and the pipe
      // carries 16 KB/s: signed 16-bit, mono, 8 kHz (mpv resamples).
      await np.setProperty('audio-format', 's16');
      await np.setProperty('audio-channels', 'mono');
      await np.setProperty('audio-samplerate', '$kPcmSampleRate');
      // Unity gain so the PCM is the decoder's output, not a mixed volume.
      await np.setProperty('volume', '100');
      await np.setProperty('mute', 'no');

      if (_disposed) return;
      await player.open(Media(url)).timeout(openTimeout);
      appLog('PCMTAP', '$cameraName: tap opened on ${fifo.path}');
    } on TimeoutException {
      _fail('open timed out after ${openTimeout.inSeconds}s');
    } catch (e) {
      _fail('start failed: $e');
    }
  }

  /// Drain the pipe and return this tick's loudness in dBFS, or null when
  /// no full 50 ms window arrived since the last call. Never throws.
  double? sample() {
    final fifo = _fifo;
    if (fifo == null || _disposed) return null;
    try {
      final bytes = fifo.readAvailable();
      if (bytes.isEmpty) return null;
      _lastDataAt = DateTime.now();
      return _meter.measure(bytes);
    } catch (e) {
      appLog('PCMTAP', '$cameraName: sample failed: $e');
      return null;
    }
  }

  /// Tear down in the only safe order: writer first, reader last.
  ///
  /// mpv's PCM writer may be blocked on a full pipe, and closing the read
  /// side underneath a writer would raise SIGPIPE in the process. So the
  /// player is disposed first while the pipe keeps being drained, and the
  /// FIFO is closed only once the player is gone (or a 5 s wait expires,
  /// in which case one descriptor is leaked rather than risked). Never
  /// throws; safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _errorSub?.cancel();
    _errorSub = null;

    final player = _player;
    _player = null;
    var playerGone = player == null;
    if (player != null) {
      final done = player.dispose().then((_) => true).catchError((Object e) {
        appLog('PCMTAP', '$cameraName: tap dispose threw: $e');
        return true;
      });
      var waitedMs = 0;
      while (waitedMs < 5000) {
        final finished = await Future.any<bool>([
          done,
          Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
        ]);
        // Keep the pipe moving so a blocked writer can finish and exit.
        try {
          _fifo?.readAvailable();
        } catch (_) {}
        if (finished) {
          playerGone = true;
          break;
        }
        waitedMs += 100;
      }
    }

    if (playerGone) {
      _fifo?.close();
    } else {
      appLog('PCMTAP',
          '$cameraName: tap player did not stop in 5 s — leaving the pipe open');
    }
    _fifo = null;
  }

  void _fail(String reason) {
    if (_failure != null) return;
    _failure = reason;
    appLog('PCMTAP', '$cameraName: tap failed — $reason');
  }

  static Future<Directory> _tempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }
}
