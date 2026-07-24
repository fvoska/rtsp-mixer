import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../auth/models/auth_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../../cameras/models/protect_camera.dart';
import '../../cameras/providers/camera_provider.dart';
import '../../monitoring/providers/audio_player_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider).value;
    final isManualMode = authState?.isManualMode ?? false;
    final isUnifiMode = authState != null &&
        authState.isAuthenticated &&
        authState.mode == AuthMode.unifi;
    final manualCameras = (ref.watch(cameraNotifierProvider).value?.cameras ??
            const <ProtectCamera>[])
        .where((c) => c.isManual)
        .toList();
    final showConnectionSection = isUnifiMode || manualCameras.isNotEmpty;

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
          if (showConnectionSection) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                0,
              ),
              child: Text(
                'Connection',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (isUnifiMode)
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: const Text('Console local address'),
                subtitle: Text(
                  authState.host ?? 'Not set',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () => _editLocalHost(context, ref, authState.host),
              ),
            // Global remote address — in Unifi mode it's the console's
            // remote URL; in manual mode it rehosts every camera's stream
            // URL as a fallback candidate (NVR-style setups).
            ListTile(
              leading: const Icon(Icons.vpn_lock_outlined),
              title: Text(
                isUnifiMode ? 'Console remote URL' : 'Remote address',
              ),
              subtitle: Text(
                authState?.remoteHost ?? 'Not set',
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => _editRemoteHost(
                context,
                ref,
                authState?.remoteHost,
                isUnifiMode: isUnifiMode,
              ),
            ),
            if (manualCameras.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  0,
                ),
                child: Text(
                  'Camera remote URLs',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final camera in manualCameras)
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(camera.name ?? 'Unnamed Camera'),
                  subtitle: Text(
                    camera.remoteUrl ?? 'Not set',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () => _editCameraRemoteUrl(context, ref, camera),
                ),
            ],
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & setup guides'),
            subtitle: const Text(
              'UniFi API keys, RTSP for Reolink, Tapo, and more.',
            ),
            onTap: () => context.push('/help'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Version, changelog, licenses, and credits.'),
            onTap: () => context.push('/about'),
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

  // The threshold gates the card-border highlight on recent VARIATION in
  // sound level (how much the level swung over the last few seconds), not
  // on absolute loudness.
  String _activityLabel(double v) {
    if (v < 0.05) return 'High sensitivity — highlight even small changes in sound level';
    if (v < 0.15) return 'Medium sensitivity — highlight moderate changes in sound level';
    return 'Low sensitivity — highlight only large swings, like crying';
  }

  Future<void> _editLocalHost(
      BuildContext context, WidgetRef ref, String? current) async {
    final result = await _showEditAddressDialog(
      context,
      title: 'Console local address',
      initialValue: current,
      hint: '192.168.1.1',
      helperText: 'IP or hostname of the console on your home network.',
      validator: (v) => v.trim().isEmpty ? 'Required' : null,
    );
    if (result == null || result.value == null) return;
    await ref.read(authNotifierProvider.notifier).updateLocalHost(result.value!);
  }

  Future<void> _editRemoteHost(
    BuildContext context,
    WidgetRef ref,
    String? current, {
    required bool isUnifiMode,
  }) async {
    final result = await _showEditAddressDialog(
      context,
      title: isUnifiMode ? 'Console remote URL' : 'Remote address',
      initialValue: current,
      hint: '100.64.0.9 or nvr.tailnet.ts.net',
      helperText: isUnifiMode
          ? 'VPN/Tailscale address tried when the local address is '
              'unreachable. Leave empty or Clear to remove.'
          : 'VPN/Tailscale address of the NVR/host serving your streams. '
              'Camera URLs are re-pointed at it when the local address is '
              'unreachable. Leave empty or Clear to remove.',
      allowClear: true,
    );
    if (result == null) return;
    await ref.read(authNotifierProvider.notifier).updateRemoteHost(result.value);
  }

  Future<void> _editCameraRemoteUrl(
      BuildContext context, WidgetRef ref, ProtectCamera camera) async {
    final result = await _showEditAddressDialog(
      context,
      title: '${camera.name ?? 'Camera'} remote URL',
      initialValue: camera.remoteUrl,
      hint: 'rtsp://100.64.0.9:554/stream',
      helperText: 'VPN/Tailscale stream URL tried when the primary URL is '
          'unreachable. Leave empty or Clear to remove.',
      allowClear: true,
      validator: (v) {
        final value = v.trim();
        if (value.isEmpty) return null; // empty = clear
        final uri = Uri.tryParse(value);
        if (uri == null ||
            (uri.scheme != 'rtsp' && uri.scheme != 'rtsps') ||
            uri.host.isEmpty) {
          return 'Enter a valid rtsp:// or rtsps:// URL';
        }
        return null;
      },
    );
    if (result == null) return;
    // Empty string clears remoteUrl (see updateManualCamera semantics).
    await ref
        .read(cameraNotifierProvider.notifier)
        .updateManualCamera(camera.id, remoteUrl: result.value ?? '');
  }

  /// Single-field edit dialog. Returns:
  /// - null when cancelled
  /// - (value: non-empty string) when saved
  /// - (value: null) when cleared (or saved empty with [allowClear])
  Future<({String? value})?> _showEditAddressDialog(
    BuildContext context, {
    required String title,
    String? initialValue,
    String? hint,
    String? helperText,
    bool allowClear = false,
    String? Function(String value)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final formKey = GlobalKey<FormState>();
    try {
      return await showDialog<({String? value})>(
        context: context,
        builder: (ctx) {
          void save() {
            if (formKey.currentState!.validate()) {
              final text = controller.text.trim();
              Navigator.of(ctx).pop((value: text.isEmpty ? null : text));
            }
          }

          return AlertDialog(
            title: Text(title),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hint,
                  helperText: helperText,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                autocorrect: false,
                validator:
                    validator == null ? null : (v) => validator(v ?? ''),
                onFieldSubmitted: (_) => save(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              if (allowClear)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop((value: null)),
                  child: const Text('Clear'),
                ),
              FilledButton(
                onPressed: save,
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
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
