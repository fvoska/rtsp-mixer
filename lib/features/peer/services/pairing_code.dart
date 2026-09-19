import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Pairing-code and token primitives for phone-to-phone pairing.
///
/// Everything here is pure Dart over `dart:math`/`crypto` — no platform
/// channels — so it is unit-tested directly and can never fail because of a
/// missing native library.

/// Number of digits in a pairing code. Six digits is the familiar TV-login
/// shape: easy to read across a room, and 10^6 combinations is plenty once
/// attempts are throttled (see `PairingGate`).
const int kPairingCodeLength = 6;

final Random _secureRandom = _newSecureRandom();

Random _newSecureRandom() {
  try {
    return Random.secure();
  } catch (_) {
    // Some exotic platforms have no CSPRNG source; a seeded Random is still
    // far better than crashing host mode.
    return Random(DateTime.now().microsecondsSinceEpoch);
  }
}

/// A fresh crypto-random numeric pairing code, zero-padded to
/// [kPairingCodeLength] digits.
String generatePairingCode({Random? random}) {
  final rng = random ?? _secureRandom;
  final buf = StringBuffer();
  for (var i = 0; i < kPairingCodeLength; i++) {
    buf.write(rng.nextInt(10));
  }
  return buf.toString();
}

/// A fresh 256-bit bearer token, URL-safe base64 without padding.
String generateToken({Random? random}) {
  final rng = random ?? _secureRandom;
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Stable, opaque host/device identifier (128 random bits, hex).
String generatePeerId({Random? random}) {
  final rng = random ?? _secureRandom;
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// SHA-256 of [token] as lowercase hex. The host persists only hashes, so a
/// leaked host config cannot be replayed as a monitor.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// Constant-time string equality so a pairing-code or token check does not
/// leak the position of the first mismatching character through timing.
bool constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  var diff = ab.length ^ bb.length;
  final n = ab.length < bb.length ? ab.length : bb.length;
  for (var i = 0; i < n; i++) {
    diff |= ab[i] ^ bb[i];
  }
  return diff == 0;
}

/// Normalize a user-typed pairing code: keep digits only. Lets the user
/// type "123 456" or "123-456" the way the host screen displays it.
String normalizePairingCode(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9]'), '');

/// Display grouping for a pairing code ("123 456") so it reads at a glance.
String formatPairingCode(String code) {
  if (code.length != kPairingCodeLength) return code;
  return '${code.substring(0, 3)} ${code.substring(3)}';
}

/// Throttles pairing attempts: after [maxFailures] wrong codes within
/// [window], pairing is locked for [lockout]. The state is per host process
/// (one gate per server), which is the right granularity — the LAN is the
/// only attack surface and the host shows a fresh code when it wants to.
class PairingGate {
  PairingGate({
    this.maxFailures = 5,
    this.window = const Duration(minutes: 1),
    this.lockout = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxFailures;
  final Duration window;
  final Duration lockout;
  final DateTime Function() _now;

  final List<DateTime> _failures = [];
  DateTime? _lockedUntil;

  /// Seconds until pairing is accepted again, or 0 when open.
  int retryAfterSeconds() {
    final until = _lockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(_now());
    if (remaining.isNegative || remaining == Duration.zero) {
      _lockedUntil = null;
      _failures.clear();
      return 0;
    }
    return remaining.inSeconds.clamp(1, lockout.inSeconds);
  }

  bool get isLocked => retryAfterSeconds() > 0;

  /// Record a wrong code. Returns true when this failure tripped the lock.
  bool recordFailure() {
    final t = _now();
    _failures.removeWhere((f) => t.difference(f) > window);
    _failures.add(t);
    if (_failures.length >= maxFailures) {
      _lockedUntil = t.add(lockout);
      return true;
    }
    return false;
  }

  /// A correct code clears the failure history.
  void recordSuccess() {
    _failures.clear();
    _lockedUntil = null;
  }
}
