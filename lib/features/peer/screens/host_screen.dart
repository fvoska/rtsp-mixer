import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/status_colors.dart';
import '../models/battery_status.dart';
import '../models/paired_client.dart';
import '../models/pairing_payload.dart';
import '../models/peer_host_state.dart';
import '../providers/peer_host_provider.dart';
import '../services/pairing_code.dart';
import '../widgets/battery_icon.dart';
import '../widgets/pairing_qr.dart';

/// "Use this phone as a camera." Reachable before any login (an old phone
/// in the nursery needs no UniFi console) and from Settings.
class HostScreen extends ConsumerWidget {
  const HostScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    // Same overnight prerequisites as monitoring: a notification channel
    // for the foreground service and an exemption from battery optimisation.
    // Idempotent on the platform side; skipped off-Android.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final perm = await FlutterForegroundTask.checkNotificationPermission();
        if (perm != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      } catch (e) {
        appLog('PEER_HOST', 'Permission prompts failed (continuing): $e');
      }
    }
    await ref.read(peerHostProvider.notifier).start();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(peerHostProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(peerHostProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Phone as camera')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Share this phone\'s microphone on your Wi‑Fi so another '
                  'phone running Roomtone can listen to this room. Pair once '
                  'with the code or QR below; it reconnects on its own after '
                  'that.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                _NameTile(state: state, onRename: notifier.setName),
                const SizedBox(height: Spacing.md),
                _StartStopButton(
                  state: state,
                  onStart: () => _start(context, ref),
                  onStop: notifier.stop,
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: Spacing.md),
                  _ErrorBanner(message: state.errorMessage!),
                ],
                if (state.isRunning) ...[
                  const SizedBox(height: Spacing.lg),
                  _PairingCard(state: state, onNewCode: notifier.regenerateCode),
                  const SizedBox(height: Spacing.md),
                  _LiveCard(state: state),
                ],
                const SizedBox(height: Spacing.lg),
                _PairedDevices(
                  clients: state.pairedClients,
                  onRevoke: notifier.revoke,
                ),
                const SizedBox(height: Spacing.lg),
                _Tips(theme: theme),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NameTile extends StatelessWidget {
  const _NameTile({required this.state, required this.onRename});

  final PeerHostState state;
  final Future<void> Function(String) onRename;

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: state.name);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Camera name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(
              hintText: 'Nursery',
              helperText: 'Shown on the monitoring phone.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result != null && result.trim().isNotEmpty) {
        await onRename(result);
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.phone_android),
        title: Text(state.name),
        subtitle: const Text('Camera name'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: state.loaded ? () => _edit(context) : null,
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({
    required this.state,
    required this.onStart,
    required this.onStop,
  });

  final PeerHostState state;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.isBusy || !state.loaded) {
      return const SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: null,
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.isRunning) {
      return SizedBox(
        height: 52,
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop sharing'),
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.mic),
        label: const Text('Start sharing microphone'),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(Radii.inner),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.state, required this.onNewCode});

  final PeerHostState state;
  final VoidCallback onNewCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = state.primaryAddress;
    final port = state.port;
    final payload = (address != null && port != null)
        ? PairingPayload(
            hostId: state.hostId,
            hostName: state.name,
            address: address,
            port: port,
            code: state.code,
          )
        : null;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          children: [
            Text('Pairing code', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Text(
              formatPairingCode(state.code),
              style: theme.textTheme.displayMedium?.copyWith(
                fontFamily: AppTypography.mono,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'On the other phone: Monitor → Add → Phone camera, pick this '
              'phone and type the code — or scan the QR.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (payload != null)
              PairingQr(payload: payload)
            else
              Text(
                'No Wi‑Fi address found yet — connect this phone to your '
                'home network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              alignment: WrapAlignment.center,
              children: [
                for (final a in state.addresses)
                  Chip(
                    avatar: const Icon(Icons.lan_outlined, size: 16),
                    label: Text(
                      '$a:${state.port}',
                      style: AppTypography.tabular(theme.textTheme.labelMedium),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextButton.icon(
              onPressed: onNewCode,
              icon: const Icon(Icons.refresh),
              label: const Text('New code'),
            ),
            if (state.lastPairingNote != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                state.lastPairingNote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.state});
  final PeerHostState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final listeners = state.listeners;
    final listenerCopy = switch (listeners) {
      0 => 'No monitor connected yet',
      1 => '1 monitor listening',
      _ => '$listeners monitors listening',
    };
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.micActive ? status.live : status.reconnecting,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    state.micActive
                        ? 'Microphone live'
                        : 'Microphone restarting…',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Icon(
                  listeners > 0 ? Icons.hearing : Icons.hearing_disabled,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    listenerCopy,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (state.battery != null) ...[
              const SizedBox(height: Spacing.xs),
              _BatteryLine(battery: state.battery!),
            ],
            const SizedBox(height: Spacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.control),
              child: LinearProgressIndicator(
                value: state.level.clamp(0.0, 1.0),
                minHeight: 10,
                color: status.live,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (!state.discoveryActive) ...[
              const SizedBox(height: Spacing.md),
              Text(
                'Auto-discovery is unavailable on this network — the other '
                'phone can still scan the QR or enter the address above.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// "Battery 73% · charging" on the host's own screen — the same reading
/// monitors see, so the parent can check it from either phone.
class _BatteryLine extends StatelessWidget {
  const _BatteryLine({required this.battery});
  final BatteryStatus battery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final Color? color = battery.isCritical
        ? status.offline
        : battery.isLow
            ? status.warning
            : null;
    final text = battery.isLow
        ? 'Battery ${battery.percent}% and not charging — plug this phone in'
        : 'Battery ${battery.label}';
    return Row(
      children: [
        Icon(
          batteryIcon(battery),
          size: 18,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PairedDevices extends StatelessWidget {
  const _PairedDevices({required this.clients, required this.onRevoke});

  final List<PairedClient> clients;
  final Future<void> Function(String id) onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paired monitors',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (clients.isEmpty)
          Text(
            'No phone has paired yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Card.filled(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final c in clients)
                  ListTile(
                    leading: const Icon(Icons.smartphone),
                    title: Text(c.name),
                    subtitle: Text(_pairedAtLabel(c.pairedAt)),
                    trailing: IconButton(
                      icon: Icon(Icons.link_off, color: theme.colorScheme.error),
                      tooltip: 'Unpair',
                      onPressed: () => onRevoke(c.id),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _pairedAtLabel(DateTime t) {
    if (t.millisecondsSinceEpoch == 0) return 'Paired';
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Paired ${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Tips extends StatelessWidget {
  const _Tips({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overnight tips', style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        )),
        const SizedBox(height: Spacing.sm),
        Text('• Keep this phone plugged in and on the same Wi‑Fi as the '
            'monitoring phone.', style: style),
        Text('• Sharing keeps running with the screen off — a notification '
            'shows while it does.', style: style),
        Text('• Give this phone a fixed IP in your router if you can; the '
            'monitor finds it again either way.', style: style),
      ],
    );
  }
}
