import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/status_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../helpers/session_status.dart';
import '../helpers/uptime_format.dart';
import '../providers/audio_player_provider.dart';
import '../providers/session_history_provider.dart';

/// Mini-bar shown above the bottom NavigationBar while monitoring is active
/// and the user is NOT on the Monitor tab. Reassures the parent that audio
/// is still live and offers a one-tap return to the Monitor screen.
///
/// Visibility rule (260514-siv):
///   - hidden if no current session
///   - hidden when [selectedIndex] == 0 (already on Monitor)
///   - otherwise shown
///
/// The reassuring "Monitoring · uptime" copy is reserved for
/// [SessionStatus.playing]. When a camera is connecting, reconnecting or
/// failed the bar names that state instead — the parent must not be told audio
/// is flowing while it isn't.
class ActiveSessionBar extends ConsumerStatefulWidget {
  const ActiveSessionBar({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  ConsumerState<ActiveSessionBar> createState() => _ActiveSessionBarState();
}

class _ActiveSessionBarState extends ConsumerState<ActiveSessionBar> {
  Timer? _tick;
  bool _pulseHi = true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _pulseHi = !_pulseHi;
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(sessionHistoryProvider).value;
    final authState = ref.watch(authNotifierProvider).value;
    final session = history?.current;
    final resuming = (authState?.resumeMonitoring ?? false) && session == null;
    // Hide on Monitor tab (inline banner takes over there) and when no session
    // is in flight and no resume is pending.
    if (widget.selectedIndex == 0) {
      return const SizedBox.shrink();
    }
    if (session == null && !resuming) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final startedAt = session?.startedAt ?? DateTime.now();
    final uptime = DateTime.now().difference(startedAt);
    final formatted = session == null ? 'resuming…' : formatUptime(uptime);

    // While a session is in flight the bar tracks stream health, not just the
    // clock: only an all-live mix earns "Monitoring · uptime". A pending
    // resume has no player state yet, so it keeps its own "resuming…" copy.
    final status = session == null
        ? SessionStatus.connecting
        : resolveSessionStatus(ref.watch(audioPlayerProvider));
    final healthy = session == null || status.isHealthy;
    final dotColor = sessionStatusColor(status, context.statusColors);

    final semanticsLabel = session == null
        ? 'Resuming monitoring'
        : healthy
            ? 'Return to monitoring, uptime $formatted'
            : 'Return to monitoring, ${sessionStatusLabel(status)}';

    return Semantics(
      label: semanticsLabel,
      button: true,
      container: true,
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: InkWell(
          onTap: () => context.go('/monitoring'),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                children: [
                  AnimatedOpacity(
                    opacity: _pulseHi ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 800),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    // The duration ticks every second, so it renders in the
                    // tabular-figure numeric face while the word stays in the
                    // UI face. Same string, same formatting logic — only the
                    // span it sits in changed.
                    child: Text.rich(
                      healthy
                          ? TextSpan(
                              text: 'Monitoring · ',
                              children: [
                                TextSpan(
                                  text: formatted,
                                  style: AppTypography.tabular(
                                    theme.textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            )
                          // No uptime next to a degraded state: "Reconnecting…
                          // · 6h 12m" reads as six hours of reconnecting.
                          : TextSpan(text: sessionStatusLabel(status)),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: healthy
                            ? theme.colorScheme.onSecondaryContainer
                            : dotColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_less,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
