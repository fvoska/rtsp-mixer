import 'package:flutter/material.dart';

import '../models/battery_status.dart';

/// Material battery glyph for a reading: the charging bolt when plugged in,
/// otherwise the bar count that matches the charge. Shared by the host
/// screen and the monitor's camera card so both phones draw the same thing.
IconData batteryIcon(BatteryStatus battery) {
  if (battery.plugged) return Icons.battery_charging_full;
  final p = battery.percent;
  if (p >= 95) return Icons.battery_full;
  if (p >= 80) return Icons.battery_6_bar;
  if (p >= 65) return Icons.battery_5_bar;
  if (p >= 50) return Icons.battery_4_bar;
  if (p >= 35) return Icons.battery_3_bar;
  if (p >= 20) return Icons.battery_2_bar;
  if (p >= 10) return Icons.battery_1_bar;
  return Icons.battery_alert;
}
