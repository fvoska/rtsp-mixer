import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_error.dart';
import '../../../core/theme/spacing.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: '192.168.1.1');
  final _apiKeyController = TextEditingController();
  String? _hostError;
  String? _apiKeyError;

  @override
  void dispose() {
    _hostController.dispose();
    _apiKeyController.dispose();
    AppLogger.instance.removeListener(_onLog);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    AppLogger.instance.addListener(_onLog);
  }

  void _onLog() {
    if (mounted) setState(() {});
  }

  void _setError(AppErrorType? type, String? msg) {
    setState(() {
      _hostError = null;
      _apiKeyError = null;
      switch (type) {
        case AppErrorType.connectionRefused || AppErrorType.timeout:
          _hostError = msg;
        case AppErrorType.invalidCredentials:
          _apiKeyError = msg;
        default:
          _hostError = msg;
      }
    });
  }

  Future<void> _handleConnect() async {
    setState(() { _hostError = null; _apiKeyError = null; });
    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    appLog('UI', 'Connect pressed: host=$host key=${apiKey.length}chars');

    final notifier = ref.read(authNotifierProvider.notifier);
    await notifier.login(host, apiKey);

    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    if (authState.value?.isAuthenticated == true) {
      appLog('UI', 'Authenticated — router will load cameras');
      // Camera loading is triggered by the router redirect on auth state change
    } else if (authState.value?.errorMessage != null) {
      _setError(authState.value?.errorType, authState.value?.errorMessage);
    }
  }

  Future<void> _handleSkip() async {
    appLog('UI', 'Skip UniFi pressed — manual RTSP setup');
    await ref.read(authNotifierProvider.notifier).skipUnifi();
    // Router redirect on auth-state change lands the user in /monitoring.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
    final logs = AppLogger.instance.lines;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Connect to Protect', style: theme.textTheme.headlineMedium),
                const SizedBox(height: Spacing.xl),
                Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: 'Console IP Address',
                        hintText: '192.168.1.1',
                        border: const OutlineInputBorder(),
                        errorText: _hostError,
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: Spacing.md),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'Paste your Protect API key',
                        border: const OutlineInputBorder(),
                        errorText: _apiKeyError,
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleConnect(),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ]),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Create an API key in Protect → Settings → Integrations',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xl),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: isLoading ? null : _handleConnect,
                    child: isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Connect to Console'),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md),
                      child: Text(
                        'or',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _handleSkip,
                    icon: const Icon(Icons.link),
                    label: const Text('Skip — add RTSP URLs manually'),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'No UniFi console? Enter camera RTSP stream URLs yourself. '
                  'You can add UniFi later by signing out.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (logs.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xl),
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        logs.join('\n'),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
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
