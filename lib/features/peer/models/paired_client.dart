/// A monitor that has paired with this host. Only the SHA-256 of the bearer
/// token is kept, so the persisted host config is useless to an attacker who
/// reads it — the token itself lives only on the monitor.
class PairedClient {
  const PairedClient({
    required this.id,
    required this.name,
    required this.tokenHash,
    required this.pairedAt,
  });

  final String id;
  final String name;
  final String tokenHash;
  final DateTime pairedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tokenHash': tokenHash,
        'pairedAt': pairedAt.toIso8601String(),
      };

  /// Tolerant decode: a malformed entry returns null rather than throwing,
  /// so one bad record cannot wipe the whole paired-device list.
  static PairedClient? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final hash = raw['tokenHash'];
    if (id is! String || id.isEmpty || hash is! String || hash.isEmpty) {
      return null;
    }
    final name = raw['name'];
    final pairedAt = DateTime.tryParse(raw['pairedAt']?.toString() ?? '');
    return PairedClient(
      id: id,
      name: name is String && name.isNotEmpty ? name : 'Monitor',
      tokenHash: hash,
      pairedAt: pairedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
