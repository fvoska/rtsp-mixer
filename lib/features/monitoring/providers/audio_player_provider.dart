import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/foreground_service.dart';
import '../../../core/services/local_notifications.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/models/protect_camera.dart';
import '../../cameras/providers/camera_provider.dart';
import '../helpers/rtsp_url.dart';
import '../helpers/stream_candidates.dart';
import '../helpers/stream_liveness.dart';
import '../models/health_event.dart';
import '../models/player_state.dart';
import '../services/alert_policy.dart';
import '../services/audio_handler.dart';
import '../services/connectivity_listener.dart';
import '../services/drift_watchdog.dart';
import '../services/reconnect_supervisor.dart';
import '../services/zombie_watchdog.dart';
import 'health_events_provider.dart';
import 'session_history_provider.dart';

final audioPlayerProvider =
    AsyncNotifierProvider<AudioPlayerNotifier, MonitoringState>(
        AudioPlayerNotifier.new);

class AudioPlayerNotifier extends AsyncNotifier<MonitoringState> {
  final Map<String, Player> _players = {};
  final Map<String, VideoController> _videoControllers = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _levelPollTimer;
  final Map<String, double> _lastAudioPts = {};
  final Map<String, double> _baselineLevel = {};
  String _lastNotificationText = '';

  /// Serializes lifecycle operations (start / stop / settings-driven restart)
  /// so they can never interleave. Concurrent invocations chain on this
  /// future and run one after the other; without it, a user-clicked Stop
  /// could race against an in-flight settings-driven `_restartIfMonitoring`
  /// and end up with orphaned players still emitting audio after the banner
  /// has been torn down.
  Future<void>? _lifecycleOp;

  /// Set by `stopMonitoringAndCleanup` so a queued or in-progress
  /// settings-driven restart bails out instead of resurrecting streams
  /// after the user asked for a full stop. Cleared by `startMonitoring`.
  bool _stopRequested = false;

  /// Coalesces rapid settings changes (e.g. dragging the buffer slider,
  /// which fires per snap with `divisions: 9`) into one restart at the
  /// final value rather than N back-to-back restart cycles.
  Timer? _settingsRestartDebounce;

  late final ReconnectSupervisor _reconnectSupervisor = ReconnectSupervisor(
    onAttempt: _performReconnectOpen,
    onStatusChange: _applyReconnectStatus,
    onEvent: _recordReconnectEvent,
  );

  // RELY-03: zombie-stream watchdog. D-07 silent fire via supervisor.
  late final ZombieWatchdog _zombieWatchdog = ZombieWatchdog(
    onFire: (cameraId, detail) {
      appLog('ZOMBIE',
          '$cameraId: fire -> requestReconnect (detail=$detail)');
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.zombieDetected,
              cameraId: cameraId,
              cameraName: _findCameraName(cameraId),
              detail: detail,
            ));
      } catch (e) {
        appLog('ZOMBIE', '$cameraId: failed to record zombie event: $e');
      }
      _reconnectSupervisor.requestReconnect(cameraId, cause: 'zombie');
    },
  );

  /// Drift watchdog: silent force-forward when demuxer cache grows past the
  /// configured buffer + tolerance. The only reliable resync on this FFmpeg
  /// build is stop+open — supervisor handles that via 'drift' cause.
  late final DriftWatchdog _driftWatchdog = DriftWatchdog(
    onFire: (cameraId, detail) {
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.driftResync,
              cameraId: cameraId,
              cameraName: _findCameraName(cameraId),
              detail: detail,
            ));
      } catch (e) {
        appLog('DRIFT', '$cameraId: failed to record driftResync event: $e');
      }
      _reconnectSupervisor.requestReconnect(cameraId, cause: 'drift');
    },
  );

  /// Tolerance added on top of the user-configured audio buffer before a drift
  /// resync fires. Keeps small jitter from triggering needless reconnects.
  static const _driftToleranceSeconds = 1.0;

  // RELY-01 D-04: 5-min one-shot per-camera alert policy.
  late final AlertPolicy _alertPolicy = AlertPolicy(
    onFire: (cameraId) {
      final cameraName = _findCameraName(cameraId) ?? cameraId;
      LocalNotificationsManager.fireAlert(
        cameraId: cameraId,
        cameraName: cameraName,
      );
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.alertFired,
              cameraId: cameraId,
              cameraName: cameraName,
            ));
      } catch (e) {
        appLog('NOTIF', 'Failed to record alertFired event: $e');
      }
    },
  );

  // RELY-01 D-03 trigger c: WiFi reconnect listener.
  late final ConnectivityListener _connectivityListener = ConnectivityListener(
    onDropped: _onWifiDropped,
    onReconnected: _onWifiReconnected,
  );

  @override
  Future<MonitoringState> build() async {
    ref.onDispose(() {
      _settingsRestartDebounce?.cancel();
      _settingsRestartDebounce = null;
      try { _reconnectSupervisor.cancelAll(); } catch (_) {}
      try { _zombieWatchdog.resetAll(); } catch (_) {}
      try { _driftWatchdog.resetAll(); } catch (_) {}
      try { _alertPolicy.cancelAll(); } catch (_) {}
      try { _connectivityListener.cancel(); } catch (_) {}
      _levelPollTimer?.cancel();
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _videoControllers.clear();
      for (final p in _players.values) {
        p.dispose();
      }
      _players.clear();
      _lastAudioPts.clear();
      _baselineLevel.clear();
    });

    // Auto-restart streams when RTSP or audio buffer settings change.
    // Debounced so a slider drag doesn't enqueue one restart per snap.
    ref.listen(settingsProvider, (prev, next) {
      if (prev == null) return;
      if (prev.useRtsp != next.useRtsp ||
          prev.audioBufferSeconds != next.audioBufferSeconds) {
        _settingsRestartDebounce?.cancel();
        _settingsRestartDebounce = Timer(
          const Duration(milliseconds: 400),
          () {
            _settingsRestartDebounce = null;
            // ignore: unawaited_futures
            _restartIfMonitoring();
          },
        );
      }
    });

    return const MonitoringState();
  }

  /// Chain [op] onto the lifecycle operation queue so start/stop/restart
  /// never overlap. See [_lifecycleOp].
  Future<void> _runLifecycle(Future<void> Function() op) async {
    final previous = _lifecycleOp;
    final completer = Completer<void>();
    _lifecycleOp = completer.future;
    try {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Don't let a previous op's failure block subsequent ops.
        }
      }
      await op();
    } finally {
      completer.complete();
      if (identical(_lifecycleOp, completer.future)) {
        _lifecycleOp = null;
      }
    }
  }

  Future<void> _restartIfMonitoring() async {
    return _runLifecycle(() async {
      if (_stopRequested) return;
      if (_players.isEmpty) return;
      appLog('AUDIO', 'Stream settings changed — restarting streams');
      await stopMonitoring();
      if (_stopRequested) {
        appLog('AUDIO', 'Restart aborted — user requested stop during restart');
        return;
      }
      await startMonitoring();
    });
  }

  /// Expose players for video preview widgets.
  Player? getPlayer(String cameraId) => _players[cameraId];

  /// Get the VideoController for a camera (created at player init time).
  VideoController? getVideoController(String cameraId) =>
      _videoControllers[cameraId];

  int _cameraIndex(String cameraId) {
    final current = state.value;
    if (current == null) return -1;
    return current.cameras.indexWhere((c) => c.cameraId == cameraId);
  }

  void _updateStreamInfo(String cameraId, StreamInfo Function(StreamInfo) updater) {
    final current = state.value;
    if (current == null) return;
    final idx = _cameraIndex(cameraId);
    if (idx < 0) return;
    final cam = current.cameras[idx];
    state = AsyncData(current.copyWithCamera(idx, cam.copyWith(
      streamInfo: updater(cam.streamInfo),
    )));
  }

  void _listenToPlayer(Player player, String cameraName, String cameraId) {
    _subscriptions.add(
      player.stream.playing.listen((playing) {
        appLog('STREAM', '$cameraName playing=$playing');
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((completed) {
        appLog('STREAM', '$cameraName completed=$completed');
        if (completed) {
          try {
            ref.read(healthEventsProvider.notifier).record(HealthEvent(
                  timestamp: DateTime.now(),
                  type: HealthEventType.streamError,
                  cameraId: cameraId,
                  cameraName: cameraName,
                  detail: 'stream completed (RTSP drop)',
                ));
          } catch (e) {
            appLog('HEALTH', 'Failed to record completed event: $e');
          }
          _reconnectSupervisor.requestReconnect(cameraId,
              cause: 'player_completed');
        }
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((error) {
        appLog('STREAM', '$cameraName error=$error');
        try {
          final msg = error.toString();
          // UI-SPEC §Event log row copy contract: streamError detail truncated
          // to 80 chars with ellipsis so the health summary row stays legible.
          final detail = msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
          ref.read(healthEventsProvider.notifier).record(HealthEvent(
                timestamp: DateTime.now(),
                type: HealthEventType.streamError,
                cameraId: cameraId,
                cameraName: cameraName,
                detail: detail,
              ));
        } catch (e) {
          appLog('HEALTH', 'Failed to record streamError: $e');
        }
        _reconnectSupervisor.requestReconnect(cameraId, cause: 'player_error');
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((buffering) {
        appLog('STREAM', '$cameraName buffering=$buffering');
        // RELY-03: feed watchdog. buffering=false resets the stuck-buffering counter;
        // buffering=true is a no-op — tick() accumulates.
        try {
          if (!buffering) {
            _zombieWatchdog.recordBufferingFalse(cameraId);
          }
        } catch (e) {
          appLog('ZOMBIE', 'buffering listener error (non-fatal): $e');
        }
        // Update status based on buffering state.
        final current = state.value;
        if (current == null) return;
        final idx = _cameraIndex(cameraId);
        if (idx < 0) return;
        final cam = current.cameras[idx];
        if (buffering && cam.connectionStatus == CameraConnectionStatus.playing) {
          state = AsyncData(current.copyWithCamera(idx,
            cam.copyWith(connectionStatus: CameraConnectionStatus.connecting)));
          // D-04: outage clock starts the moment we leave `playing`.
          _alertPolicy.armIfAbsent(cameraId);
        } else if (!buffering && cam.connectionStatus == CameraConnectionStatus.connecting) {
          state = AsyncData(current.copyWithCamera(idx,
            cam.copyWith(connectionStatus: CameraConnectionStatus.playing)));
          // D-04: recovered — cancel pending alert + dismiss any fired one.
          _alertPolicy.clear(cameraId);
          LocalNotificationsManager.cancelAlert(cameraId);
        }
      }),
    );
    _subscriptions.add(
      player.stream.audioParams.listen((params) {
        appLog('STREAM', '$cameraName audioParams=$params');
        _updateStreamInfo(cameraId, (info) => info.merge(
          sampleRate: params.sampleRate,
          channels: params.hrChannels,
        ));
        // RELY-03: feed watchdog — any audioParams event resets the counter.
        try {
          _zombieWatchdog.recordAudioParams(cameraId);
        } catch (e) {
          appLog('ZOMBIE', 'audioParams listener error (non-fatal): $e');
        }
      }),
    );
    _subscriptions.add(
      player.stream.track.listen((track) {
        appLog('STREAM', '$cameraName track: audio=${track.audio} video=${track.video}');
        final a = track.audio;
        final v = track.video;
        _updateStreamInfo(cameraId, (info) => info.merge(
          audioCodec: a.codec,
          audioBitrate: a.bitrate,
          videoCodec: v.codec,
          videoBitrate: v.bitrate,
          width: v.w,
          height: v.h,
          fps: v.fps,
        ));
      }),
    );
    _subscriptions.add(
      player.stream.log.listen((log) {
        // Suppress noisy HEVC/H264 decoder errors from mid-stream joins.
        if (log.prefix.contains('ffmpeg/video') &&
            (log.text.contains('PPS id out of range') ||
             log.text.contains('SPS id out of range') ||
             log.text.contains('non-existing PPS') ||
             log.text.contains('decode_slice_header') ||
             log.text.contains('no frame'))) {
          return;
        }
        // Windows: VideoController is created eagerly so a later
        // user toggle to video=auto works without recreating the player,
        // but with vid=no the EGL surface init fails harmlessly. Filter the
        // dxva2-egl "Failed to create EGL surface" line so it doesn't spam
        // the log every reconnect.
        if (log.prefix.contains('libmpv_render/dxva2-egl') &&
            log.text.contains('Failed to create EGL surface')) {
          return;
        }
        appLog('MPV', '$cameraName [${log.prefix}] ${log.level}: ${log.text}');
      }),
    );
  }

  Player _createPlayer() => Player(
        configuration: const PlayerConfiguration(
          protocolWhitelist: [
            'udp', 'rtp', 'tcp', 'tls', 'data', 'file',
            'http', 'https', 'crypto', 'rtsp', 'rtsps',
          ],
          bufferSize: 2 * 1024 * 1024,
        ),
      );

  /// Per-candidate open timeout for initial opens and quality switches.
  /// player.open() has no timeout of its own and mpv's network-timeout is
  /// broken for RTSP, so an unreachable local address would otherwise hang
  /// the whole start sequence.
  static const _candidateOpenTimeout = Duration(seconds: 12);

  /// Per-candidate open timeout during supervisor-driven reconnects (mirrors
  /// the pre-existing 15s reconnect timeout).
  static const _reconnectOpenTimeout = Duration(seconds: 15);

  /// Grace window after a successful open() during which we wait for
  /// evidence the stream is actually alive. media_kit's open() resolves once
  /// the media is queued — BEFORE the RTSP connection is established — so a
  /// fast failure (e.g. "connection refused") surfaces on the error stream a
  /// moment AFTER open() reports success. Without this window a dead
  /// candidate would be declared the winner on every cycle and later
  /// candidates would never get a turn.
  ///
  /// A timeout of this window no longer implies alive: it triggers the
  /// mpv `track-list/count` fallback check and, when that reads 0, one
  /// [_openConfirmExtendedGrace] wait before the candidate is disqualified.
  static const _openConfirmGrace = Duration(seconds: 4);

  /// Second-stage grace window entered only when [_openConfirmGrace]
  /// elapsed with no signal AND mpv's `track-list/count` read 0 (no RTSP
  /// session established yet). Gives slow VPN links (e.g. Tailscale) extra
  /// time to produce a real track before a silent candidate is disqualified.
  static const _openConfirmExtendedGrace = Duration(seconds: 6);

  /// Sentinel returned by the confirmation completer's timeout so an
  /// elapsed grace window is distinguishable from a real completion
  /// (null = alive, any other string = an error-stream event). Never reuse
  /// null for timeout — null means alive.
  static const _confirmTimedOut = '__gsd_confirm_timed_out__';

  /// Cameras with an open/candidate loop currently running. Guards against
  /// a supervisor retry timer firing mid-attempt and running a second
  /// stop+reopen concurrently against the same player.
  final Set<String> _openingCameras = {};

  /// Read and parse mpv's `track-list/count` as the liveness fallback.
  /// mpv's track-list contains only real demuxer tracks (no auto/no pseudo
  /// entries), so 0 means no RTSP session was established. Returns null
  /// when the property read throws or the value doesn't parse — the
  /// "inconclusive" signal the caller treats as assume-alive (CLAUDE.md
  /// defensive rule). Never throws.
  Future<int?> _readLivenessTrackCount(
      Player player, String cameraName) async {
    try {
      final raw = await (player.platform as NativePlayer)
          .getProperty('track-list/count');
      final count = parseTrackCount(raw);
      if (count == null) {
        appLog('AUDIO',
            '$cameraName: liveness track-list fallback inconclusive '
            '(raw="$raw") — assuming alive');
      }
      return count;
    } catch (e) {
      appLog('AUDIO',
          '$cameraName: liveness track-list fallback read failed '
          '(assuming alive): $e');
      return null;
    }
  }

  /// Wait for POSITIVE evidence that the stream just opened on [player] is
  /// actually alive:
  ///
  ///  - audioParams with sampleRate > 0 (audio decoder configured itself
  ///    from real stream data), or
  ///  - a real audio OR video track appearing on `player.stream.tracks`
  ///    (see [hasRealTrack] — video-only keeps mic-disabled cameras
  ///    working), or
  ///  - mpv's `track-list/count` reading > 0.
  ///
  /// An error event within either grace window disqualifies the candidate
  /// immediately (throws). Silence through [_openConfirmGrace] AND
  /// [_openConfirmExtendedGrace] with `track-list/count` parsing to 0 both
  /// times ALSO disqualifies it — this is the fix for the Tailscale
  /// exit-node blackhole where SYNs to the console's LAN IP are silently
  /// dropped (no RST/ICMP): FFmpeg's TCP connect hangs, no error event ever
  /// arrives, and the dead `local` candidate used to be falsely declared
  /// the winner so `_openFirstCandidate` never tried the working remote
  /// (ts.net) candidate.
  ///
  /// Defensive: failures of the confirmation plumbing itself (tracks
  /// subscription error, getProperty throwing, unparseable track count)
  /// must never fail a good open — they degrade to "assume alive". The
  /// deliberate no-signs-of-life disqualification is set as [failure] (not
  /// thrown inside the try) so the defensive catch cannot swallow it.
  Future<void> _confirmStreamAlive(
      Player player, String cameraName, String label) async {
    final subs = <StreamSubscription<dynamic>>[];
    String? failure;
    try {
      final completer = Completer<String?>();
      subs.add(player.stream.error.listen((e) {
        if (!completer.isCompleted) completer.complete(e.toString());
      }));
      subs.add(player.stream.audioParams.listen((p) {
        if ((p.sampleRate ?? 0) > 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }));
      subs.add(player.stream.tracks.listen((tracks) {
        // A real audio OR video track proves the RTSP session was
        // established (video-only = mic-disabled camera, still alive).
        if (hasRealTrack(tracks) && !completer.isCompleted) {
          completer.complete(null);
        }
      }));

      final first = await completer.future
          .timeout(_openConfirmGrace, onTimeout: () => _confirmTimedOut);
      if (first == _confirmTimedOut) {
        // First window elapsed in silence. Belt-and-braces: ask mpv how
        // many real demuxer tracks exist. Inconclusive (null) or > 0 →
        // assume alive; exactly 0 → no session yet, extend the wait.
        final count = await _readLivenessTrackCount(player, cameraName);
        if (count == 0) {
          // Listeners are still attached — a late audioParams/tracks event
          // completes alive, an error event completes dead.
          final second = await completer.future.timeout(
              _openConfirmExtendedGrace,
              onTimeout: () => _confirmTimedOut);
          if (second == _confirmTimedOut) {
            final recount = await _readLivenessTrackCount(player, cameraName);
            if (recount == 0) {
              failure =
                  '$label candidate showed no signs of life (no tracks) after open';
            }
            // recount null (inconclusive) or > 0 → assume alive.
          } else if (second != null) {
            failure = '$label candidate errored right after open: $second';
          }
        }
      } else if (first != null) {
        failure = '$label candidate errored right after open: $first';
      }
    } catch (e) {
      appLog('AUDIO',
          '$cameraName: liveness check error (assuming alive): $e');
      failure = null;
    } finally {
      for (final s in subs) {
        try {
          unawaited(s.cancel());
        } catch (_) {}
      }
    }
    if (failure != null) {
      throw StateError(failure);
    }
  }

  /// Build the ordered [local, remote, override] candidate list for
  /// [quality] from a camera's quality maps. Local always comes first so
  /// every (re)connect cycle re-prefers the LAN stream when it's reachable.
  /// Falls back to the camera's activeStreamUrl when the quality maps are
  /// empty (defensive — should not happen in practice). Never throws.
  List<StreamCandidate> _candidatesFor(CameraAudioState cam, String? quality) =>
      orderedStreamCandidates(
        local: cam.availableQualities,
        remote: cam.remoteQualities,
        cameraRemote: cam.overrideQualities,
        quality: quality,
        activeUrl: cam.activeStreamUrl,
      );

  /// Open [url] on [player] with a hard [timeout] so a dead address can't
  /// hang the caller.
  Future<void> _openWithTimeout(
      Player player, String url, Duration timeout) async {
    await player.open(Media(url)).timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException(
            'player.open($url) exceeded ${timeout.inSeconds}s', timeout);
      },
    );
  }

  /// Try [candidates] in order and return the first one that opens AND shows
  /// signs of life within the confirmation grace window (see
  /// [_confirmStreamAlive] — open() alone resolving is not proof the RTSP
  /// connection succeeded).
  ///
  /// Every candidate failure is caught and logged individually — nothing is
  /// rethrown mid-loop, so a dead local address can never kill the attempt at
  /// the remote address (CLAUDE.md defensive-error-handling rule). Throws the
  /// last failure only when ALL candidates fail.
  Future<StreamCandidate> _openFirstCandidate(
    Player player,
    String cameraName,
    List<StreamCandidate> candidates,
    Duration timeout,
  ) async {
    Object? lastError;
    for (final cand in candidates) {
      try {
        appLog('AUDIO',
            '$cameraName: opening ${cand.label} candidate: ${cand.url}');
        await _openWithTimeout(player, cand.url, timeout);
        await _confirmStreamAlive(player, cameraName, cand.label);
        appLog('AUDIO', '$cameraName: connected via ${cand.label} candidate');
        return cand;
      } catch (e) {
        lastError = e;
        appLog('AUDIO', '$cameraName: ${cand.label} candidate failed: $e');
      }
    }
    throw lastError ?? StateError('No stream candidates for $cameraName');
  }

  /// Connect a single camera and return its resolved [CameraAudioState].
  ///
  /// Single source of the per-camera connect logic shared by
  /// [startMonitoring] (looped over the whole selection) and
  /// [addCameraToSession] (one camera into a live mix). Builds the
  /// local/remote/override candidate maps, registers the [Player],
  /// [VideoController] and stream listeners, runs the ordered-candidate open
  /// and — on TOTAL failure — leaves the camera in `error` with supervisor +
  /// alert handoff. Never throws: a failed open is captured in the returned
  /// state so it can never tear down an already-running stream (CLAUDE.md
  /// defensive-error rule).
  Future<CameraAudioState> _connectCamera(
    ProtectCamera camera, {
    required bool videoPreview,
  }) async {
    final settings = ref.read(settingsProvider);
    final cameraName = camera.name ?? 'Camera';
    appLog('AUDIO', 'Connecting to $cameraName (${camera.id})');

    // Manual cameras use their URL verbatim — the RTSPS→RTSP port/scheme
    // rewrite in resolveStreamUrl is Unifi-specific and would corrupt an
    // arbitrary user-entered stream URL.
    String resolveFor(String raw) => camera.isManual
        ? raw
        : resolveStreamUrl(raw, useRtsp: settings.useRtsp);

    // The integration API embeds the console's own LAN IP in the RTSPS
    // URLs it returns, regardless of which address the API was reached
    // through. When the console is configured via a different address
    // (e.g. a Tailscale hostname), that embedded IP is unreachable — so
    // point the local candidates at the configured console address.
    // Manual cameras keep their user-entered URL verbatim. Defensive:
    // rewriteStreamUrlHosts never throws and degrades to the API URLs.
    var localUrls = camera.rtspsStreamUrls;
    if (!camera.isManual) {
      localUrls = rewriteStreamUrlHosts(
          localUrls, ref.read(authNotifierProvider).value?.host);
    }

    final quality = camera.defaultQuality;
    final rtspsUrl = quality != null ? localUrls[quality] : null;
    final url = rtspsUrl != null ? resolveFor(rtspsUrl) : null;

    // Remote (VPN/Tailscale) candidates, parallel to availableQualities.
    // Two tiers, tried after the local candidate:
    //  - remoteQualities: the stream URLs re-pointed at the globally
    //    configured remote host — Unifi AND manual cameras. Covers
    //    NVR-style setups where all streams are served from one host
    //    (still run through resolveFor so Unifi useRtsp handling matches
    //    the local candidate; resolveFor is a no-op for manual cameras).
    //  - overrideQualities: the camera's own remote URL, verbatim (manual
    //    cameras only), for cameras whose remote address doesn't follow
    //    the global host swap.
    // Defensive: any failure here degrades to "no remote fallback" — it
    // must never prevent the local stream from starting.
    var remoteQualities = const <String, String>{};
    var overrideQualities = const <String, String>{};
    try {
      final remoteHost = ref.read(authNotifierProvider).value?.remoteHost;
      if (remoteHost != null && remoteHost.isNotEmpty) {
        remoteQualities = camera.rtspsStreamUrls.map(
          (k, v) => MapEntry(k, resolveFor(replaceUrlHost(v, remoteHost))),
        );
      }
      if (camera.isManual) {
        final remoteUrl = camera.remoteUrl;
        if (remoteUrl != null && remoteUrl.isNotEmpty) {
          overrideQualities = {
            for (final k in camera.rtspsStreamUrls.keys) k: remoteUrl,
          };
        }
      }
    } catch (e) {
      appLog('AUDIO',
          '$cameraName: building remote candidates failed (continuing without): $e');
    }

    var camState = CameraAudioState(
      cameraId: camera.id,
      cameraName: cameraName,
      connectionStatus: CameraConnectionStatus.connecting,
      availableQualities: localUrls.map(
        (k, v) => MapEntry(k, resolveFor(v)),
      ),
      remoteQualities: remoteQualities,
      overrideQualities: overrideQualities,
      activeQuality: quality,
      activeStreamUrl: url,
      mac: camera.mac,
      modelKey: camera.modelKey,
      micVolume: camera.micVolume,
      isManual: camera.isManual,
    );

    if (!camera.isMicEnabled) {
      camState = camState.copyWith(
        errorMessage:
            'Microphone is disabled on this camera -- enable it in Protect camera settings',
      );
      appLog('AUDIO', 'Warning: mic disabled on $cameraName');
    }

    try {
      if (url == null || url.isEmpty) {
        throw StateError('No stream URL for $cameraName — enable RTSP in Protect camera settings');
      }

      final player = _createPlayer();
      final nativePlayer = player.platform as NativePlayer;
      // Apply tuning properties. Idempotent helper — reused on every reconnect
      // to hedge against mpv property resets across open() (RESEARCH §Pitfall 3).
      await _applyPlaybackTuning(nativePlayer);

      // Create VideoController BEFORE open so the render context exists.
      // This is required for vid=auto to work later.
      _videoControllers[camera.id] = VideoController(player);

      _players[camera.id] = player;
      _listenToPlayer(player, cameraName, camera.id);

      // Ordered candidate list: local first, then global-remote rewrite,
      // then the camera's own remote URL. First success wins; each
      // candidate failure is caught + logged inside _openFirstCandidate,
      // never rethrown mid-loop. The error state below is reached only
      // when ALL candidates fail.
      final candidates = _candidatesFor(camState, quality);
      appLog('AUDIO',
          'Opening stream ($quality, ${candidates.length} candidate(s)): $url');
      _openingCameras.add(camera.id);
      StreamCandidate winner;
      try {
        winner = await _openFirstCandidate(
            player, cameraName, candidates, _candidateOpenTimeout);
      } finally {
        _openingCameras.remove(camera.id);
      }
      // Errors from losing candidates already kicked the supervisor —
      // drop any pending retry now that a candidate is confirmed alive.
      try {
        _reconnectSupervisor.cancel(camera.id);
      } catch (_) {}

      // Disable video after open if not previewing (audio-only mode).
      if (!videoPreview) {
        await nativePlayer.setProperty('vid', 'no');
      }

      camState = camState.copyWith(
        connectionStatus: CameraConnectionStatus.playing,
        activeStreamUrl: winner.url,
      );
      appLog('AUDIO', '$cameraName is now playing');

      // D-15: record per-camera streamStarted event for health summary.
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.streamStarted,
              cameraId: camera.id,
              cameraName: cameraName,
            ));
      } catch (e) {
        appLog('HEALTH', 'Failed to record streamStarted: $e');
      }
    } catch (e) {
      appLog('AUDIO', 'Error connecting to $cameraName: $e');
      camState = camState.copyWith(
        connectionStatus: CameraConnectionStatus.error,
        errorMessage: e.toString(),
      );
      // WR-01 fix: a failed initial open leaves the camera in `error` with
      // no supervisor or alert ownership. Hand off to both so D-04's 5-min
      // alert can fire and the supervisor's retry loop takes over.
      try {
        _alertPolicy.armIfAbsent(camera.id);
        // ignore: unawaited_futures
        _reconnectSupervisor.requestReconnect(
          camera.id,
          cause: 'initial_open_failed',
        );
      } catch (handoffErr) {
        appLog('AUDIO',
            'Handoff to supervisor/alert after initial-open failure threw: $handoffErr');
      }
    }

    return camState;
  }

  Future<void> startMonitoring({bool videoPreview = false}) async {
    // Any new start clears the stop flag so a subsequent settings-driven
    // restart isn't permanently suppressed by an earlier Stop.
    _stopRequested = false;
    final cameraState = ref.read(cameraNotifierProvider).value;
    final selectedCameras = cameraState?.selectedCameras ?? [];
    if (selectedCameras.isEmpty) {
      appLog('AUDIO', 'Cannot start monitoring: no cameras selected');
      return;
    }

    // Idempotency guard (260514-siv): if MonitoringScreen is re-entered via
    // ShellRoute while a session is already in flight AND players are still
    // connecting/connected, return without clearing events or restarting streams.
    // Note: enum value is `playing` (not `connected`) — see CameraConnectionStatus.
    try {
      final existing = ref.read(sessionHistoryProvider).value?.current;
      final running = state.value?.cameras.any((c) =>
              c.connectionStatus == CameraConnectionStatus.connecting ||
              c.connectionStatus == CameraConnectionStatus.playing ||
              c.connectionStatus == CameraConnectionStatus.reconnecting) ??
          false;
      if (existing != null && running) {
        appLog('AUDIO',
            'startMonitoring called while session already in progress — noop');
        return;
      }
    } catch (e) {
      appLog('SESSION', 'startMonitoring idempotency check failed: $e');
      // fall through — better to restart than to be stuck
    }

    state = const AsyncLoading();
    final settings = ref.read(settingsProvider);
    appLog('AUDIO', 'Starting monitoring for ${selectedCameras.length} cameras (video=$videoPreview, rtsp=${settings.useRtsp}, buffer=${settings.audioBufferSeconds}s)');

    // 260514-siv: begin a new persisted session BEFORE recording the first
    // event, so the monitoringStarted event lands in the new session rather
    // than being dropped (recordEvent is a no-op when current == null).
    try {
      await ref.read(sessionHistoryProvider.notifier).beginSession(
            selectedCameras
                .map((c) => (id: c.id, name: c.name ?? 'Camera'))
                .toList(),
          );
    } catch (e) {
      appLog('SESSION', 'beginSession from startMonitoring failed: $e');
    }

    // D-13: session boundary — clear previous session's health events and
    // record monitoringStarted before opening streams.
    try {
      ref.read(healthEventsProvider.notifier).clear();
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.monitoringStarted,
            detail: '${selectedCameras.length} cameras',
          ));
    } catch (e) {
      appLog('HEALTH', 'Failed to clear/record monitoringStarted: $e');
    }

    final cameraStates = <CameraAudioState>[];

    for (final camera in selectedCameras) {
      cameraStates.add(await _connectCamera(camera, videoPreview: videoPreview));
    }

    // Restore saved volume/mute state
    final savedMix = await _loadMixState();
    for (int i = 0; i < cameraStates.length; i++) {
      final cam = cameraStates[i];
      final mix = savedMix[cam.cameraId];
      if (mix != null) {
        final volume = (mix['volume'] as num?)?.toDouble() ?? 100.0;
        final muted = mix['muted'] as bool? ?? false;
        cameraStates[i] = cam.copyWith(
          volume: volume,
          preMuteVolume: volume,
          isMuted: muted,
        );
        final player = _players[cam.cameraId];
        if (player != null) {
          player.setVolume(muted ? 0.0 : volume);
        }
        appLog('AUDIO', '${cam.cameraName} restored vol=${volume.toStringAsFixed(0)} muted=$muted');
      }
    }

    state = AsyncData(MonitoringState(cameras: cameraStates));
    appLog('AUDIO', 'Monitoring started for ${cameraStates.length} cameras');

    // Update foreground notification with camera status
    try {
      final statusParts = cameraStates.map((c) {
        final status = c.connectionStatus == CameraConnectionStatus.playing
            ? '' : ' (${c.connectionStatus.name})';
        return '${c.cameraName}$status';
      }).toList();
      final text = 'Monitoring: ${statusParts.join(", ")}';
      _lastNotificationText = text;
      await ForegroundServiceManager.updateNotification(text: text);
    } catch (e) {
      appLog('FGS', 'Failed to update notification: $e');
    }

    // Start polling audio-pts to detect silence / estimate activity.
    _startLevelPolling();

    // RELY-01 D-03 trigger c: subscribe to connectivity events for WiFi reconnect.
    try {
      _connectivityListener.start();
    } catch (e) {
      appLog('CONN', 'Failed to start connectivity listener: $e');
    }
  }

  static const _pollInterval = Duration(milliseconds: 500);

  void _startLevelPolling() {
    _levelPollTimer?.cancel();
    _levelPollTimer = Timer.periodic(_pollInterval, (_) => _pollAudioLevels());
  }

  Future<void> _pollAudioLevels() async {
    final current = state.value;
    if (current == null || current.cameras.isEmpty) return;

    var changed = false;
    var updated = current;

    for (int i = 0; i < updated.cameras.length; i++) {
      final cam = updated.cameras[i];
      if (!cam.isLive) continue;

      final player = _players[cam.cameraId];
      if (player == null) continue;

      try {
        final np = player.platform as NativePlayer;

        // Audio PTS: tracks whether audio data is flowing per-player.
        // Not a loudness measurement, but reliably detects silence vs activity.
        final ptsStr = await np.getProperty('audio-pts');
        final pts = double.tryParse(ptsStr) ?? 0.0;
        final lastPts = _lastAudioPts[cam.cameraId] ?? 0.0;
        final ptsDelta = pts - lastPts;
        _lastAudioPts[cam.cameraId] = pts;

        final flowing = ptsDelta > 0.01;
        // RELY-03: feed watchdog with PTS-advance positive signal.
        try {
          if (flowing) {
            _zombieWatchdog.recordPtsAdvance(cam.cameraId);
          }
        } catch (e) {
          appLog('ZOMBIE', 'pts feed error (non-fatal): $e');
        }
        // Normalize: typical delta at 500ms poll is ~0.5s.
        final level = flowing ? (ptsDelta / 0.6).clamp(0.2, 1.0) : 0.0;

        // Activity: deviation from per-camera baseline.
        final prevBaseline = _baselineLevel[cam.cameraId] ?? level;
        final baseline = prevBaseline * 0.95 + level * 0.05;
        _baselineLevel[cam.cameraId] = baseline;
        final rawActivity = (level - baseline).clamp(0.0, 1.0);
        final prevActivity = cam.audioActivity;
        final activity = rawActivity > prevActivity
            ? rawActivity
            : prevActivity * 0.7;

        final newSilence = !flowing
            ? cam.silenceDuration + _pollInterval.inMilliseconds / 1000.0
            : 0.0;

        // Poll mpv properties for stream metadata (track events are sparse for RTSP).
        final audioCodec = await _tryGetProperty(np, 'audio-codec-name');
        final videoCodec = await _tryGetProperty(np, 'video-codec-name');
        final audioFormat = await _tryGetProperty(np, 'audio-params/format');
        final audioSampleRate = int.tryParse(await _tryGetProperty(np, 'audio-params/samplerate') ?? '');
        final audioChannelCount = int.tryParse(await _tryGetProperty(np, 'audio-params/channel-count') ?? '');
        final audioChannels = await _tryGetProperty(np, 'audio-params/hr-channels');
        final width = int.tryParse(await _tryGetProperty(np, 'video-params/w') ?? '');
        final height = int.tryParse(await _tryGetProperty(np, 'video-params/h') ?? '');
        final fps = double.tryParse(await _tryGetProperty(np, 'container-fps') ?? '');
        final audioBitrate = double.tryParse(await _tryGetProperty(np, 'audio-bitrate') ?? '');
        // RELY-03: feed watchdog with bitrate>0 positive signal.
        try {
          if (audioBitrate != null && audioBitrate > 0) {
            _zombieWatchdog.recordBitrateNonZero(cam.cameraId);
          }
        } catch (e) {
          appLog('ZOMBIE', 'bitrate feed error (non-fatal): $e');
        }
        final videoBitrate = double.tryParse(await _tryGetProperty(np, 'video-bitrate') ?? '');

        final newInfo = cam.streamInfo.merge(
          audioCodec: audioCodec,
          videoCodec: videoCodec,
          sampleRate: audioSampleRate,
          channels: audioChannels ?? (audioChannelCount != null ? '${audioChannelCount}ch' : null),
          audioBitrate: audioBitrate?.round(),
          videoBitrate: videoBitrate?.round(),
          width: width,
          height: height,
          fps: fps,
          audioFormat: audioFormat,
        );

        final infoChanged = newInfo.audioCodec != cam.streamInfo.audioCodec ||
            newInfo.videoCodec != cam.streamInfo.videoCodec ||
            newInfo.sampleRate != cam.streamInfo.sampleRate ||
            newInfo.width != cam.streamInfo.width ||
            newInfo.audioBitrate != cam.streamInfo.audioBitrate ||
            newInfo.videoBitrate != cam.streamInfo.videoBitrate;

        if ((level - cam.audioLevel).abs() > 0.05 ||
            (activity - cam.audioActivity).abs() > 0.03 ||
            (newSilence - cam.silenceDuration).abs() > 0.5 ||
            infoChanged) {
          updated = updated.copyWithCamera(
            i,
            cam.copyWith(
              audioLevel: level,
              audioActivity: activity,
              silenceDuration: newSilence,
              streamInfo: newInfo,
            ),
          );
          changed = true;
        }

        // RELY-03: tick the watchdog once per camera per pass. Must run
        // AFTER the positive-signal feeders above so signal-age accounting
        // reflects this poll's signals.
        try {
          _zombieWatchdog.tick(cam.cameraId, _pollInterval.inMilliseconds);
        } catch (e) {
          appLog('ZOMBIE', 'tick error (non-fatal): $e');
        }

        // Drift detection: feed the watchdog the demuxer's forward cache.
        // demuxer-cache-duration is the seconds of decoded+demuxed audio
        // sitting ahead of the playhead. If it exceeds the user buffer plus
        // tolerance for the confirm window, the watchdog fires a stop+open.
        try {
          final cacheStr = await _tryGetProperty(np, 'demuxer-cache-duration');
          final cache = double.tryParse(cacheStr ?? '');
          if (cache != null && cache.isFinite && cache >= 0) {
            final bufferSeconds =
                ref.read(settingsProvider).audioBufferSeconds;
            _driftWatchdog.recordCacheDuration(
              cameraId: cam.cameraId,
              cacheSeconds: cache,
              thresholdSeconds: bufferSeconds + _driftToleranceSeconds,
              pollIntervalMs: _pollInterval.inMilliseconds,
            );
          }
        } catch (e) {
          appLog('DRIFT', 'cache read error (non-fatal): $e');
        }
      } catch (_) {
        // Player may be disposed during poll.
      }
    }

    if (changed) {
      state = AsyncData(updated);

      // Update notification if status text changed
      try {
        final statusParts = updated.cameras.map((c) {
          final status = c.connectionStatus == CameraConnectionStatus.playing
              ? '' : ' (${c.connectionStatus.name})';
          return '${c.cameraName}$status';
        }).toList();
        final newText = 'Monitoring: ${statusParts.join(", ")}';
        if (newText != _lastNotificationText) {
          _lastNotificationText = newText;
          ForegroundServiceManager.updateNotification(text: newText);
        }
      } catch (_) {}
    }
  }

  Future<String?> _tryGetProperty(NativePlayer np, String name) async {
    try {
      final v = await np.getProperty(name);
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Apply all mpv tuning properties. Idempotent; safe to call before every
  /// open() — hedges against Pitfall 3 (RESEARCH §Pitfall 3) where mpv
  /// properties may reset across player.open() on some builds.
  Future<void> _applyPlaybackTuning(NativePlayer nativePlayer) async {
    final settings = ref.read(settingsProvider);
    // Use TCP transport for reliable delivery over LAN.
    await nativePlayer.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');
    // Small demuxer cache absorbs network jitter without adding much latency.
    // The old profile=low-latency + cache=no combination set audio-buffer=0
    // which caused audible crackling from audio output underruns.
    await nativePlayer.setProperty('cache', 'yes');
    await nativePlayer.setProperty('demuxer-max-bytes', '512KiB');
    // Cap backlog at 0 so the demuxer drops already-played audio rather than
    // accumulating an unbounded history. Without this, brief decoder stalls
    // overnight let the live edge drift by minutes (audio plays old samples
    // forever once jitter pushes packets into the back-buffer).
    await nativePlayer.setProperty('demuxer-max-back-bytes', '0');
    // Read-ahead matches the playback buffer goal — 1s is enough to absorb
    // LAN jitter without giving room for noticeable lag.
    await nativePlayer.setProperty('demuxer-readahead-secs', '1');
    await nativePlayer.setProperty('cache-pause', 'no');
    // Keep audio output buffer small but nonzero for smooth playback.
    await nativePlayer.setProperty(
        'audio-buffer', settings.audioBufferSeconds.toString());
  }

  /// Supervisor's onAttempt: actually reconnect the media_kit Player.
  /// Reuses the same Player instance (RESEARCH §Section 2 Pattern 1).
  /// Wraps open() in a 15s timeout — mpv network-timeout is broken for RTSP.
  Future<void> _performReconnectOpen(String cameraId) async {
    final player = _players[cameraId];
    if (player == null) {
      throw StateError('No player for $cameraId');
    }
    final current = state.value;
    final idx = _cameraIndex(cameraId);
    if (current == null || idx < 0) {
      throw StateError('No camera state for $cameraId');
    }
    final cam = current.cameras[idx];
    // Rebuild the ordered [local, remote] candidate list for the current
    // quality instead of blindly retrying activeStreamUrl. Local comes first
    // so recovery re-prefers the LAN stream when the parent is back home,
    // even if the session had fallen back to the remote URL.
    final candidates = _candidatesFor(cam, cam.activeQuality);
    if (candidates.isEmpty) {
      throw StateError('No active stream URL for $cameraId');
    }

    // A retry timer can fire while a previous (long) candidate loop is still
    // running — bail out and let the supervisor reschedule with backoff
    // instead of running two stop+reopen cycles against the same player.
    if (!_openingCameras.add(cameraId)) {
      throw StateError('open already in progress for $cameraId');
    }
    try {
      await _performReconnectOpenLocked(cameraId, player, candidates);
    } finally {
      _openingCameras.remove(cameraId);
    }
  }

  Future<void> _performReconnectOpenLocked(
    String cameraId,
    Player player,
    List<StreamCandidate> candidates,
  ) async {
    final nativePlayer = player.platform as NativePlayer;
    // Capture the user's current video preference BEFORE stop() so reconnect
    // doesn't silently disable a preview the user had toggled on.
    // Pre-Phase-4 this method unconditionally forced vid=no on every reopen,
    // which was harmless when reconnects were rare but turns the preview into
    // a black screen now that the supervisor + watchdog reconnect aggressively.
    String? priorVid;
    try {
      priorVid = await _tryGetProperty(nativePlayer, 'vid');
    } catch (e) {
      appLog('RECONNECT', '$cameraId: vid read failed (continuing): $e');
    }

    appLog('RECONNECT',
        '$cameraId: stop + reopen (${candidates.length} candidate(s), priorVid=$priorVid)');
    try {
      await player.stop();
    } catch (e) {
      appLog('RECONNECT', '$cameraId: stop() failed (continuing): $e');
    }
    await Future.delayed(const Duration(milliseconds: 200));

    // Re-apply tuning properties — hedge against Pitfall 3 (property reset).
    try {
      await _applyPlaybackTuning(nativePlayer);
    } catch (e) {
      appLog('RECONNECT', '$cameraId: tuning re-apply failed (continuing): $e');
    }

    // Try each candidate with a per-candidate 15s open timeout — mpv
    // network-timeout is broken for RTSP. Throws only when ALL candidates
    // fail, so the ReconnectSupervisor reschedules exactly as before.
    final winner = await _openFirstCandidate(
        player, cameraId, candidates, _reconnectOpenTimeout);

    // Record which URL actually connected so the UI and the next reconnect
    // cycle see the truth. Defensive: a state hiccup here must not fail an
    // otherwise-successful reconnect.
    try {
      final afterState = state.value;
      final afterIdx = _cameraIndex(cameraId);
      if (afterState != null && afterIdx >= 0) {
        state = AsyncData(afterState.copyWithCamera(
          afterIdx,
          afterState.cameras[afterIdx].copyWith(activeStreamUrl: winner.url),
        ));
      }
    } catch (e) {
      appLog('RECONNECT',
          '$cameraId: activeStreamUrl update failed (non-fatal): $e');
    }

    // Restore the video track selection. If the user had vid=no (audio-only,
    // the default), keep it off. If they had vid=auto (preview on), put it
    // back so the reconnect doesn't trash their video. Default to 'no' if the
    // pre-stop read failed — preserves the original audio-only contract.
    final restoreVid = (priorVid == 'auto' || priorVid == '1') ? 'auto' : 'no';
    try {
      await nativePlayer.setProperty('vid', restoreVid);
    } catch (e) {
      appLog('RECONNECT',
          '$cameraId: vid=$restoreVid restore failed (non-fatal): $e');
    }
  }

  /// Supervisor's onStatusChange: flip UI state.
  void _applyReconnectStatus(String cameraId, ReconnectStatus status) {
    final current = state.value;
    if (current == null) return;
    final idx = _cameraIndex(cameraId);
    if (idx < 0) return;
    final cam = current.cameras[idx];
    final newStatus = status == ReconnectStatus.reconnecting
        ? CameraConnectionStatus.reconnecting
        : CameraConnectionStatus.playing;
    state = AsyncData(current.copyWithCamera(
      idx,
      cam.copyWith(connectionStatus: newStatus),
    ));
    // RELY-03: a successful reconnect zeroes the watchdog so the next
    // zombie can fire fresh. Status `reconnecting` keeps counters running.
    if (status == ReconnectStatus.playing) {
      try {
        _zombieWatchdog.reset(cameraId);
      } catch (e) {
        appLog('ZOMBIE', 'reset error (non-fatal): $e');
      }
      try {
        _driftWatchdog.reset(cameraId);
      } catch (e) {
        appLog('DRIFT', 'reset error (non-fatal): $e');
      }
      // WR-03 fix: the new stream's audio-pts starts back near 0. The next
      // poll would otherwise compute a large negative ptsDelta against the
      // previous stream's PTS and miscount one tick of `silenceDuration`.
      _lastAudioPts.remove(cameraId);
      _baselineLevel.remove(cameraId);
    }
    // RELY-01 D-04: alert-timer lifecycle on supervisor-driven status changes.
    final cameraName = _findCameraName(cameraId) ?? cameraId;
    if (status == ReconnectStatus.playing) {
      _alertPolicy.clear(cameraId);
      LocalNotificationsManager.cancelAlert(cameraId);
    } else {
      appLog('NOTIF', 'Arming 5-min alert timer for $cameraName');
      _alertPolicy.armIfAbsent(cameraId);
    }
  }

  /// D-03 trigger c: WiFi dropped — record event only; supervisor will pick up
  /// player.stream.error within 30–60s naturally. Do NOT proactively reconnect
  /// while network is down — attempts would fail and waste battery.
  void _onWifiDropped() {
    appLog('CONN', 'WiFi dropped — recording event');
    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.wifiDropped,
          ));
    } catch (e) {
      appLog('CONN', 'Failed to record wifiDropped: $e');
    }
  }

  /// D-03 trigger c: WiFi reconnected — immediate retry for any non-playing
  /// camera. Bypasses backoff because the network just came back.
  void _onWifiReconnected() {
    appLog('CONN',
        'WiFi reconnected — triggering immediate reconnect for non-playing cameras');
    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.wifiReconnected,
          ));
    } catch (e) {
      appLog('CONN', 'Failed to record wifiReconnected: $e');
    }
    final current = state.value;
    if (current == null) return;
    for (final cam in current.cameras) {
      if (cam.connectionStatus != CameraConnectionStatus.playing) {
        try {
          _reconnectSupervisor.requestReconnect(
            cam.cameraId,
            cause: 'wifi_reconnect',
            immediate: true,
          );
        } catch (e) {
          appLog('CONN', 'wifi_reconnect requestReconnect failed: $e');
        }
      }
    }
  }

  /// Supervisor's onEvent: record to health summary stream.
  void _recordReconnectEvent(
    ReconnectEventType type,
    String cameraId,
    String? detail,
  ) {
    try {
      final cameraName = _findCameraName(cameraId) ?? cameraId;
      final evtType = type == ReconnectEventType.reconnectAttempt
          ? HealthEventType.reconnectAttempt
          : HealthEventType.reconnectSuccess;
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: evtType,
            cameraId: cameraId,
            cameraName: cameraName,
            detail: detail,
          ));
    } catch (e) {
      appLog('RECONNECT', 'Failed to record event: $e');
    }
  }

  String? _findCameraName(String cameraId) {
    final current = state.value;
    if (current == null) return null;
    for (final c in current.cameras) {
      if (c.cameraId == cameraId) return c.cameraName;
    }
    return null;
  }

  void setVolume(int cameraIndex, double volume) {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    player.setVolume(camState.isMuted ? 0.0 : volume);
    appLog('AUDIO', '${camState.cameraName} volume=${volume.toStringAsFixed(0)}');

    state = AsyncData(
      current.copyWithCamera(
        cameraIndex,
        camState.copyWith(volume: volume, preMuteVolume: volume),
      ),
    );
    _saveMixState();
  }

  void toggleMute(int cameraIndex) {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final player = _players[camState.cameraId];
    if (player == null) return;

    if (camState.isMuted) {
      player.setVolume(camState.preMuteVolume);
      appLog('AUDIO', '${camState.cameraName} unmuted (vol=${camState.preMuteVolume.toStringAsFixed(0)})');
      state = AsyncData(
        current.copyWithCamera(
          cameraIndex,
          camState.copyWith(isMuted: false),
        ),
      );
    } else {
      player.setVolume(0.0);
      appLog('AUDIO', '${camState.cameraName} muted');
      state = AsyncData(
        current.copyWithCamera(
          cameraIndex,
          camState.copyWith(
            isMuted: true,
            preMuteVolume: camState.volume,
          ),
        ),
      );
    }
    _saveMixState();
  }

  /// Mute all cameras in a single atomic state update.
  void muteAll() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      final cam = updated.cameras[i];
      if (!cam.isMuted) {
        _players[cam.cameraId]?.setVolume(0.0);
        updated = updated.copyWithCamera(i, cam.copyWith(
          isMuted: true,
          preMuteVolume: cam.volume,
        ));
      }
    }
    state = AsyncData(updated);
    appLog('AUDIO', 'All cameras muted');
    _saveMixState();
  }

  /// Unmute all cameras in a single atomic state update.
  void unmuteAll() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      final cam = updated.cameras[i];
      if (cam.isMuted) {
        _players[cam.cameraId]?.setVolume(cam.preMuteVolume);
        updated = updated.copyWithCamera(i, cam.copyWith(isMuted: false));
      }
    }
    state = AsyncData(updated);
    appLog('AUDIO', 'All cameras unmuted');
    _saveMixState();
  }

  /// Whether all cameras are currently muted.
  bool get isAllMuted {
    final current = state.value;
    if (current == null || current.cameras.isEmpty) return false;
    return current.cameras.every((c) => c.isMuted);
  }

  /// Enable or disable video decoding on all active players.
  Future<void> setVideoEnabled(bool enabled) async {
    final value = enabled ? 'auto' : 'no';
    appLog('AUDIO', 'Setting vid=$value on ${_players.length} players');
    _setAllCamerasConnecting();
    for (final player in _players.values) {
      final nativePlayer = player.platform as NativePlayer;
      await nativePlayer.setProperty('vid', value);
    }
    // Restore playing status directly — toggling vid track may not trigger
    // a buffering event since the audio stream is already flowing.
    _restoreAllCamerasPlaying();
  }

  void _setAllCamerasConnecting() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      if (updated.cameras[i].isLive) {
        updated = updated.copyWithCamera(i,
          updated.cameras[i].copyWith(connectionStatus: CameraConnectionStatus.connecting));
      }
    }
    state = AsyncData(updated);
  }

  void _restoreAllCamerasPlaying() {
    final current = state.value;
    if (current == null) return;
    var updated = current;
    for (int i = 0; i < updated.cameras.length; i++) {
      if (updated.cameras[i].connectionStatus == CameraConnectionStatus.connecting) {
        updated = updated.copyWithCamera(i,
          updated.cameras[i].copyWith(connectionStatus: CameraConnectionStatus.playing));
      }
    }
    state = AsyncData(updated);
  }

  /// Switch stream quality for a camera. Stops and re-opens with the new URL.
  Future<void> switchQuality(int cameraIndex, String quality) async {
    final current = state.value;
    if (current == null) return;
    if (cameraIndex < 0 || cameraIndex >= current.cameras.length) return;

    final camState = current.cameras[cameraIndex];
    final url = camState.availableQualities[quality];
    if (url == null || url == camState.activeStreamUrl) return;

    final player = _players[camState.cameraId];
    if (player == null) return;

    // Same ordered-candidate approach as startMonitoring/reconnect: local
    // first, then global-remote rewrite, then the camera's own remote URL.
    // Error state only when ALL candidates fail.
    final candidates = _candidatesFor(camState, quality);

    appLog('AUDIO',
        'Switching ${camState.cameraName} to $quality (${candidates.length} candidate(s)): $url');

    state = AsyncData(current.copyWithCamera(
      cameraIndex,
      camState.copyWith(
        connectionStatus: CameraConnectionStatus.connecting,
        activeQuality: quality,
        activeStreamUrl: url,
      ),
    ));

    try {
      _openingCameras.add(camState.cameraId);
      StreamCandidate winner;
      try {
        winner = await _openFirstCandidate(
            player, camState.cameraName, candidates, _candidateOpenTimeout);
      } finally {
        _openingCameras.remove(camState.cameraId);
      }
      // Errors from losing candidates already kicked the supervisor —
      // drop any pending retry now that a candidate is confirmed alive.
      try {
        _reconnectSupervisor.cancel(camState.cameraId);
      } catch (_) {}
      final updated = state.value!;
      state = AsyncData(updated.copyWithCamera(
        cameraIndex,
        updated.cameras[cameraIndex].copyWith(
          connectionStatus: CameraConnectionStatus.playing,
          activeStreamUrl: winner.url,
        ),
      ));
      appLog('AUDIO',
          '${camState.cameraName} now playing $quality via ${winner.label} candidate');
    } catch (e) {
      appLog('AUDIO', 'Error switching quality: $e');
      final updated = state.value!;
      state = AsyncData(updated.copyWithCamera(
        cameraIndex,
        updated.cameras[cameraIndex].copyWith(
          connectionStatus: CameraConnectionStatus.error,
          errorMessage: e.toString(),
        ),
      ));
    }
  }

  /// Enable or disable video decoding on a single player by camera ID.
  Future<void> setVideoEnabledForCamera(String cameraId, bool enabled) async {
    final player = _players[cameraId];
    if (player == null) return;
    final value = enabled ? 'auto' : 'no';
    appLog('AUDIO', 'Setting vid=$value for camera $cameraId');
    final nativePlayer = player.platform as NativePlayer;
    await nativePlayer.setProperty('vid', value);
  }

  Future<void> stopMonitoring() async {
    appLog('AUDIO', 'Stopping monitoring');
    _levelPollTimer?.cancel();
    // RELY-01 D-04: tear down alerts BEFORE the supervisor so a pending
    // status flap can't re-arm a timer mid-teardown.
    final knownCameraIds =
        state.value?.cameras.map((c) => c.cameraId).toList() ?? const [];
    try { _alertPolicy.cancelAll(); } catch (e) {
      appLog('NOTIF', 'AlertPolicy.cancelAll threw during stopMonitoring: $e');
    }
    for (final id in knownCameraIds) {
      LocalNotificationsManager.cancelAlert(id);
    }
    try { _connectivityListener.cancel(); } catch (e) {
      appLog('CONN', 'connectivity cancel threw during stopMonitoring: $e');
    }
    // Cancel supervisor BEFORE disposing players (T-04-08 ordering).
    try { _reconnectSupervisor.cancelAll(); } catch (e) {
      appLog('RECONNECT', 'cancelAll threw during stopMonitoring: $e');
    }
    try { _zombieWatchdog.resetAll(); } catch (e) {
      appLog('ZOMBIE', 'resetAll threw during stopMonitoring: $e');
    }
    try { _driftWatchdog.resetAll(); } catch (e) {
      appLog('DRIFT', 'resetAll threw during stopMonitoring: $e');
    }
    _lastAudioPts.clear();
    _baselineLevel.clear();
    _lastNotificationText = '';
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _videoControllers.clear();
    for (final player in _players.values) {
      await player.stop();
      await player.dispose();
    }
    _players.clear();
    state = const AsyncData(MonitoringState());
    appLog('AUDIO', 'All players stopped and disposed');

    // D-13: record monitoringStopped after teardown so it lands last in the list.
    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.monitoringStopped,
          ));
    } catch (e) {
      appLog('HEALTH', 'Failed to record monitoringStopped: $e');
    }

    // 260514-siv: finalize the persisted session. Awaits a synchronous flush
    // so the session is on disk before stopMonitoring returns (the user is
    // about to be routed to /cameras and might immediately re-open Sessions).
    try {
      await ref.read(sessionHistoryProvider.notifier).endCurrentSession();
    } catch (e) {
      appLog('SESSION', 'endCurrentSession from stopMonitoring failed: $e');
    }
  }

  /// Unified entry point for "the user wants monitoring fully stopped."
  ///
  /// Used by every stop path (inline Stop banner, media-notification Stop
  /// button, FGS notification Stop button, sign-out flow). Performs the
  /// full teardown that the in-process stopMonitoring() alone is not
  /// responsible for:
  ///   - delete the `was_monitoring` storage flag so the app doesn't try to
  ///     auto-resume on next launch
  ///   - clear AuthState.resumeMonitoring so UI predicates that OR it in
  ///     don't keep showing "monitoring active" after the user has stopped
  ///   - tear down players via stopMonitoring()
  ///   - stop the Android foreground service
  Future<void> stopMonitoringAndCleanup() async {
    // Preempt any settings-driven restart that hasn't started yet and signal
    // any in-flight restart to bail before it resurrects the streams. Without
    // this, a Stop click during a buffer/RTSP-driven restart leaves orphaned
    // players running with no banner left to stop them again.
    _settingsRestartDebounce?.cancel();
    _settingsRestartDebounce = null;
    _stopRequested = true;
    return _runLifecycle(() async {
      try {
        await ref.read(storageProvider).delete('was_monitoring');
      } catch (e) {
        appLog('AUDIO', 'failed to delete was_monitoring (continuing): $e');
      }
      try {
        ref.read(authNotifierProvider.notifier).clearResumeFlag();
      } catch (e) {
        appLog('AUDIO', 'failed to clear resume flag (continuing): $e');
      }
      await stopMonitoring();
      try {
        await ForegroundServiceManager.stop();
      } catch (e) {
        appLog('AUDIO', 'failed to stop FGS (continuing): $e');
      }
      // Flip the MediaSession/audio_service notification to idle. Without this
      // the media notification ("Baby Monitor Active" with Pause/Stop controls)
      // keeps showing an active-looking state and re-surfaces when the app is
      // backgrounded — only the media notification's own Stop button called
      // setIdle() before, so stopping from the inline banner or the FGS
      // notification left it lingering. This is the shared stop path for every
      // entry point, so setting idle here covers all of them.
      try {
        final handler = await ref.read(audioHandlerProvider.future);
        handler.setIdle();
      } catch (e) {
        appLog('AUDIO_SERVICE',
            'failed to set media handler idle (continuing): $e');
      }
    });
  }

  /// Remove a single camera from the live mix without stopping the others.
  ///
  /// Disposes that camera's player, drops it from the audio state, removes
  /// it from the user's selected set, and records a health event. If the
  /// removed camera was the last one, falls back to a full stop so the
  /// foreground service isn't left running with nothing to play.
  Future<void> removeCamera(String cameraId) async {
    final current = state.value;
    if (current == null) return;
    final idx = _cameraIndex(cameraId);
    if (idx < 0) return;
    final cam = current.cameras[idx];
    appLog('AUDIO', 'Removing camera ${cam.cameraName} ($cameraId) from mix');

    // Stop the per-camera reconnect supervisor + clear watchdog state so
    // they don't fire on a disposed player.
    try { _reconnectSupervisor.cancel(cameraId); } catch (_) {}
    try { _zombieWatchdog.reset(cameraId); } catch (_) {}
    try { _driftWatchdog.reset(cameraId); } catch (_) {}
    try { _alertPolicy.clear(cameraId); } catch (_) {}
    LocalNotificationsManager.cancelAlert(cameraId);

    final player = _players.remove(cameraId);
    _videoControllers.remove(cameraId);
    _lastAudioPts.remove(cameraId);
    _baselineLevel.remove(cameraId);
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (e) {
        appLog('AUDIO', 'dispose for $cameraId threw (continuing): $e');
      }
    }

    // Drop the camera from MonitoringState.
    final newCameras = [...current.cameras]..removeAt(idx);
    state = AsyncData(current.copyWith(cameras: newCameras));

    // Drop from the user's selected set so on next start it stays out.
    try {
      ref.read(cameraNotifierProvider.notifier).toggleCamera(cameraId);
    } catch (e) {
      // toggleCamera no-ops if not selected; safe to ignore.
      appLog('AUDIO', 'toggleCamera on remove threw (continuing): $e');
    }

    try {
      ref.read(healthEventsProvider.notifier).record(HealthEvent(
            timestamp: DateTime.now(),
            type: HealthEventType.monitoringStopped,
            cameraId: cameraId,
            cameraName: cam.cameraName,
            detail: 'removed from mix',
          ));
    } catch (_) {}

    // If that was the last camera, fall back to a full stop so the FGS
    // isn't left running with no audio.
    if (newCameras.isEmpty) {
      appLog('AUDIO', 'Last camera removed — performing full stop');
      await stopMonitoringAndCleanup();
    }
  }

  /// Add a single camera to a LIVE mix without disturbing the running players.
  ///
  /// Inverse of [removeCamera]. Connects just this camera via the shared
  /// [_connectCamera] helper and APPENDS it to [MonitoringState.cameras]. It
  /// never sets `AsyncLoading` and never calls stopMonitoring, so every
  /// already-running player keeps playing untouched (T-oj0-01) — the observable
  /// contract is that no other camera's connectionStatus/activeStreamUrl
  /// changes across the add. Restores the camera's saved volume/mute, persists
  /// it into the selected set so it survives a restart, and records a health
  /// event. No-ops (with a log) when there is no live session, the camera is
  /// already in the mix, or the id can't be resolved from the camera list.
  ///
  /// Runs through [_runLifecycle] so it can never interleave with a stop or a
  /// settings-driven restart.
  Future<void> addCameraToSession(String cameraId,
      {bool videoPreview = false}) async {
    return _runLifecycle(() async {
      final current = state.value;
      if (current == null) {
        appLog('AUDIO', 'addCameraToSession: no monitoring state — ignoring');
        return;
      }
      // No live session — a fresh start is the correct path, not an add.
      if (_players.isEmpty) {
        appLog('AUDIO',
            'addCameraToSession: no live session — ignoring $cameraId');
        return;
      }
      // Already in the mix — nothing to do (never reopen a running stream).
      if (current.cameras.any((c) => c.cameraId == cameraId)) {
        appLog('AUDIO',
            'addCameraToSession: $cameraId already in the mix — ignoring');
        return;
      }
      // Resolve the camera from the (already-trusted) loaded camera list.
      ProtectCamera? camera;
      final all = ref.read(cameraNotifierProvider).value?.cameras ??
          const <ProtectCamera>[];
      for (final c in all) {
        if (c.id == cameraId) {
          camera = c;
          break;
        }
      }
      if (camera == null) {
        appLog('AUDIO',
            'addCameraToSession: no camera with id $cameraId — ignoring');
        return;
      }

      appLog('AUDIO', 'Adding camera ${camera.name ?? cameraId} to live mix');
      var camState = await _connectCamera(camera, videoPreview: videoPreview);

      // Restore saved volume/mute for just this camera (same source as
      // startMonitoring's full-list restore). Defensive: a failure here must
      // not drop the freshly-connected stream.
      try {
        final savedMix = await _loadMixState();
        final mix = savedMix[camState.cameraId];
        if (mix != null) {
          final volume = (mix['volume'] as num?)?.toDouble() ?? 100.0;
          final muted = mix['muted'] as bool? ?? false;
          camState = camState.copyWith(
            volume: volume,
            preMuteVolume: volume,
            isMuted: muted,
          );
          _players[camState.cameraId]?.setVolume(muted ? 0.0 : volume);
          appLog('AUDIO',
              '${camState.cameraName} restored vol=${volume.toStringAsFixed(0)} muted=$muted');
        }
      } catch (e) {
        appLog('AUDIO',
            'addCameraToSession: mix restore failed (continuing): $e');
      }

      // Append WITHOUT AsyncLoading / stopMonitoring — that would blank the
      // grid and drop the other players. Re-read state fresh: the awaits above
      // yielded, so poll/reconnect callbacks may have replaced it.
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(cameras: [...latest.cameras, camState]),
      );

      // Persist selection so the camera survives a restart. toggleCamera
      // toggles, so only call it when the camera isn't already selected
      // (otherwise it would deselect it).
      try {
        final selectedIds =
            ref.read(cameraNotifierProvider).value?.selectedIds ?? const {};
        if (!selectedIds.contains(cameraId)) {
          ref.read(cameraNotifierProvider.notifier).toggleCamera(cameraId);
        }
      } catch (e) {
        appLog('AUDIO',
            'addCameraToSession: persist selection failed (continuing): $e');
      }

      // Health event + notification refresh, mirroring startMonitoring.
      // Defensive: never let these tear down the running stream.
      try {
        ref.read(healthEventsProvider.notifier).record(HealthEvent(
              timestamp: DateTime.now(),
              type: HealthEventType.streamStarted,
              cameraId: cameraId,
              cameraName: camState.cameraName,
              detail: 'added to mix',
            ));
      } catch (e) {
        appLog('HEALTH',
            'addCameraToSession: failed to record streamStarted: $e');
      }
      try {
        final cams = state.value?.cameras ?? const <CameraAudioState>[];
        final statusParts = cams.map((c) {
          final status = c.connectionStatus == CameraConnectionStatus.playing
              ? '' : ' (${c.connectionStatus.name})';
          return '${c.cameraName}$status';
        }).toList();
        final text = 'Monitoring: ${statusParts.join(", ")}';
        _lastNotificationText = text;
        await ForegroundServiceManager.updateNotification(text: text);
      } catch (e) {
        appLog('FGS',
            'addCameraToSession: failed to update notification: $e');
      }
    });
  }

  /// Save per-camera volume/mute to secure storage.
  void _saveMixState() {
    final current = state.value;
    if (current == null) return;
    final map = <String, Map<String, dynamic>>{};
    for (final cam in current.cameras) {
      map[cam.cameraId] = {
        'volume': cam.volume,
        'muted': cam.isMuted,
      };
    }
    try {
      ref.read(storageProvider).write('mix_state', jsonEncode(map));
    } catch (_) {}
  }

  /// Load per-camera volume/mute from secure storage.
  Future<Map<String, Map<String, dynamic>>> _loadMixState() async {
    try {
      final raw = await ref.read(storageProvider).read('mix_state');
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
    } catch (_) {
      return {};
    }
  }
}

/// The cameras in [all] that are not already represented in [inSession] — i.e.
/// the set a live-session "add camera" picker should offer. Pure and free of
/// native/platform dependencies so the UI can render it and it can be
/// unit-tested directly (the notifier methods that open streams cannot).
List<ProtectCamera> addableCameras(
  List<ProtectCamera> all,
  List<CameraAudioState> inSession,
) =>
    all.where((c) => !inSession.any((s) => s.cameraId == c.id)).toList();
