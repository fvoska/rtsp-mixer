import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

/// Persistent encrypted storage using platform keystore/keychain.
/// - Android: EncryptedSharedPreferences (backed by Android Keystore)
/// - iOS/macOS: Keychain Services
///
/// Falls back to in-memory storage if keychain/keystore is unavailable
/// (e.g. unsigned macOS builds during development).
class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _installMarkerFilename = '.install_marker';
  final Map<String, String> _fallback = {};
  bool _useFallback = false;

  /// Single-flight guard for the fresh-install check so concurrent callers
  /// share one wipe attempt and we never re-wipe within a process.
  Future<void>? _freshInstallCheck;

  /// Wipe secure storage if no install-marker file exists in the app data
  /// directory. On macOS/iOS, Keychain entries (credentials, was_monitoring,
  /// cached/selected cameras) survive app uninstall — without this check, a
  /// reinstall inherits the previous install's state and the app
  /// auto-resumes into a stale session. The app documents directory IS
  /// wiped on uninstall, so the marker's absence is a reliable
  /// "first launch after fresh install" signal.
  ///
  /// Safe to call multiple times — only the first call does any work.
  /// Failures are logged and swallowed (degrade to "leave Keychain alone")
  /// so we never block app startup on a path_provider hiccup.
  Future<void> ensureFreshInstallChecked() {
    return _freshInstallCheck ??= _runFreshInstallCheck();
  }

  Future<void> _runFreshInstallCheck() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final marker = File(
        '${dir.path}${Platform.pathSeparator}$_installMarkerFilename',
      );
      if (await marker.exists()) return;

      appLog('STORAGE',
          'install marker missing — wiping stale secure storage (likely reinstall)');
      await deleteAll();

      await marker.create(recursive: true);
      await marker.writeAsString(
        DateTime.now().toIso8601String(),
        flush: true,
      );
    } catch (e) {
      appLog('STORAGE', 'Fresh-install check failed (continuing): $e');
    }
  }

  Future<void> write(String key, String value) async {
    if (_useFallback) {
      _fallback[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      appLog('STORAGE', 'Secure write failed, switching to in-memory fallback: $e');
      _useFallback = true;
      _fallback[key] = value;
    }
  }

  Future<String?> read(String key) async {
    if (_useFallback) return _fallback[key];
    try {
      return await _storage.read(key: key);
    } catch (e) {
      appLog('STORAGE', 'Secure read failed, switching to in-memory fallback: $e');
      _useFallback = true;
      return _fallback[key];
    }
  }

  Future<void> delete(String key) async {
    if (_useFallback) {
      _fallback.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _useFallback = true;
      _fallback.remove(key);
    }
  }

  Future<void> deleteAll() async {
    if (_useFallback) {
      _fallback.clear();
      return;
    }
    try {
      await _storage.deleteAll();
    } catch (e) {
      _useFallback = true;
      _fallback.clear();
    }
  }

  Future<void> saveCredentials(String host, String apiKey) async {
    await write('host', host);
    await write('api_key', apiKey);
  }

  Future<({String host, String apiKey})?> loadCredentials() async {
    final host = await read('host');
    final apiKey = await read('api_key');
    if (host == null || apiKey == null) return null;
    return (host: host, apiKey: apiKey);
  }

  Future<void> clearAll() async => deleteAll();

  /// Optional remote (VPN/Tailscale) address for the Unifi console. `host`
  /// (saved via [saveCredentials]) remains the local/primary address; this is
  /// only tried as a fallback when the local address is unreachable.
  Future<void> saveRemoteHost(String host) async {
    await write('remote_host', host);
  }

  Future<String?> loadRemoteHost() async => read('remote_host');

  Future<void> deleteRemoteHost() async => delete('remote_host');

  Future<void> saveSelectedCameraIds(List<String> ids) async {
    await write('selected_cameras', jsonEncode(ids));
  }

  Future<List<String>> loadSelectedCameraIds() async {
    final raw = await read('selected_cameras');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  /// Manually-entered RTSP cameras. Persisted independently of the Unifi
  /// camera cache so they survive across Unifi refreshes and exist even when
  /// no Unifi console is configured. Each entry is a ProtectCamera JSON map.
  Future<void> saveManualCameras(List<Map<String, dynamic>> cameras) async {
    await write('manual_cameras', jsonEncode(cameras));
  }

  Future<List<Map<String, dynamic>>> loadManualCameras() async {
    final raw = await read('manual_cameras');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Setup mode: 'unifi' (logged in via API key) or 'manual' (user skipped
  /// Unifi login and uses manual RTSP URLs only). Absent → not yet set up.
  Future<void> saveAuthMode(String mode) async => write('auth_mode', mode);

  Future<String?> loadAuthMode() async => read('auth_mode');
}
