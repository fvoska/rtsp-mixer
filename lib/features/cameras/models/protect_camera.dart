import 'stream_channel.dart';

class ProtectCamera {
  final String id;
  final String? name;
  final String type;
  final String state;
  final bool isConnected;
  final List<StreamChannel> channels;

  const ProtectCamera({
    required this.id,
    this.name,
    required this.type,
    required this.state,
    required this.isConnected,
    required this.channels,
  });

  /// Construct RTSP URL for audio-only streaming.
  /// Returns null if no channel has RTSP enabled.
  String? rtspUrl(String nvrHost, {bool encrypted = false}) {
    final channel = channels.cast<StreamChannel?>().firstWhere(
          (c) => c!.isRtspEnabled,
          orElse: () => null,
        );
    if (channel == null) return null;
    return encrypted
        ? 'rtsps://$nvrHost:7441/${channel.rtspAlias}?enableSrtp'
        : 'rtsp://$nvrHost:7447/${channel.rtspAlias}';
  }

  factory ProtectCamera.fromJson(Map<String, dynamic> json) => ProtectCamera(
        id: json['id'] as String,
        name: json['name'] as String?,
        type: json['type'] as String,
        state: json['state'] as String,
        isConnected: json['isConnected'] as bool? ?? false,
        channels: (json['channels'] as List<dynamic>)
            .map((c) => StreamChannel.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
