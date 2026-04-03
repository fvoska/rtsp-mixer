/// Builds an mpv lavfi pan filter string for stereo panning.
///
/// [pan] ranges from -1.0 (full left) to 1.0 (full right), 0.0 = center.
/// Assumes mono input (c0) from camera microphone.
/// Returns a string suitable for NativePlayer.setProperty('af', ...).
///
/// The FFmpeg pan filter uses `|` as channel separator. mpv's lavfi filter
/// wrapper needs the graph passed via `graph="..."` to avoid mpv parsing
/// the `|` as its own filter chain separator.
String buildPanFilter(double pan) {
  final p = pan.clamp(-1.0, 1.0);
  // FFmpeg's pan filter uses `|` as channel separator which conflicts with
  // mpv's filter chain parsing — no escaping method works via setProperty.
  //
  // Instead: force mono→stereo with aformat, then use stereotools balance.
  // stereotools balance_out: -1.0 = full left, 1.0 = full right.
  final balance = p.toStringAsFixed(3);
  // Use FFmpeg's stereotools for balance. FFmpeg auto-upmixes mono→stereo
  // when feeding into a filter that requires stereo input.
  return 'lavfi=[stereotools=balance_out=$balance]';
}
