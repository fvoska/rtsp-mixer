/// A Roomtone host seen on the LAN — via a discovery reply, a QR code, or a
/// typed address. Value object; [lastSeen] lets the scanner expire hosts
/// that stopped answering.
class DiscoveredHost {
  const DiscoveredHost({
    required this.hostId,
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    this.pairingOpen = true,
    required this.lastSeen,
  });

  final String hostId;
  final String name;
  final String address;
  final int port;
  final int protocol;
  final bool pairingOpen;
  final DateTime lastSeen;

  DiscoveredHost copyWith({
    String? name,
    String? address,
    int? port,
    int? protocol,
    bool? pairingOpen,
    DateTime? lastSeen,
  }) =>
      DiscoveredHost(
        hostId: hostId,
        name: name ?? this.name,
        address: address ?? this.address,
        port: port ?? this.port,
        protocol: protocol ?? this.protocol,
        pairingOpen: pairingOpen ?? this.pairingOpen,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredHost &&
          hostId == other.hostId &&
          name == other.name &&
          address == other.address &&
          port == other.port &&
          protocol == other.protocol &&
          pairingOpen == other.pairingOpen;

  @override
  int get hashCode =>
      Object.hash(hostId, name, address, port, protocol, pairingOpen);

  @override
  String toString() => 'DiscoveredHost($name @ $address:$port, id=$hostId)';
}
