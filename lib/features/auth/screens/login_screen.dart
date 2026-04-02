import 'package:flutter/material.dart';

import '../../../core/models/app_error.dart';
import '../../../core/theme/spacing.dart';

/// Login screen with Console IP, Username, and Password fields (D-01).
///
/// Displays inline errors under relevant fields (D-03).
/// Shows SSL certificate warning dialog on first connection (D-02).
class LoginScreen extends StatefulWidget {
  /// Callback invoked when the user taps Connect.
  /// Receives host, username, password, and whether self-signed certs are accepted.
  /// Should return null on success, or an [AppError] on failure.
  ///
  /// TODO: Wire to Riverpod auth provider in Plan 03.
  final Future<AppError?> Function(
    String host,
    String username,
    String password, {
    required bool acceptSelfSigned,
  })? onConnect;

  const LoginScreen({super.key, this.onConnect});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isAuthenticating = false;
  bool _hasAcceptedCert = false;

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
  void _setServerError(AppError error) {
    setState(() {
      switch (error.type) {
        case AppErrorType.connectionRefused:
          _hostError =
              'Could not reach the console. Check the IP address and make sure you are on the same network.';
        case AppErrorType.invalidCredentials:
          _passwordError = 'Invalid username or password.';
        case AppErrorType.sslRejected:
          _hostError =
              'Connection cancelled. The console uses a certificate that was not trusted.';
        case AppErrorType.timeout:
          _hostError = 'Connection timed out. Please try again.';
        case AppErrorType.unknown:
          _hostError = error.message;
      }
    });
  }

  Future<void> _handleConnect() async {
    _clearServerErrors();

    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Show SSL certificate dialog if not yet accepted (D-02)
    if (!_hasAcceptedCert) {
      final accepted = await _showCertificateDialog(host);
      if (!accepted) return;
      _hasAcceptedCert = true;
    }

    setState(() => _isAuthenticating = true);

    try {
      final error = await widget.onConnect?.call(
        host,
        username,
        password,
        acceptSelfSigned: _hasAcceptedCert,
      );

      if (error != null) {
        _setServerError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
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
                      onPressed: _isAuthenticating ? null : _handleConnect,
                      child: _isAuthenticating
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
