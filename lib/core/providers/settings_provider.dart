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

/// Default [AppSettings.levelThreshold]: a quarter of the way up the meter,
/// comfortably above poll jitter on a calm night, well below a cry.
const kDefaultLevelThreshold = 0.25;

class AppSettings {
  /// Use plain RTSP (port 7447) instead of RTSPS (port 7441 + SRTP).
  final bool useRtsp;

  /// Audio output buffer in seconds. Higher = smoother, more latency.
  final double audioBufferSeconds;

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

  const AppSettings({
    this.useRtsp = false,
    this.audioBufferSeconds = 0.5,
    this.levelThreshold = kDefaultLevelThreshold,
    this.themeMode = ThemeMode.system,
    this.oledDark = false,
  });

  AppSettings copyWith({
    bool? useRtsp,
    double? audioBufferSeconds,
    double? levelThreshold,
    ThemeMode? themeMode,
    bool? oledDark,
  }) =>
      AppSettings(
        useRtsp: useRtsp ?? this.useRtsp,
        audioBufferSeconds: audioBufferSeconds ?? this.audioBufferSeconds,
        levelThreshold: levelThreshold ?? this.levelThreshold,
        themeMode: themeMode ?? this.themeMode,
        oledDark: oledDark ?? this.oledDark,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          useRtsp == other.useRtsp &&
          audioBufferSeconds == other.audioBufferSeconds &&
          levelThreshold == other.levelThreshold &&
          themeMode == other.themeMode &&
          oledDark == other.oledDark;

  @override
  int get hashCode => Object.hash(
        useRtsp,
        audioBufferSeconds,
        levelThreshold,
        themeMode,
        oledDark,
      );

  Map<String, dynamic> toJson() => {
        'useRtsp': useRtsp,
        'audioBufferSeconds': audioBufferSeconds,
        'levelThreshold': levelThreshold,
        'themeMode': _themeModeToName(themeMode),
        'oledDark': oledDark,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        useRtsp: json['useRtsp'] as bool? ?? false,
        audioBufferSeconds:
            (json['audioBufferSeconds'] as num?)?.toDouble() ?? 0.5,
        levelThreshold:
            (json['levelThreshold'] as num?)?.toDouble() ?? kDefaultLevelThreshold,
        themeMode: _themeModeFromName(json['themeMode']),
        // Same tolerance as themeMode, and for the same reason: a cast here
        // would throw out of the whole decode, and _loadFromStorage swallows
        // that — so one wrong-typed field would silently reset every setting.
        oledDark: _boolOrFalse(json['oledDark']),
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
            'Loaded: rtsp=${settings.useRtsp} buffer=${settings.audioBufferSeconds}s activity=${settings.levelThreshold}');
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
