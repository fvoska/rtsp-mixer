import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../models/player_state.dart';

/// Health of the live monitoring session, derived from the per-camera
/// connection states.
///
/// Every surface that summarizes "is the session OK?" — the monitoring
/// banner, the header status line, the mini-bar above the nav bar, the live
/// row in the sessions list — resolves it through here so colour and wording
/// can never disagree. A parent glancing at a red bar that reads "Monitoring
/// active" learns nothing about what is wrong.
enum SessionStatus { playing, connecting, reconnecting, error }

/// Resolve the session status from the audio player state.
///
/// Only [SessionStatus.playing] — every camera actually streaming — means the
/// session is healthy. A still-loading provider resolves to
/// [SessionStatus.connecting] rather than to a healthy state: not-yet-known is
/// never reported as live.
SessionStatus resolveSessionStatus(AsyncValue<MonitoringState> monitoring) {
  if (monitoring.hasError) return SessionStatus.error;
  final state = monitoring.value;
  if (state == null || state.cameras.isEmpty) return SessionStatus.connecting;
  if (state.anyError) return SessionStatus.error;
  if (state.allLive) return SessionStatus.playing;
  // A dropped-and-recovering stream is not a first connection; name it so the
  // UI doesn't imply a fresh, healthy start.
  if (state.cameras.any((c) => c.isReconnecting)) {
    return SessionStatus.reconnecting;
  }
  return SessionStatus.connecting;
}

/// Honest one-line summary of the session. Only [SessionStatus.playing] may
/// claim monitoring is active; every other state names itself.
String sessionStatusLabel(SessionStatus status) => switch (status) {
      SessionStatus.playing => 'Monitoring active',
      SessionStatus.connecting => 'Connecting…',
      SessionStatus.reconnecting => 'Reconnecting…',
      SessionStatus.error => 'Stream failed',
    };

/// Status colour for dots, chips and accents. Mirrors the per-camera palette
/// (teal live / blue connecting / amber reconnecting / red offline).
Color sessionStatusColor(SessionStatus status, StatusColors colors) =>
    switch (status) {
      SessionStatus.playing => colors.live,
      SessionStatus.connecting => colors.connecting,
      SessionStatus.reconnecting => colors.reconnecting,
      SessionStatus.error => colors.offline,
    };

extension SessionStatusX on SessionStatus {
  /// True only when every camera in the mix is streaming — the one state
  /// allowed to render the reassuring "Listening / Monitoring · uptime" copy.
  bool get isHealthy => this == SessionStatus.playing;
}
