import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';

/// Polls a paired phone's `/status` endpoint for its microphone level.
///
/// The monitor's loudness proxy is the encoded audio bitrate, which is
/// constant for a PCM stream — so a phone camera reports its own RMS level
/// and this poller keeps the latest value per camera. The audio poll loop
/// reads [levelFor] synchronously; a stale or failed poll degrades to null
/// (caller keeps the previous level) and never to an exception.
class PeerLevelPoller {
  PeerLevelPoller({
    this.interval = const Duration(milliseconds: 500),
    this.timeout = const Duration(milliseconds: 900),
    this.staleAfter = const Duration(seconds: 3),
    Future<Map<String, dynamic>?> Function(String url, Duration timeout)? fetch,
  }) : _fetch = fetch ?? _httpFetch;

  final Duration interval;
  final Duration timeout;
  final Duration staleAfter;
  final Future<Map<String, dynamic>?> Function(String url, Duration timeout)
      _fetch;

  final Map<String, _Entry> _entries = {};

  /// Start (or re-target) polling for [cameraId].
  void start(String cameraId, String? statusUrl) {
    if (statusUrl == null || statusUrl.isEmpty) return;
    final existing = _entries[cameraId];
    if (existing != null && existing.url == statusUrl) return;
    existing?.timer.cancel();
    final entry = _Entry(statusUrl);
    entry.timer = Timer.periodic(interval, (_) => _tick(cameraId, entry));
    _entries[cameraId] = entry;
    // ignore: unawaited_futures
    _tick(cameraId, entry);
  }

  void stop(String cameraId) {
    _entries.remove(cameraId)?.timer.cancel();
  }

  void stopAll() {
    for (final e in _entries.values) {
      e.timer.cancel();
    }
    _entries.clear();
  }

  /// Latest level in 0..1, or null when unknown/stale.
  double? levelFor(String cameraId) {
    final e = _entries[cameraId];
    if (e == null || e.lastOk == null) return null;
    if (DateTime.now().difference(e.lastOk!) > staleAfter) return null;
    return e.level;
  }

  /// Latest host-measured dBFS, or null when unknown/stale (hosts from an
  /// older build report only the 0..1 level).
  double? dbFor(String cameraId) {
    final e = _entries[cameraId];
    if (e == null || e.lastOk == null || e.levelDb == null) return null;
    if (DateTime.now().difference(e.lastOk!) > staleAfter) return null;
    return e.levelDb;
  }

  /// Latest listener count reported by the host, if known.
  int? listenersFor(String cameraId) => _entries[cameraId]?.listeners;

  Future<void> _tick(String cameraId, _Entry entry) async {
    if (entry.inFlight) return;
    entry.inFlight = true;
    try {
      final json = await _fetch(entry.url, timeout);
      if (json == null) return;
      final level = json['level'];
      if (level is num && level.isFinite) {
        entry.level = level.toDouble().clamp(0.0, 1.0);
        entry.lastOk = DateTime.now();
      }
      final db = json['levelDb'];
      entry.levelDb = db is num && db.isFinite ? db.toDouble() : null;
      final listeners = json['listeners'];
      if (listeners is int) entry.listeners = listeners;
    } catch (e) {
      // Logged sparsely: this runs twice a second per phone camera.
      if (entry.failures++ % 20 == 0) {
        appLog('PEER_LEVEL', '$cameraId status poll failed: $e');
      }
    } finally {
      entry.inFlight = false;
    }
  }

  static Future<Map<String, dynamic>?> _httpFetch(
      String url, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(res).join().timeout(timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } finally {
      client.close(force: true);
    }
  }
}

class _Entry {
  _Entry(this.url);
  final String url;
  late Timer timer;
  double level = 0.0;
  double? levelDb;
  int? listeners;
  DateTime? lastOk;
  bool inFlight = false;
  int failures = 0;
}
