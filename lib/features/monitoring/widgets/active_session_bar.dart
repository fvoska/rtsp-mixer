import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spacing.dart';
import '../providers/session_history_provider.dart';

/// Mini-bar shown above the bottom NavigationBar while monitoring is active
/// and the user is NOT on the Monitor tab. Reassures the parent that audio
/// is still live and offers a one-tap return to the Monitor screen.
///
/// Visibility rule (260514-siv):
///   - hidden if no current session
///   - hidden when [selectedIndex] == 0 (already on Monitor)
///   - otherwise shown
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
    final session = history?.current;
    if (session == null || widget.selectedIndex == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final uptime = DateTime.now().difference(session.startedAt);
    final formatted = _formatUptime(uptime);
    final semanticsLabel = 'Return to monitoring, uptime $formatted';

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
                      decoration: const BoxDecoration(
                        color: AppTheme.statusOnline,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Monitoring · $formatted',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
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

  /// Same xs / Mm / Hh Mm format used by HealthSummaryScreen's uptime card.
  String _formatUptime(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes - h * 60;
    return '${h}h ${m}m';
  }
}
