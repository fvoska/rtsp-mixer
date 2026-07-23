import 'package:flutter/material.dart';

import '../../../core/theme/spacing.dart';

/// Setup instructions reachable from both the login screen (before any
/// credentials exist) and the Settings tab (after setup). Static content
/// only — no providers, so it renders regardless of auth state.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Setup')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This app plays audio (and optional video) from cameras on '
                  'your local network. Connect a UniFi Protect console with an '
                  'API key, or add rtsp:// stream URLs from any camera brand '
                  'manually — or both.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                const _HelpSection(
                  icon: Icons.vpn_key_outlined,
                  title: 'UniFi Protect — create an API key',
                  children: [
                    _Step(1, 'Open the UniFi Protect web app: browse to your '
                        'console\'s IP address (e.g. https://192.168.1.1) and '
                        'sign in, or use unifi.ui.com.'),
                    _Step(2, 'Go to Settings → Integrations (on some versions: '
                        'Settings → Control Plane → Integrations).'),
                    _Step(3, 'Ensure the API is enabled, then choose '
                        '"Generate API Key". Give it a name like '
                        '"Baby Monitor".'),
                    _Step(4, 'Copy the key immediately — Protect shows it '
                        'only once. If you lose it, generate a new one.'),
                    _Step(5, 'In this app, enter the console\'s IP address '
                        'and paste the API key, then tap '
                        '"Connect to Console".'),
                    SizedBox(height: Spacing.sm),
                    _Note('Streaming also requires RTSP to be enabled per '
                        'camera: in Protect, select the camera → Settings → '
                        'Advanced → enable RTSP for at least one quality '
                        '(High/Medium/Low). The app picks up the stream '
                        'automatically once enabled.'),
                    _Note('The API key only works on your local network — '
                        'this app connects directly to the console, not '
                        'through UniFi\'s cloud.'),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                const _HelpSection(
                  icon: Icons.videocam_outlined,
                  title: 'Reolink — enable RTSP',
                  children: [
                    _Step(1, 'In the Reolink app or web interface, open the '
                        'camera\'s Settings → Network → Advanced → Port '
                        'Settings (in the app: tap the camera → gear icon → '
                        'Network Information / Advanced).'),
                    _Step(2, 'Enable the RTSP toggle. On most wired and WiFi '
                        'Reolink cameras it is available (often on by '
                        'default); note that most battery-powered Reolink '
                        'cameras do NOT support RTSP.'),
                    _Step(3, 'Use the camera\'s admin username and password '
                        'in the stream URL (the same credentials you use to '
                        'log into the camera).'),
                    SizedBox(height: Spacing.sm),
                    _UrlExample(
                      label: 'Main stream (high quality):',
                      url: 'rtsp://admin:PASSWORD@CAMERA_IP:554/'
                          'h264Preview_01_main',
                    ),
                    _UrlExample(
                      label: 'Sub stream (lower quality, less CPU — '
                          'recommended for audio monitoring):',
                      url: 'rtsp://admin:PASSWORD@CAMERA_IP:554/'
                          'h264Preview_01_sub',
                    ),
                    _Note('On newer firmware / H.265 models the path is '
                        '"Preview_01_main" (without the h264 prefix). If one '
                        'form fails, try the other.'),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                const _HelpSection(
                  icon: Icons.videocam_outlined,
                  title: 'TP-Link Tapo — enable RTSP',
                  children: [
                    _Step(1, 'In the Tapo app, open the camera and tap the '
                        'gear icon to open its settings.'),
                    _Step(2, 'Go to Advanced Settings → Camera Account and '
                        'create an account (username + password). This is a '
                        'separate, local account just for RTSP/ONVIF — not '
                        'your TP-Link ID.'),
                    _Step(3, 'Use that account in the stream URL below.'),
                    SizedBox(height: Spacing.sm),
                    _UrlExample(
                      label: 'Main stream (1080p or higher):',
                      url: 'rtsp://USERNAME:PASSWORD@CAMERA_IP:554/stream1',
                    ),
                    _UrlExample(
                      label: 'Sub stream (360p, less CPU — recommended for '
                          'audio monitoring):',
                      url: 'rtsp://USERNAME:PASSWORD@CAMERA_IP:554/stream2',
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                const _HelpSection(
                  icon: Icons.vpn_lock_outlined,
                  title: 'Remote access (VPN / Tailscale)',
                  children: [
                    _Note('A Remote URL is a second address for the same '
                        'console or camera, reachable over a VPN — so the '
                        'monitor keeps working when your phone is away from '
                        'the home network.'),
                    _Note('Connections always prefer the local address and '
                        'fall back to the remote one only when local is '
                        'unreachable. A connection fails only when BOTH '
                        'addresses fail, and monitoring automatically '
                        'recovers to the local stream when you are back '
                        'home.'),
                    _Note('Works with Tailscale, WireGuard, or any VPN that '
                        'makes your camera network routable from your '
                        'phone.'),
                    SizedBox(height: Spacing.sm),
                    _Step(1, 'Set up your VPN so the phone can reach the '
                        'console or camera (e.g. install Tailscale on both '
                        'ends, or enable a WireGuard tunnel on your '
                        'router).'),
                    _Step(2, 'For a UniFi console: open Settings → '
                        'Connection and set "Console remote URL" to the '
                        'console\'s VPN address (e.g. 100.64.0.9 or '
                        'nvr.tailnet.ts.net).'),
                    _Step(3, 'For a manually-added camera: enter the '
                        '"Remote URL" in the Add camera dialog, or edit it '
                        'later under Settings → Connection → Camera remote '
                        'URLs.'),
                    SizedBox(height: Spacing.sm),
                    _UrlExample(
                      label: 'Example manual-camera remote URL (Tailscale):',
                      url: 'rtsp://100.64.0.9:554/stream1',
                    ),
                    _Note('Set the app up while away from home? Enter the '
                        'VPN address first, then add the real local address '
                        'later in Settings → Connection once you are back '
                        'on your home network.'),
                    _Note('Streaming over a VPN adds latency and battery '
                        'cost compared to the local network — expect a '
                        'slightly delayed and less efficient stream while '
                        'remote.'),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                const _HelpSection(
                  icon: Icons.tips_and_updates_outlined,
                  title: 'General RTSP tips',
                  children: [
                    _Note('Find the camera\'s IP address in its app or in '
                        'your router\'s client list, and give it a DHCP '
                        'reservation (static IP) so the stream URL keeps '
                        'working after the camera reboots.'),
                    _Note('To add a stream: on the Monitor tab, choose '
                        '"Add camera" and paste the rtsp:// URL. You can '
                        'test the same URL first in VLC ("Open Network '
                        'Stream") to confirm it plays.'),
                    _Note('If your password contains special characters, '
                        'URL-encode them in the stream URL — e.g. "@" '
                        'becomes "%40", "#" becomes "%23".'),
                    _Note('The phone and the cameras must be on the same '
                        'network (or routable VLANs). This app never sends '
                        'your streams or credentials to the cloud.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card with an icon header and a list of steps/notes below it.
class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Numbered instruction line.
class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$number.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Secondary remark below the steps.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled, selectable monospace RTSP URL template the user can copy.
class _UrlExample extends StatelessWidget {
  const _UrlExample({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              url,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
