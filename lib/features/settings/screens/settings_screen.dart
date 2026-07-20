import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../monitoring/providers/audio_player_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final isManualMode =
        ref.watch(authNotifierProvider).value?.isManualMode ?? false;

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
          ListTile(
            title: const Text('Activity trigger'),
            subtitle: Text(
              _activityLabel(settings.activityThreshold),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Slider(
              value: settings.activityThreshold,
              min: 0.01,
              max: 0.5,
              onChanged: notifier.setActivityThreshold,
            ),
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
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              isManualMode ? 'Reset setup' : 'Sign out',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: Text(
              isManualMode
                  ? 'Remove manual cameras and return to setup.'
                  : 'Forget the saved Protect API key.',
            ),
            onTap: () => _confirmSignOut(context, ref, isManualMode),
          ),
        ],
      ),
    );
  }

  String _activityLabel(double v) {
    if (v < 0.05) return 'High sensitivity — highlight even quiet sounds';
    if (v < 0.15) return 'Medium sensitivity';
    return 'Low sensitivity — highlight only loud sounds';
  }

  Future<void> _confirmSignOut(
      BuildContext context, WidgetRef ref, bool isManualMode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isManualMode ? 'Reset setup?' : 'Sign out?'),
        content: Text(
          isManualMode
              ? 'Active monitoring will be stopped and your manually-added '
                  'cameras will be removed. You will return to the setup screen.'
              : 'Active monitoring will be stopped. You will need to re-enter '
                  'your Protect API key to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isManualMode ? 'Reset' : 'Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Stop monitoring before logout so the user doesn't end up logged out
    // with the foreground service + audio still running.
    await ref.read(audioPlayerProvider.notifier).stopMonitoringAndCleanup();
    await ref.read(authNotifierProvider.notifier).logout();
  }
}
