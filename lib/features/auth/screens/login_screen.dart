import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_error.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../cameras/providers/camera_provider.dart';
import '../providers/auth_provider.dart';

/// Login screen with Console IP, Username, and Password fields (D-01).
///
/// Displays inline errors under relevant fields (D-03).
/// Shows SSL certificate warning dialog on first connection (D-02).
/// Wired to [authNotifierProvider] for authentication state management.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;

  // Server error state for inline display (D-03)
  String? _hostError;
  String? _passwordError;

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    setState(() {
      _hostError = null;
      _passwordError = null;
    });
  }

  /// Map server errors to the relevant field (D-03).
  void _setServerError(AppErrorType? errorType, String? message) {
    if (errorType == null && message == null) return;
    setState(() {
      switch (errorType) {
        case AppErrorType.connectionRefused:
          _hostError = message ??
              'Could not reach the console. Check the IP address and make sure you are on the same network.';
        case AppErrorType.invalidCredentials:
          _passwordError = message ?? 'Invalid username or password.';
        case AppErrorType.sslRejected:
          _hostError = message ??
              'Connection cancelled. The console uses a certificate that was not trusted.';
        case AppErrorType.timeout:
          _hostError = message ?? 'Connection timed out. Please try again.';
        case AppErrorType.unknown:
        case null:
          _hostError = message;
      }
    });
  }

  Future<void> _handleConnect() async {
    _clearServerErrors();

    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Check SSL acceptance (D-02)
    final storage = ref.read(secureStorageProvider);
    final sslAccepted = await storage.loadSslAccepted(host);

    if (!sslAccepted) {
      final accepted = await _showCertificateDialog(host);
      if (!accepted) return;
      await storage.saveSslAccepted(host, true);
    }

    // Perform login via auth provider
    final notifier = ref.read(authNotifierProvider.notifier);
    await notifier.login(host, username, password);

    // Check result and handle errors
    if (!mounted) return;
    final authState = ref.read(authNotifierProvider);
    if (authState.value?.isAuthenticated == true) {
      // Login succeeded -- load cameras so the list is ready
      final authHost = authState.value?.host;
      if (authHost != null) {
        ref.read(cameraNotifierProvider.notifier).loadCameras(authHost);
      }
    } else if (authState.value?.errorMessage != null) {
      _setServerError(
        authState.value?.errorType,
        authState.value?.errorMessage,
      );
    }
  }

  /// SSL certificate warning dialog (D-02).
  Future<bool> _showCertificateDialog(String host) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Untrusted Certificate'),
            content: Text(
              'The Protect console at $host uses a self-signed certificate. '
              'This is normal for local Unifi consoles.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Trust This Console'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isAuthenticating = authState.isLoading;

    // Show auto-connect error banner if present
    final autoConnectError = authState.value?.errorMessage;

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Connect to Protect',
                    style: theme.textTheme.headlineMedium,
                  ),
                  if (autoConnectError != null && _hostError == null && _passwordError == null) ...[
                    const SizedBox(height: Spacing.md),
                    Container(
                      padding: const EdgeInsets.all(Spacing.md),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        autoConnectError,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Spacing.xl),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _hostController,
                          decoration: InputDecoration(
                            labelText: 'Console IP Address',
                            hintText: '192.168.1.1',
                            border: const OutlineInputBorder(),
                            errorText: _hostError,
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Console IP address is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: Spacing.md),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: Spacing.md),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            errorText: _passwordError,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                          obscureText: !_isPasswordVisible,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleConnect(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: isAuthenticating ? null : _handleConnect,
                      child: isAuthenticating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Connect to Console'),
                    ),
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
