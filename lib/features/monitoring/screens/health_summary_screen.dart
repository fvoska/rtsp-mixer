import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../models/health_event.dart';
import '../models/session.dart';

/// MNTR-01 / 260514-siv: per-session health summary.
///
/// Reads events directly from the [Session] passed in (no longer watches
/// healthEventsProvider). Used both for in-flight sessions (via /sessions/:id
/// when current.id matches) and for finalized sessions from history.
class HealthSummaryScreen extends ConsumerWidget {
  const HealthSummaryScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = session.events;

    final cameras = session.cameras;

    final startedEvent = events
        .where((e) => e.type == HealthEventType.monitoringStarted)
        .fold<HealthEvent?>(null, (_, e) => e);
    final isStoppedSession = session.endedAt != null ||
        (events.isNotEmpty &&
            events.last.type == HealthEventType.monitoringStopped);

    // Non-trivial events = everything except the implicit monitoringStarted row.
    final nonTrivial = events.where(
      (e) => e.type != HealthEventType.monitoringStarted,
    );
    final isEmpty = nonTrivial.isEmpty;

    final reconnectCountByCamera = <String, int>{};
    for (final e in events) {
      if (e.type == HealthEventType.reconnectAttempt && e.cameraId != null) {
        reconnectCountByCamera[e.cameraId!] =
            (reconnectCountByCamera[e.cameraId!] ?? 0) + 1;
      }
    }

    final downtimeByCamera = _computeDowntimeByCamera(events);

    return Scaffold(
      appBar: AppBar(
        title: Text(_formatRange(session)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SessionUptimeCard(
              startedAt: startedEvent?.timestamp ?? session.startedAt,
              endedAt: session.endedAt,
            ),
            const SizedBox(height: Spacing.lg),
            if (cameras.isNotEmpty) ...[
              Text('Cameras', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              _CamerasRow(
                cameras: cameras,
                reconnectCount: reconnectCountByCamera,
                downtime: downtimeByCamera,
              ),
              const SizedBox(height: Spacing.lg),
            ],
            Text('Events', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (isStoppedSession) ...[
              const _StoppedSessionBanner(),
              const SizedBox(height: Spacing.sm),
            ],
            if (isEmpty)
              const Expanded(child: _EmptyEvents())
            else
              Expanded(
                child: Builder(
                  builder: (_) {
                    final reversed = events.reversed.toList();
                    return ListView.builder(
                      itemCount: reversed.length,
                      itemBuilder: (_, i) => _EventRow(event: reversed[i]),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Computes per-camera downtime by summing (streamError/zombieDetected → reconnectSuccess/streamStarted) windows.
  /// A window opens on streamError / zombieDetected; closes on the next reconnectSuccess
  /// or streamStarted for the same cameraId.
  Map<String, Duration> _computeDowntimeByCamera(List<HealthEvent> events) {
    final openFrom = <String, DateTime>{};
    final total = <String, Duration>{};
    for (final e in events) {
      final id = e.cameraId;
      if (id == null) continue;
      final opens = e.type == HealthEventType.streamError ||
          e.type == HealthEventType.zombieDetected;
      final closes = e.type == HealthEventType.reconnectSuccess ||
          e.type == HealthEventType.streamStarted;
      if (opens && openFrom[id] == null) {
        openFrom[id] = e.timestamp;
      } else if (closes && openFrom[id] != null) {
        final d = e.timestamp.difference(openFrom[id]!);
        total[id] = (total[id] ?? Duration.zero) + d;
        openFrom.remove(id);
      }
    }
    return total;
  }
}

String _formatRange(Session s) {
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String ymd(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  final end = s.endedAt;
  if (end == null) {
    return '${ymd(s.startedAt)} · ${hm(s.startedAt)} → live';
  }
  final sameDay = s.startedAt.year == end.year &&
      s.startedAt.month == end.month &&
      s.startedAt.day == end.day;
  if (sameDay) {
    return '${ymd(s.startedAt)} · ${hm(s.startedAt)} → ${hm(end)}';
  }
  return '${ymd(s.startedAt)} → ${ymd(end)}';
}

class _SessionUptimeCard extends StatelessWidget {
  const _SessionUptimeCard({required this.startedAt, required this.endedAt});
  final DateTime? startedAt;
  final DateTime? endedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = endedAt ?? DateTime.now();
    final uptime = startedAt != null
        ? end.difference(startedAt!)
        : Duration.zero;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              endedAt == null ? 'Session uptime' : 'Session duration',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              _formatUptime(uptime),
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }

  String _formatUptime(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes - h * 60;
    return '${h}h ${m}m';
  }
}

class _CamerasRow extends StatelessWidget {
  const _CamerasRow({
    required this.cameras,
    required this.reconnectCount,
    required this.downtime,
  });
  final List<({String id, String name})> cameras;
  final Map<String, int> reconnectCount;
  final Map<String, Duration> downtime;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < cameras.length; i++) {
      final cam = cameras[i];
      children.add(Expanded(
        child: _CameraTile(
          name: cam.name,
          reconnects: reconnectCount[cam.id] ?? 0,
          downtime: downtime[cam.id] ?? Duration.zero,
        ),
      ));
      if (i < cameras.length - 1) {
        children.add(const SizedBox(width: Spacing.md));
      }
    }
    return Row(children: children);
  }
}

class _CameraTile extends StatelessWidget {
  const _CameraTile({
    required this.name,
    required this.reconnects,
    required this.downtime,
  });
  final String name;
  final int reconnects;
  final Duration downtime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            _MetricRow(
              label: 'Reconnects',
              value: '$reconnects',
            ),
            const SizedBox(height: Spacing.xs),
            _MetricRow(
              label: 'Downtime',
              value: _formatDowntime(downtime),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDowntime(Duration d) {
    if (d == Duration.zero) return '—';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds - m * 60;
    return '${m}m ${s}s';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _StoppedSessionBanner extends StatelessWidget {
  const _StoppedSessionBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Session finalized.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No events recorded',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text(
              'This session ran without any reconnects, WiFi changes, or alerts.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final HealthEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconData = _iconForType(event.type);
    final color = _colorForType(event.type, theme);
    final label = _labelForType(event.type);
    final timestamp = _formatHms(event.timestamp);
    final camera = event.cameraName ?? 'Session';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                // UI-SPEC §Accessibility Contract: wrap icon in Semantics(label: labelForType)
                // so screen readers announce the event type (icon is purely visual).
                child: Semantics(
                  label: label,
                  child: Icon(iconData, size: 20, color: color),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  '$timestamp · $camera · $label',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (event.detail != null && event.detail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: Spacing.lg,
                top: Spacing.xs,
              ),
              child: Text(
                event.detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  String _formatHms(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
  }

  IconData _iconForType(HealthEventType t) {
    switch (t) {
      case HealthEventType.monitoringStarted:
        return Icons.play_circle_outline;
      case HealthEventType.monitoringStopped:
        return Icons.stop_circle_outlined;
      case HealthEventType.streamStarted:
        return Icons.play_arrow;
      case HealthEventType.streamError:
        return Icons.error_outline;
      case HealthEventType.reconnectAttempt:
        return Icons.refresh;
      case HealthEventType.reconnectSuccess:
        return Icons.check_circle_outline;
      case HealthEventType.zombieDetected:
        return Icons.warning_amber_outlined;
      case HealthEventType.wifiDropped:
        return Icons.wifi_off;
      case HealthEventType.wifiReconnected:
        return Icons.wifi;
      case HealthEventType.alertFired:
        return Icons.notifications_active_outlined;
    }
  }

  Color _colorForType(HealthEventType t, ThemeData theme) {
    switch (t) {
      case HealthEventType.monitoringStarted:
      case HealthEventType.streamStarted:
      case HealthEventType.reconnectSuccess:
        return AppTheme.statusOnline;
      case HealthEventType.streamError:
      case HealthEventType.zombieDetected:
        return AppTheme.statusOffline;
      case HealthEventType.reconnectAttempt:
      case HealthEventType.wifiDropped:
      case HealthEventType.alertFired:
        return theme.colorScheme.tertiary;
      case HealthEventType.wifiReconnected:
        return theme.colorScheme.primary;
      case HealthEventType.monitoringStopped:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _labelForType(HealthEventType t) {
    switch (t) {
      case HealthEventType.monitoringStarted:
        return 'Monitoring started';
      case HealthEventType.monitoringStopped:
        return 'Monitoring stopped';
      case HealthEventType.streamStarted:
        return 'Stream started';
      case HealthEventType.streamError:
        return 'Stream error';
      case HealthEventType.reconnectAttempt:
        return 'Reconnect attempt';
      case HealthEventType.reconnectSuccess:
        return 'Reconnected';
      case HealthEventType.zombieDetected:
        return 'Zombie stream detected';
      case HealthEventType.wifiDropped:
        return 'WiFi lost';
      case HealthEventType.wifiReconnected:
        return 'WiFi reconnected';
      case HealthEventType.alertFired:
        return '5-minute alert sent';
    }
  }
}
