import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/spacing.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        children: [
          SwitchListTile(
            title: const Text('Use plain RTSP'),
            subtitle: Text(
              settings.useRtsp
                  ? 'Unencrypted (port 7447) — lower CPU, may reduce crackling'
                  : 'Encrypted RTSPS + SRTP (port 7441)',
              style: theme.textTheme.bodySmall,
            ),
            value: settings.useRtsp,
            onChanged: notifier.setUseRtsp,
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Audio buffer'),
            subtitle: Text(
              '${(settings.audioBufferSeconds * 1000).round()} ms — '
              '${settings.audioBufferSeconds <= 0.2 ? 'low latency' : settings.audioBufferSeconds <= 0.5 ? 'balanced' : 'smooth'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
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
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Debug mode'),
            subtitle: Text(
              'Show stream info in camera cards',
              style: theme.textTheme.bodySmall,
            ),
            value: settings.debugMode,
            onChanged: (_) => notifier.toggleDebugMode(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Text(
              'RTSP and audio-buffer changes take effect on next stream start.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
