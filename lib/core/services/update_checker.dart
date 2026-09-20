import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/providers/auth_provider.dart' show storageProvider;
import '../logging/app_logger.dart';
import '../storage/storage_service.dart';

const _tag = 'UPDATE';

/// The public GitHub endpoint for the newest published release.
///
/// Deliberately unauthenticated: the repository is public, so a token would
/// buy nothing and would be a credential shipped inside a side-loaded APK.
const _latestReleaseUrl =
    'https://api.github.com/repos/fvoska/rtsp-mixer/releases/latest';

/// Secure-storage key holding the version the user last dismissed.
///
/// Declared here next to the code that reads and writes it, the way
/// `SettingsNotifier` owns its own storage key.
const kDismissedUpdateVersionKey = 'dismissed_update_version';

/// Whether the launch-time update check is suppressed.
///
/// True under `flutter test`, following [AppLogger.fileSinkEnabled]'s
/// precedent: no widget test may reach the public internet, and a pending
/// request would leave a live timer behind at the end of a test. Only
/// [updateCheckProvider] consults this — [UpdateChecker] itself stays
/// exercisable through its injected adapter.
final bool updateCheckDisabled =
    kIsWeb ? false : Platform.environment.containsKey('FLUTTER_TEST');

/// A published release newer than the running build.
@immutable
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.releaseUrl,
    this.apkUrl,
  });

  /// Release version with any leading `v` stripped, e.g. `1.15.0`.
  final String version;

  /// Human-readable release page (`html_url`).
  final String releaseUrl;

  /// Direct download for the Android build, when the release published one.
  final String? apkUrl;

  /// Where the Download action sends the parent.
  ///
  /// On Android that is the APK itself, so the tap lands on the installer.
  /// Everywhere else (and whenever the release carries no APK) it is the
  /// release page, which is the only thing a desktop dev build can use.
  String get downloadUrl {
    final apk = apkUrl;
    if (apk == null) return releaseUrl;
    // Guarded exactly as `lib/main.dart` guards its Android-only branch:
    // `Platform` is unavailable on web and would throw at load time.
    if (!kIsWeb && Platform.isAndroid) return apk;
    return releaseUrl;
  }

  /// Tolerant decode of one GitHub release object.
  ///
  /// The body is untrusted input as far as this app is concerned, so every
  /// field read is a type-checked cast-or-null and anything unexpected
  /// resolves to `null` rather than throwing — per CLAUDE.md a nice-to-have
  /// must never be able to surface an error.
  static AppUpdate? fromJson(Map<String, dynamic> json) {
    try {
      // Guard even though /releases/latest already excludes both: a draft or
      // pre-release must never be offered to a parent as "the new build".
      if (json['draft'] == true || json['prerelease'] == true) return null;

      final rawTag = json['tag_name'];
      if (rawTag is! String) return null;
      final version = _stripVersionPrefix(rawTag);
      if (version.isEmpty) return null;

      final releaseUrl = json['html_url'];
      if (releaseUrl is! String || releaseUrl.trim().isEmpty) return null;

      return AppUpdate(
        version: version,
        releaseUrl: releaseUrl.trim(),
        apkUrl: _firstApkAssetUrl(json['assets']),
      );
    } catch (e) {
      appLog(_tag, 'Could not parse release payload: $e');
      return null;
    }
  }

  /// `browser_download_url` of the first asset whose name ends in `.apk`.
  /// CI publishes `rtsp-mixer-<version>-android.apk`.
  static String? _firstApkAssetUrl(Object? rawAssets) {
    if (rawAssets is! List) return null;
    for (final asset in rawAssets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (!name.toLowerCase().endsWith('.apk')) continue;
      final trimmed = url.trim();
      if (trimmed.isEmpty) continue;
      return trimmed;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUpdate &&
          version == other.version &&
          releaseUrl == other.releaseUrl &&
          apkUrl == other.apkUrl;

  @override
  int get hashCode => Object.hash(version, releaseUrl, apkUrl);

  @override
  String toString() => 'AppUpdate($version)';
}

/// Drops one leading `v`/`V` and surrounding whitespace.
String _stripVersionPrefix(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
    return trimmed.substring(1).trim();
  }
  return trimmed;
}

/// Parses `1.15.0` / `v1.15` / `1.15.0+3` / `1.15.0-rc.1` into three ints.
///
/// Returns null for anything it cannot read with certainty — `latest`,
/// `1.x.0`, an empty string. A null on either side of [isNewerVersion] means
/// "no banner", which is the safe direction to fail in.
List<int>? _parseVersion(String raw) {
  var s = _stripVersionPrefix(raw);
  if (s.isEmpty) return null;

  // Build metadata (`+22`) and pre-release suffixes (`-rc.1`) carry no
  // ordering information we are willing to act on — cut at whichever comes
  // first and compare the numeric core only.
  final cut = [s.indexOf('+'), s.indexOf('-')]
      .where((i) => i >= 0)
      .fold<int>(-1, (a, b) => a < 0 ? b : (b < a ? b : a));
  if (cut >= 0) s = s.substring(0, cut);
  if (s.isEmpty) return null;

  final parts = s.split('.');
  final out = <int>[];
  for (final part in parts) {
    if (out.length == 3) break;
    final trimmed = part.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value < 0) return null;
    out.add(value);
  }
  if (out.isEmpty) return null;
  // "1.14" means 1.14.0, not "newer than 1.14.0".
  while (out.length < 3) {
    out.add(0);
  }
  return out;
}

/// Whether [latestTag] describes a build strictly newer than [currentVersion].
///
/// False whenever either side fails to parse: an unreadable tag must never
/// produce a banner.
bool isNewerVersion(String latestTag, String currentVersion) {
  final latest = _parseVersion(latestTag);
  final current = _parseVersion(currentVersion);
  if (latest == null || current == null) return false;
  for (var i = 0; i < 3; i++) {
    if (latest[i] != current[i]) return latest[i] > current[i];
  }
  return false;
}

/// Decides whether [latest] should be shown to the user.
///
/// [dismissedVersion] is stored with the same normalisation as
/// [AppUpdate.version], so a direct string compare is the whole rule: a
/// dismissal silences exactly one version, and a later release re-arms the
/// banner.
AppUpdate? selectUpdate({
  required AppUpdate? latest,
  required String currentVersion,
  required String? dismissedVersion,
}) {
  if (latest == null) return null;
  if (!isNewerVersion(latest.version, currentVersion)) return null;
  if (dismissedVersion != null && dismissedVersion.trim() == latest.version) {
    return null;
  }
  return latest;
}

/// Remembers that the user dismissed [version]'s banner.
///
/// Failures are swallowed: losing the dismissal costs one re-shown banner on
/// the next launch, which is never worth an exception escaping into a running
/// monitoring session.
Future<void> rememberDismissedUpdate(
    StorageService storage, String version) async {
  try {
    await storage.write(kDismissedUpdateVersionKey, version);
  } catch (e) {
    appLog(_tag, 'Could not remember dismissed version $version: $e');
  }
}

/// Reads the newest published release of the app's own GitHub repository.
///
/// Unauthenticated GitHub API calls are rate limited to 60/hour per IP. This
/// makes exactly one call per app launch, which stays far under that ceiling;
/// a 403 from the limiter is treated like any other failure — no banner.
class UpdateChecker {
  late Dio _dio;

  UpdateChecker() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
      // Anything below 500 comes back as a response we can inspect and
      // discard; 5xx still raises, and the catch below turns it into null.
      validateStatus: (s) => s != null && s < 500,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Roomtone',
      },
    ));
    // Deliberately NO badCertificateCallback here: unlike ProtectApiClient,
    // which talks to a LAN console with a self-signed certificate, this talks
    // to the public internet and must keep normal TLS verification. A relaxed
    // check would let a MITM choose the URL the parent is sent to.
  }

  /// Test-only: swap the transport while keeping this checker's real [Dio],
  /// so its BaseOptions and headers stay in the path. Mirrors
  /// [ProtectApiClient.setHttpClientAdapterForTest].
  @visibleForTesting
  void setHttpClientAdapterForTest(HttpClientAdapter adapter) =>
      _dio.httpClientAdapter = adapter;

  /// Returns the newest release, or null when it cannot be determined.
  ///
  /// Every failure mode — offline, rate limited, 404, a 5xx, a body that is
  /// not the JSON object we expect — resolves to null plus one log line.
  Future<AppUpdate?> fetchLatestRelease() async {
    try {
      final response = await _dio.get<dynamic>(_latestReleaseUrl);
      if (response.statusCode != 200) {
        appLog(_tag, 'Release check returned ${response.statusCode} — skipping');
        return null;
      }
      final data = response.data;
      if (data is! Map) {
        appLog(_tag, 'Release check got an unexpected body (${data.runtimeType})');
        return null;
      }
      final update = AppUpdate.fromJson(Map<String, dynamic>.from(data));
      appLog(_tag,
          update == null ? 'No usable release in response' : 'Latest release: ${update.version}');
      return update;
    } on DioException catch (e) {
      appLog(_tag, 'Release check failed: ${e.type} ${e.message}');
      return null;
    } catch (e) {
      appLog(_tag, 'Release check failed: $e');
      return null;
    }
  }
}

/// The checker instance, as a provider so widget tests can override it.
final updateCheckerProvider = Provider<UpdateChecker>((_) => UpdateChecker());

/// One update check per app launch, resolving to the release worth showing.
///
/// `keepAlive` matters: Riverpod 3 providers are auto-dispose by default, so
/// without it every rebuild that momentarily drops the last listener would
/// re-run the request. Everything is wrapped in one try/catch — per CLAUDE.md
/// this is a nice-to-have, so it degrades to "no banner" rather than
/// surfacing an error state or delaying anything.
final updateCheckProvider = FutureProvider<AppUpdate?>((ref) async {
  ref.keepAlive();
  if (updateCheckDisabled) return null;
  try {
    final currentVersion = (await PackageInfo.fromPlatform()).version;
    String? dismissed;
    try {
      dismissed = await ref.read(storageProvider).read(kDismissedUpdateVersionKey);
    } catch (e) {
      appLog(_tag, 'Could not read the dismissed version: $e');
    }
    final latest = await ref.read(updateCheckerProvider).fetchLatestRelease();
    final selected = selectUpdate(
      latest: latest,
      currentVersion: currentVersion,
      dismissedVersion: dismissed,
    );
    appLog(_tag,
        selected == null ? 'Running $currentVersion — nothing to offer' : 'Update available: ${selected.version}');
    return selected;
  } catch (e) {
    appLog(_tag, 'Update check skipped: $e');
    return null;
  }
});
