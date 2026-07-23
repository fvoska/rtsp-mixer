import '../../../core/models/app_error.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated }

/// How the user set the app up. [unifi] = signed in with a Protect API key;
/// [manual] = skipped Unifi login and uses manually-entered RTSP URLs only.
enum AuthMode { unifi, manual }

class AuthState {
  final AuthStatus status;
  final AuthMode mode;
  final String? host;

  /// Optional remote (VPN/Tailscale) address. In Unifi mode it's the
  /// console's remote address, tried whenever [host] (the local address) is
  /// unreachable. In manual mode it's a global fallback host: manual stream
  /// URLs are re-pointed at it as an extra playback candidate. Always null
  /// when unauthenticated.
  final String? remoteHost;
  final String? errorMessage;
  final AppErrorType? errorType;
  final bool resumeMonitoring;

  const AuthState.unauthenticated({this.errorMessage, this.errorType})
      : status = AuthStatus.unauthenticated,
        mode = AuthMode.unifi,
        host = null,
        remoteHost = null,
        resumeMonitoring = false;

  const AuthState.authenticated({
    required this.host,
    this.remoteHost,
    this.resumeMonitoring = false,
  })  : status = AuthStatus.authenticated,
        mode = AuthMode.unifi,
        errorMessage = null,
        errorType = null;

  /// Authenticated in manual-only mode: no Unifi console, no host. Cameras
  /// come entirely from manually-entered RTSP URLs. [remoteHost] optionally
  /// holds the global remote (VPN/Tailscale) fallback address.
  const AuthState.manual({this.remoteHost, this.resumeMonitoring = false})
      : status = AuthStatus.authenticated,
        mode = AuthMode.manual,
        host = null,
        errorMessage = null,
        errorType = null;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  bool get isManualMode => mode == AuthMode.manual;
}
