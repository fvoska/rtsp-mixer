import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper around [FlutterSecureStorage] for credential persistence,
/// selected camera IDs, and SSL acceptance state.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  const SecureStorageService(this._storage);

  // Credential keys
  static const _hostKey = 'protect_host';
  static const _usernameKey = 'protect_username';
  static const _passwordKey = 'protect_password';
  static const _selectedCameraIdsKey = 'selected_camera_ids';
  static const _sslAcceptedPrefix = 'ssl_accepted_';

  /// Save Protect console credentials.
  Future<void> saveCredentials(
      String host, String username, String password) async {
    await _storage.write(key: _hostKey, value: host);
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  /// Load saved credentials. Returns null if any key is missing.
  Future<({String host, String username, String password})?> loadCredentials() async {
    final host = await _storage.read(key: _hostKey);
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);

    if (host == null || username == null || password == null) return null;

    return (host: host, username: username, password: password);
  }

  /// Clear all stored credentials, selected cameras, and SSL acceptance.
  Future<void> clearCredentials() async {
    await _storage.deleteAll();
  }

  /// Save the list of selected camera IDs as JSON.
  Future<void> saveSelectedCameraIds(List<String> ids) async {
    await _storage.write(key: _selectedCameraIdsKey, value: jsonEncode(ids));
  }

  /// Load previously selected camera IDs. Returns empty list if none saved.
  Future<List<String>> loadSelectedCameraIds() async {
    final value = await _storage.read(key: _selectedCameraIdsKey);
    if (value == null) return [];
    return (jsonDecode(value) as List<dynamic>).cast<String>();
  }

  /// Save SSL acceptance for a specific host.
  Future<void> saveSslAccepted(String host, bool accepted) async {
    await _storage.write(
        key: '$_sslAcceptedPrefix$host', value: accepted.toString());
  }

  /// Load SSL acceptance for a specific host. Returns false if not set.
  Future<bool> loadSslAccepted(String host) async {
    final value = await _storage.read(key: '$_sslAcceptedPrefix$host');
    return value == 'true';
  }
}
