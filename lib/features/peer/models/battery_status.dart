/// Battery reading a host phone reports over its status endpoint.
///
/// A phone camera that runs flat at 3 am dies silently — the monitor's
/// reconnect loop will hammer an address nobody answers. Reporting the
/// battery lets the monitor show the parent, before they fall asleep,
/// whether the phone in the nursery is plugged in.
class BatteryStatus {
  const BatteryStatus({required this.percent, required this.plugged});

  /// State of charge, 0..100.
  final int percent;

  /// Connected to external power (charging, full, or held at a charge
  /// limit). What matters to a parent is "will this phone die tonight?",
  /// so every powered state counts as plugged in.
  final bool plugged;

  /// Discharging at or below this is worth a warning on the monitor.
  static const int lowThreshold = 20;

  /// Discharging at or below this is urgent: the phone may not last the
  /// night.
  static const int criticalThreshold = 10;

  bool get isLow => !plugged && percent <= lowThreshold;
  bool get isCritical => !plugged && percent <= criticalThreshold;

  /// Wire form: `{"percent": 73, "plugged": true}`.
  Map<String, Object?> toJson() => {'percent': percent, 'plugged': plugged};

  /// Tolerant parse: an older host that sends nothing, or garbage, yields
  /// null — never an exception in a poll loop.
  static BatteryStatus? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final percent = json['percent'];
    if (percent is! num || !percent.isFinite) return null;
    final plugged = json['plugged'];
    return BatteryStatus(
      percent: percent.round().clamp(0, 100),
      plugged: plugged == true,
    );
  }

  /// One-line human form, e.g. `73% · charging` or `12% · on battery`.
  String get label => '$percent% · ${plugged ? 'charging' : 'on battery'}';

  @override
  bool operator ==(Object other) =>
      other is BatteryStatus &&
      other.percent == percent &&
      other.plugged == plugged;

  @override
  int get hashCode => Object.hash(percent, plugged);

  @override
  String toString() => 'BatteryStatus($percent%, plugged=$plugged)';
}
