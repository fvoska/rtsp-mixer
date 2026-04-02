class StreamChannel {
  final int id;
  final String name;
  final String rtspAlias;
  final bool isRtspEnabled;

  const StreamChannel({
    required this.id,
    required this.name,
    required this.rtspAlias,
    required this.isRtspEnabled,
  });

  factory StreamChannel.fromJson(Map<String, dynamic> json) => StreamChannel(
        id: json['id'] as int,
        name: json['name'] as String,
        rtspAlias: json['rtspAlias'] as String? ?? '',
        isRtspEnabled: json['isRtspEnabled'] as bool? ?? false,
      );
}
