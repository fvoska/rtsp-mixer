import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../logging/app_logger.dart';

class AppSettings {
  /// Use plain RTSP (port 7447) instead of RTSPS (port 7441 + SRTP).
  final bool useRtsp;

  /// Audio output buffer in seconds. Higher = smoother, more latency.
  final double audioBufferSeconds;

  /// Activity-trigger sensitivity for the highlight border on camera cards.
  /// 0.01 = most sensitive (any sound), 0.5 = least.
  final double activityThreshold;

  const AppSettings({
    this.useRtsp = false,
    this.audioBufferSeconds = 0.5,
    this.activityThreshold = 0.05,
  });

  AppSettings copyWith({
    bool? useRtsp,
    double? audioBufferSeconds,
    double? activityThreshold,
  }) =>
      AppSettings(
        useRtsp: useRtsp ?? this.useRtsp,
        audioBufferSeconds: audioBufferSeconds ?? this.audioBufferSeconds,
        activityThreshold: activityThreshold ?? this.activityThreshold,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          useRtsp == other.useRtsp &&
          audioBufferSeconds == other.audioBufferSeconds &&
          activityThreshold == other.activityThreshold;

  @override
  int get hashCode =>
      Object.hash(useRtsp, audioBufferSeconds, activityThreshold);

  Map<String, dynamic> toJson() => {
        'useRtsp': useRtsp,
        'audioBufferSeconds': audioBufferSeconds,
        'activityThreshold': activityThreshold,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        useRtsp: json['useRtsp'] as bool? ?? false,
        audioBufferSeconds:
            (json['audioBufferSeconds'] as num?)?.toDouble() ?? 0.5,
        activityThreshold:
            (json['activityThreshold'] as num?)?.toDouble() ?? 0.05,
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
            'Loaded: rtsp=${settings.useRtsp} buffer=${settings.audioBufferSeconds}s activity=${settings.activityThreshold}');
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

  void setActivityThreshold(double value) {
    state = state.copyWith(activityThreshold: value);
    appLog('SETTINGS', 'Activity threshold: $value');
    _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
