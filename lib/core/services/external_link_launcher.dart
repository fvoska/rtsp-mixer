import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_logger.dart';

const _tag = 'Links';

/// Signature of the platform call [openExternalLink] delegates to.
typedef ExternalLinkOpener = Future<bool> Function(Uri url);

/// Overridable seam so widget tests can observe launches without a platform
/// channel. Mirrors the existing test seams (`AuthNotifier
/// .backgroundValidationDelay`, `ProtectApiClient.setDioForTest`).
///
/// Reset it to [defaultExternalLinkOpener] in `tearDown`.
@visibleForTesting
ExternalLinkOpener externalLinkOpener = defaultExternalLinkOpener;

/// The real launcher: hands the URL to the OS and lets it pick a handler.
///
/// [LaunchMode.externalApplication] is deliberate — a changelog link should
/// leave the app for the browser rather than open an in-app web view, so the
/// monitoring session stays visibly in the background.
Future<bool> defaultExternalLinkOpener(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Opens [url] in the device's browser, returning whether the launch was
/// accepted.
///
/// Defensive per CLAUDE.md: this is called from tap handlers on a screen that
/// can be open while audio is streaming, so no failure mode is allowed to
/// escape. A rejected scheme, a device with no browser, or a platform channel
/// error all log and resolve to `false`.
///
/// Only `http` and `https` are launched. The changelog is a bundled asset, but
/// its link targets are still text we did not write — refusing every other
/// scheme keeps `tel:`, `intent:` and friends from reaching the platform.
Future<bool> openExternalLink(Uri url) async {
  try {
    if (!isLaunchableLink(url)) {
      appLog(_tag, 'Refusing to open non-http(s) URL: $url');
      return false;
    }
    final launched = await externalLinkOpener(url);
    if (!launched) appLog(_tag, 'Launcher declined to open $url');
    return launched;
  } catch (e) {
    appLog(_tag, 'Failed to open $url: $e');
    return false;
  }
}

/// Whether [url] is a link this app is willing to hand to the OS.
bool isLaunchableLink(Uri url) =>
    (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;

/// Opens the device's mail client to compose a message to [email].
///
/// Unlike [openExternalLink], this is not restricted to http(s): the address
/// is a fixed, developer-supplied contact detail rather than text parsed from
/// the changelog, so the scheme guard that keeps untrusted markdown from
/// reaching `tel:`/`intent:`/etc. doesn't apply here.
///
/// Defensive per CLAUDE.md: called from a tap handler on a screen that can be
/// open while audio is streaming, so no failure mode escapes — a missing mail
/// app or a platform channel error logs and resolves to `false`.
Future<bool> openMailtoLink(String email) async {
  try {
    final uri = Uri(scheme: 'mailto', path: email);
    final launched = await externalLinkOpener(uri);
    if (!launched) appLog(_tag, 'Launcher declined to open $uri');
    return launched;
  } catch (e) {
    appLog(_tag, 'Failed to open mailto for $email: $e');
    return false;
  }
}

/// Parses [raw] into a launchable [Uri], or null when it is not one.
///
/// Used by the renderer to decide whether a markdown link becomes a tappable
/// span or plain text — an unparseable target should look inert rather than
/// look tappable and then do nothing, which is the bug this replaces.
Uri? tryParseLaunchableLink(String raw) {
  try {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !isLaunchableLink(uri)) return null;
    return uri;
  } catch (_) {
    return null;
  }
}
