import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../router/app_router.dart';

/// A floating action button available on all screens that opens the debug/settings panel.
class DebugOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  ConsumerState<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends ConsumerState<DebugOverlay> {
  bool _sheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (!_sheetOpen)
            Positioned(
              right: 12,
              bottom: 100,
              child: Material(
                type: MaterialType.transparency,
                child: FloatingActionButton.small(
                  heroTag: 'debug_overlay',
                  backgroundColor: settings.debugMode
                      ? const Color(0xFF4DB6AC)
                      : const Color(0xFF2C2C2C),
                  foregroundColor: settings.debugMode
                      ? Colors.black
                      : Colors.white70,
                  onPressed: _showSettingsSheet,
                  child: const Icon(Icons.settings, size: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
    final router = ref.read(appRouterProvider);
    final navContext = router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;

    setState(() => _sheetOpen = true);
    showModalBottomSheet(
      context: navContext,
      builder: (_) => const _SettingsSheet(),
    ).whenComplete(() {
      if (mounted) setState(() => _sheetOpen = false);
    });
  }
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Use plain RTSP'),
              subtitle: Text(
                settings.useRtsp
                    ? 'Unencrypted (port 7447) — lower CPU, may reduce crackling'
                    : 'Encrypted RTSPS + SRTP (port 7441)',
                style: theme.textTheme.bodySmall,
              ),
              value: settings.useRtsp,
              onChanged: (v) => notifier.setUseRtsp(v),
            ),
            const Divider(),
            ListTile(
              title: const Text('Audio buffer'),
              subtitle: Text(
                '${(settings.audioBufferSeconds * 1000).round()} ms — '
                '${settings.audioBufferSeconds <= 0.2 ? 'low latency' : settings.audioBufferSeconds <= 0.5 ? 'balanced' : 'smooth'}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: SizedBox(
                width: 180,
                child: Slider(
                  value: settings.audioBufferSeconds,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  label: '${(settings.audioBufferSeconds * 1000).round()} ms',
                  onChanged: (v) => notifier.setAudioBufferSeconds(
                    (v * 100).round() / 100.0,
                  ),
                ),
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Debug mode'),
              subtitle: Text(
                'Show stream info in camera cards',
                style: theme.textTheme.bodySmall,
              ),
              value: settings.debugMode,
              onChanged: (_) => notifier.toggleDebugMode(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.terminal, size: 18),
                label: const Text('View logs'),
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(appRouterProvider).push('/logs');
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'RTSP/buffer changes take effect on next stream start.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
