/// Camera from the official Protect API (integration/v1/cameras).
class ProtectCamera {
  final String id;
  final String? name;
  final String state;
  final bool isMicEnabled;

  const ProtectCamera({
    required this.id,
    this.name,
    required this.state,
    this.isMicEnabled = false,
  });

  bool get isConnected => state == 'CONNECTED';

  factory ProtectCamera.fromJson(Map<String, dynamic> json) => ProtectCamera(
        id: json['id'] as String,
        name: json['name'] as String?,
        state: json['state'] as String? ?? 'DISCONNECTED',
        isMicEnabled: json['isMicEnabled'] as bool? ?? false,
      );
}
