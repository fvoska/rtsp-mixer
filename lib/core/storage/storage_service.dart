import 'dart:convert';

/// Simple in-memory storage for the app.
/// Works without keychain entitlements or code signing.
/// TODO: Replace with flutter_secure_storage for production Android builds.
class StorageService {
  final Map<String, String> _data = {};

  Future<void> write(String key, String value) async => _data[key] = value;
  Future<String?> read(String key) async => _data[key];
  Future<void> delete(String key) async => _data.remove(key);
  Future<void> deleteAll() async => _data.clear();

  Future<void> saveCredentials(String host, String apiKey) async {
    _data['host'] = host;
    _data['api_key'] = apiKey;
  }

  Future<({String host, String apiKey})?> loadCredentials() async {
    final host = _data['host'];
    final apiKey = _data['api_key'];
    if (host == null || apiKey == null) return null;
    return (host: host, apiKey: apiKey);
  }

  Future<void> clearAll() async => _data.clear();

  Future<void> saveSelectedCameraIds(List<String> ids) async {
    _data['selected_cameras'] = jsonEncode(ids);
  }

  Future<List<String>> loadSelectedCameraIds() async {
    final raw = _data['selected_cameras'];
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }
}
