/// Builds an mpv lavfi pan filter string for stereo panning.
///
/// [pan] ranges from -1.0 (full left) to 1.0 (full right), 0.0 = center.
/// Assumes mono input (c0) from camera microphone.
/// Returns a string suitable for NativePlayer.setProperty('af', ...).
String buildPanFilter(double pan) {
  final p = pan.clamp(-1.0, 1.0);
  final leftGain = ((1.0 - p) / 2.0).toStringAsFixed(3);
  final rightGain = ((1.0 + p) / 2.0).toStringAsFixed(3);
  return 'lavfi=[pan=stereo|FL=$leftGain*c0|FR=$rightGain*c0]';
}
