import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/spacing.dart';
import '../models/health_event.dart';
import '../models/session.dart';
import '../providers/session_history_provider.dart';

/// `/sessions` tab — lists the in-flight session (if any) followed by up to
/// 10 finalized sessions, most-recent first.
///
/// Per the 260514-siv plan: the in-flight row uses a 1-second periodic
/// StreamBuilder so the uptime ticks live. Finalized rows render their
/// frozen duration computed once from the events list.
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(sessionHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: asyncHistory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (history) {
          final entries = <Widget>[];
          if (history.current != null) {
            entries.add(_SessionCard(
              session: history.current!,
              isCurrent: true,
            ));
          }
          for (final s in history.past) {
            entries.add(_SessionCard(session: s, isCurrent: false));
          }
          if (entries.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
            itemBuilder: (_, i) => entries[i],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No sessions yet',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text(
              'Start monitoring from the Monitor tab — your session history will appear here.',
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.isCurrent});

  final Session session;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reconnects = session.events
        .where((e) => e.type == HealthEventType.reconnectAttempt)
        .length;
    final downtime = _totalDowntime(session.events);

    return Card.filled(
      child: InkWell(
        onTap: () => context.push('/sessions/${session.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatRange(session),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'In progress',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              if (isCurrent)
                _LiveDuration(startedAt: session.startedAt)
              else
                _MetricRow(
                  label: 'Duration',
                  value: _formatDuration(_sessionDuration(session)),
                ),
              const SizedBox(height: Spacing.xs),
              _MetricRow(
                label: 'Reconnects',
                value: '$reconnects',
              ),
              const SizedBox(height: Spacing.xs),
              _MetricRow(
                label: 'Downtime',
                value: _formatDuration(downtime),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration _sessionDuration(Session s) {
    final end = s.endedAt ?? DateTime.now();
    return end.difference(s.startedAt);
  }
}

class _LiveDuration extends StatefulWidget {
  const _LiveDuration({required this.startedAt});
  final DateTime startedAt;

  @override
  State<_LiveDuration> createState() => _LiveDurationState();
}

class _LiveDurationState extends State<_LiveDuration> {
  late final Stream<DateTime> _tick;

  @override
  void initState() {
    super.initState();
    _tick = Stream<DateTime>.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _tick,
      initialData: DateTime.now(),
      builder: (_, snap) {
        final now = snap.data ?? DateTime.now();
        final d = now.difference(widget.startedAt);
        return _MetricRow(label: 'Uptime', value: _formatDuration(d));
      },
    );
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
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Same downtime algorithm as HealthSummaryScreen._computeDowntimeByCamera,
/// but summed across cameras for the list row.
Duration _totalDowntime(List<HealthEvent> events) {
  final openFrom = <String, DateTime>{};
  var total = Duration.zero;
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
      total += e.timestamp.difference(openFrom[id]!);
      openFrom.remove(id);
    }
  }
  return total;
}

String _formatDuration(Duration d) {
  if (d == Duration.zero) return '—';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes - h * 60;
  return '${h}h ${m}m';
}

String _formatRange(Session s) {
  final start = s.startedAt;
  final end = s.endedAt;
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String ymd(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  if (end == null) {
    return '${ymd(start)} · ${hm(start)} → live';
  }
  // Same day → only show one date.
  final sameDay =
      start.year == end.year && start.month == end.month && start.day == end.day;
  if (sameDay) {
    return '${ymd(start)} · ${hm(start)} → ${hm(end)}';
  }
  return '${ymd(start)} ${hm(start)} → ${ymd(end)} ${hm(end)}';
}
