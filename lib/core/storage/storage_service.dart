import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';

/// Persistent encrypted storage using platform keystore/keychain.
/// - Android: EncryptedSharedPreferences (backed by Android Keystore)
/// - iOS/macOS: Keychain Services
///
/// Falls back to in-memory storage if keychain/keystore is unavailable
/// (e.g. unsigned macOS builds during development).
class StorageService {
  static const _storage = FlutterSecureStorage();
  final Map<String, String> _fallback = {};
  bool _useFallback = false;

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

  Future<void> saveSelectedCameraIds(List<String> ids) async {
    await write('selected_cameras', jsonEncode(ids));
  }

  Future<List<String>> loadSelectedCameraIds() async {
    final raw = await read('selected_cameras');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }
}
