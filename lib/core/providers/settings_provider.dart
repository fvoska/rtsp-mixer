import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../logging/app_logger.dart';

/// Persisted as a stable string rather than the enum index: reordering
/// [ThemeMode] in a future SDK must never silently flip a user's theme.
const _themeModeNames = <ThemeMode, String>{
  ThemeMode.system: 'system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};

String _themeModeToName(ThemeMode mode) => _themeModeNames[mode] ?? 'system';

/// Tolerant by design: a null, absent, or unrecognised value (a settings blob
/// written by an older or newer build) decodes to system instead of throwing.
ThemeMode _themeModeFromName(Object? raw) {
  if (raw is! String) return ThemeMode.system;
  for (final entry in _themeModeNames.entries) {
    if (entry.value == raw) return entry.key;
  }
  return ThemeMode.system;
}

/// Tolerant bool decode: anything that is not a real `true` reads as false.
bool _boolOrFalse(Object? raw) => raw is bool && raw;

/// How the player rides the live edge of a stream.
///
/// The demuxer packet cache of a live RTSP stream can only grow: every
/// playback stall (Doze, an audio-focus duck, WiFi jitter, the NVR's start-up
/// burst) leaves a residue that 1x playback never drains. Both modes drain
/// it by playing slightly faster for a while (mpv `speed` with the built-in
/// `scaletempo2` pitch correction); they differ in how much backlog they
/// deliberately keep as a jitter buffer and in what happens on an underrun.
enum StreamMode {
  /// Lowest latency. Keeps the cache near empty and plays straight through
  /// jitter (an underrun is a brief dropout, never a pause).
  realtime,

  /// Holds [AppSettings.bufferedDelaySeconds] of audio ahead of the playhead
  /// and lets mpv rebuffer natively (`cache-pause`) when the network stalls.
  /// Smoother on a flaky WiFi at the cost of a fixed delay.
  buffered,
}

const _streamModeNames = <StreamMode, String>{
  StreamMode.realtime: 'realtime',
  StreamMode.buffered: 'buffered',
};

String streamModeToName(StreamMode mode) =>
    _streamModeNames[mode] ?? 'realtime';

/// Tolerant like [_themeModeFromName]: unknown or wrong-typed → realtime.
StreamMode _streamModeFromName(Object? raw) {
  if (raw is! String) return StreamMode.realtime;
  for (final entry in _streamModeNames.entries) {
    if (entry.value == raw) return entry.key;
  }
  return StreamMode.realtime;
}

/// Default [AppSettings.bufferedDelaySeconds] and the range the slider (and
/// the decoder) clamp it to. 0.5 s is already enough to ride out typical LAN
/// jitter; 5 s is the most delay that still feels "live" on a monitor.
const kDefaultBufferedDelaySeconds = 2.0;
const kMinBufferedDelaySeconds = 0.5;
const kMaxBufferedDelaySeconds = 5.0;

/// Tolerant double decode with clamping: a missing, wrong-typed or absurd
/// value reads as the default instead of throwing out of the whole blob.
double _clampedDouble(Object? raw, double fallback, double min, double max) {
  if (raw is! num) return fallback;
  final v = raw.toDouble();
  if (!v.isFinite) return fallback;
  return v.clamp(min, max).toDouble();
}

/// Default [AppSettings.levelThreshold]: a quarter of the way up the meter,
/// comfortably above poll jitter on a calm night, well below a cry.
const kDefaultLevelThreshold = 0.25;

class AppSettings {
  /// Use plain RTSP (port 7447) instead of RTSPS (port 7441 + SRTP).
  final bool useRtsp;

  /// Audio output buffer in seconds. Higher = smoother, more latency.
  ///
  /// This is mpv's `audio-buffer` — the decoded-sample buffer in front of
  /// the audio device. It is unrelated to the demuxer packet cache that
  /// [streamMode] / [bufferedDelaySeconds] govern.
  final double audioBufferSeconds;

  /// Realtime (lowest latency) or Buffered (hold a jitter buffer).
  final StreamMode streamMode;

  /// Seconds of audio the Buffered mode keeps ahead of the playhead. Ignored
  /// in Realtime mode. Clamped to [kMinBufferedDelaySeconds]..
  /// [kMaxBufferedDelaySeconds] on decode.
  final double bufferedDelaySeconds;

  /// Sound level (0..1, relative to the room's noise floor — see
  /// `AudioLevelTracker`) above which a camera card lights up its border.
  /// 0.05 = most sensitive (almost any sound), 0.6 = least (loud sounds only).
  ///
  /// Persisted under the key `levelThreshold`. The previous meter stored a
  /// peak-to-trough *variation* threshold under `activityThreshold` with a
  /// default of 0.05; that value means something else on this scale, so it
  /// is deliberately not read back.
  final double levelThreshold;

  /// System / Light / Dark, chosen by the user in Settings.
  final ThemeMode themeMode;

  /// Use the true-black OLED dark theme instead of the standard petrol one.
  ///
  /// Orthogonal to [themeMode] by design: it is a property of the *dark*
  /// theme, so it applies whenever dark is active — whether the user picked
  /// [ThemeMode.dark] or the OS resolved dark under [ThemeMode.system]. It has
  /// no effect while light is showing, and is deliberately still persisted in
  /// that case so switching back to dark restores the user's choice.
  final bool oledDark;

  /// Skip non-essential per-tick processing (loudness/activity estimation,
  /// stream metadata polling) to reduce CPU wake-ups overnight. Stream
  /// health monitoring (silence detection, zombie/drift watchdogs, and
  /// auto-reconnect) keeps running unchanged — only the SPL/activity and
  /// metadata work that feeds the on-screen meter and debug panel is cut.
  final bool batterySaverMode;

  const AppSettings({
    this.useRtsp = false,
    this.audioBufferSeconds = 0.5,
    this.streamMode = StreamMode.realtime,
    this.bufferedDelaySeconds = kDefaultBufferedDelaySeconds,
    this.levelThreshold = kDefaultLevelThreshold,
    this.themeMode = ThemeMode.system,
    this.oledDark = false,
    this.batterySaverMode = false,
  });

  AppSettings copyWith({
    bool? useRtsp,
    double? audioBufferSeconds,
    StreamMode? streamMode,
    double? bufferedDelaySeconds,
    double? levelThreshold,
    ThemeMode? themeMode,
    bool? oledDark,
    bool? batterySaverMode,
  }) =>
      AppSettings(
        useRtsp: useRtsp ?? this.useRtsp,
        audioBufferSeconds: audioBufferSeconds ?? this.audioBufferSeconds,
        streamMode: streamMode ?? this.streamMode,
        bufferedDelaySeconds:
            bufferedDelaySeconds ?? this.bufferedDelaySeconds,
        levelThreshold: levelThreshold ?? this.levelThreshold,
        themeMode: themeMode ?? this.themeMode,
        oledDark: oledDark ?? this.oledDark,
        batterySaverMode: batterySaverMode ?? this.batterySaverMode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          useRtsp == other.useRtsp &&
          audioBufferSeconds == other.audioBufferSeconds &&
          streamMode == other.streamMode &&
          bufferedDelaySeconds == other.bufferedDelaySeconds &&
          levelThreshold == other.levelThreshold &&
          themeMode == other.themeMode &&
          oledDark == other.oledDark &&
          batterySaverMode == other.batterySaverMode;

  @override
  int get hashCode => Object.hash(
        useRtsp,
        audioBufferSeconds,
        streamMode,
        bufferedDelaySeconds,
        levelThreshold,
        themeMode,
        oledDark,
        batterySaverMode,
      );

  Map<String, dynamic> toJson() => {
        'useRtsp': useRtsp,
        'audioBufferSeconds': audioBufferSeconds,
        'streamMode': streamModeToName(streamMode),
        'bufferedDelaySeconds': bufferedDelaySeconds,
        'levelThreshold': levelThreshold,
        'themeMode': _themeModeToName(themeMode),
        'oledDark': oledDark,
        'batterySaverMode': batterySaverMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        useRtsp: json['useRtsp'] as bool? ?? false,
        audioBufferSeconds:
            (json['audioBufferSeconds'] as num?)?.toDouble() ?? 0.5,
        streamMode: _streamModeFromName(json['streamMode']),
        bufferedDelaySeconds: _clampedDouble(
          json['bufferedDelaySeconds'],
          kDefaultBufferedDelaySeconds,
          kMinBufferedDelaySeconds,
          kMaxBufferedDelaySeconds,
        ),
        levelThreshold:
            (json['levelThreshold'] as num?)?.toDouble() ?? kDefaultLevelThreshold,
        themeMode: _themeModeFromName(json['themeMode']),
        // Same tolerance as themeMode, and for the same reason: a cast here
        // would throw out of the whole decode, and _loadFromStorage swallows
        // that — so one wrong-typed field would silently reset every setting.
        oledDark: _boolOrFalse(json['oledDark']),
        batterySaverMode: _boolOrFalse(json['batterySaverMode']),
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _storageKey = 'app_settings';

  @override
  AppSettings build() {
    _loadFromStorage();
    return const AppSettings();
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw = await ref.read(storageProvider).read(_storageKey);
      if (raw != null) {
        final settings = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        state = settings;
        appLog('SETTINGS',
            'Loaded: rtsp=${settings.useRtsp} buffer=${settings.audioBufferSeconds}s '
            'mode=${streamModeToName(settings.streamMode)} '
            'delay=${settings.bufferedDelaySeconds}s activity=${settings.levelThreshold}');
      }
    } catch (e) {
      appLog('SETTINGS', 'Failed to load settings: $e');
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(storageProvider).write(_storageKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  void setUseRtsp(bool value) {
    state = state.copyWith(useRtsp: value);
    appLog('SETTINGS', 'Use RTSP: $value');
    _save();
  }

  void setAudioBufferSeconds(double value) {
    state = state.copyWith(audioBufferSeconds: value);
    appLog('SETTINGS', 'Audio buffer: ${value}s');
    _save();
  }

  void setStreamMode(StreamMode value) {
    state = state.copyWith(streamMode: value);
    appLog('SETTINGS', 'Stream mode: ${streamModeToName(value)}');
    _save();
  }

  void setBufferedDelaySeconds(double value) {
    final clamped = value
        .clamp(kMinBufferedDelaySeconds, kMaxBufferedDelaySeconds)
        .toDouble();
    state = state.copyWith(bufferedDelaySeconds: clamped);
    appLog('SETTINGS', 'Buffered delay: ${clamped}s');
    _save();
  }

  void setThemeMode(ThemeMode value) {
    state = state.copyWith(themeMode: value);
    appLog('SETTINGS', 'Theme mode: ${_themeModeToName(value)}');
    _save();
  }

  void setOledDark(bool value) {
    state = state.copyWith(oledDark: value);
    appLog('SETTINGS', 'OLED dark: $value');
    _save();
  }

  void setLevelThreshold(double value) {
    state = state.copyWith(levelThreshold: value);
    appLog('SETTINGS', 'Level threshold: $value');
    _save();
  }

  void setBatterySaverMode(bool value) {
    state = state.copyWith(batterySaverMode: value);
    appLog('SETTINGS', 'Battery saver mode: $value');
    _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
