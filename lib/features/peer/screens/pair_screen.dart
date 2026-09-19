import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/spacing.dart';
import '../models/discovered_host.dart';
import '../models/pairing_payload.dart';
import '../peer_protocol.dart';
import '../providers/peer_pairing_provider.dart';
import '../services/pairing_code.dart';

/// Monitor side: find a phone running Roomtone host mode and pair with it.
/// Three ways in, all landing in [PeerPairingNotifier.pair]:
///  1. tap a host found by LAN discovery and type its code,
///  2. scan the host's QR (address + code in one go),
///  3. type the host's address and code by hand.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(peerPairingProvider.notifier).startScan();
    });
  }

  Future<void> _scanQr() async {
    final payload = await context.push<PairingPayload?>('/pair/scan');
    if (payload == null || !mounted) return;
    await ref.read(peerPairingProvider.notifier).pairWithPayload(payload);
  }

  Future<void> _pairWithHost(DiscoveredHost host) async {
    if (host.protocol != kPeerProtocolVersion) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That phone runs a different Roomtone version.'),
      ));
      return;
    }
    final code = await _askCode(context, host.name);
    if (code == null || !mounted) return;
    await ref.read(peerPairingProvider.notifier).pair(
          address: host.address,
          port: host.port,
          code: code,
          hostName: host.name,
          hostId: host.hostId,
        );
  }

  Future<void> _pairManually() async {
    final result = await showDialog<({String address, int port, String code})>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    if (result == null || !mounted) return;
    await ref.read(peerPairingProvider.notifier).pair(
          address: result.address,
          port: result.port,
          code: result.code,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(peerPairingProvider);

    // Pop back to the picker once paired; the camera is already selected.
    ref.listen(peerPairingProvider.select((s) => s.pairedCameraId),
        (prev, next) {
      if (next != null && prev == null && mounted) {
        final name = ref.read(peerPairingProvider).pairedHostName ?? 'phone';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paired with "$name" — ready to monitor.')),
        );
        // Normally pushed from the picker; a deep link (`go`) has no stack.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/monitoring');
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Add phone camera')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'On the other phone, open Roomtone → "Phone as camera" and '
                  'start sharing. It will show up below on the same Wi‑Fi.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: state.pairing ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Phones on your network',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (state.scanning)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                if (state.hosts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                    child: Text(
                      state.scanning
                          ? 'Looking for phones sharing their microphone…'
                          : 'Auto-discovery is unavailable on this network. '
                              'Scan the QR or enter the address manually.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Card.filled(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final host in state.hosts)
                          ListTile(
                            leading: const Icon(Icons.phone_android),
                            title: Text(host.name),
                            subtitle: Text(
                              '${host.address}:${host.port}',
                              style: AppTypography.tabular(
                                  theme.textTheme.bodySmall),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: !state.pairing,
                            onTap: () => _pairWithHost(host),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                OutlinedButton.icon(
                  onPressed: state.pairing ? null : _pairManually,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Enter address and code manually'),
                ),
                if (state.pairing) ...[
                  const SizedBox(height: Spacing.lg),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: Spacing.sm),
                  const Center(child: Text('Pairing…')),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: Spacing.lg),
                  Container(
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(Radii.inner),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => ref
                              .read(peerPairingProvider.notifier)
                              .clearError(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ask for the 6-digit code shown on [hostName]. Returns null on cancel.
Future<String?> _askCode(BuildContext context, String hostName) =>
    showDialog<String>(
      context: context,
      builder: (_) => _CodeDialog(hostName: hostName),
    );

/// Owns its controller so the dialog's exit animation never rebuilds a
/// text field against a disposed controller.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.hostName});
  final String hostName;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(normalizePairingCode(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pair with ${widget.hostName}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTypography.mono,
            fontSize: 24,
            letterSpacing: 4,
          ),
          decoration: const InputDecoration(
            hintText: '123 456',
            helperText: 'The 6-digit code on the host phone\'s screen.',
            border: OutlineInputBorder(),
          ),
          validator: _validateCode,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pair')),
      ],
    );
  }
}

String? _validateCode(String? v) =>
    normalizePairingCode(v ?? '').length == kPairingCodeLength
        ? null
        : 'Enter the 6-digit code';

class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '$kPeerPreferredHttpPort');
  final _code = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      address: _address.text.trim(),
      port: int.parse(_port.text.trim()),
      code: normalizePairingCode(_code.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair by address'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _address,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Host phone address',
                  hintText: '192.168.1.20',
                  helperText: 'Shown on the host phone under the QR code.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final p = int.tryParse((v ?? '').trim());
                  return (p == null || p <= 0 || p > 65535)
                      ? 'Enter a port (1–65535)'
                      : null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pairing code',
                  hintText: '123 456',
                  border: OutlineInputBorder(),
                ),
                validator: _validateCode,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pair')),
      ],
    );
  }
}
