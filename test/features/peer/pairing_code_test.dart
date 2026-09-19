import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/peer/services/pairing_code.dart';

void main() {
  group('generatePairingCode', () {
    test('is six digits', () {
      for (var i = 0; i < 50; i++) {
        final code = generatePairingCode();
        expect(code, matches(RegExp(r'^\d{6}$')));
      }
    });

    test('is deterministic for a seeded random', () {
      expect(generatePairingCode(random: Random(1)),
          generatePairingCode(random: Random(1)));
    });
  });

  group('tokens and ids', () {
    test('token is URL-safe base64 without padding and long enough', () {
      final t = generateToken();
      expect(t, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(t.length, greaterThanOrEqualTo(43));
    });

    test('peer id is 32 hex chars', () {
      expect(generatePeerId(), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('hashToken is stable sha256 hex', () {
      expect(hashToken('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('constantTimeEquals', () {
    test('equal strings compare true', () {
      expect(constantTimeEquals('123456', '123456'), isTrue);
    });
    test('different length or content compare false', () {
      expect(constantTimeEquals('123456', '12345'), isFalse);
      expect(constantTimeEquals('123456', '123457'), isFalse);
      expect(constantTimeEquals('', 'a'), isFalse);
    });
  });

  group('code formatting', () {
    test('normalize strips separators', () {
      expect(normalizePairingCode(' 123 456 '), '123456');
      expect(normalizePairingCode('123-456'), '123456');
    });
    test('format groups as 3+3 only for full codes', () {
      expect(formatPairingCode('123456'), '123 456');
      expect(formatPairingCode('12'), '12');
    });
  });

  group('PairingGate', () {
    test('locks after maxFailures within the window and unlocks after lockout',
        () {
      var t = DateTime(2026, 1, 1);
      final gate = PairingGate(
        maxFailures: 3,
        window: const Duration(minutes: 1),
        lockout: const Duration(seconds: 30),
        now: () => t,
      );
      expect(gate.isLocked, isFalse);
      expect(gate.recordFailure(), isFalse);
      expect(gate.recordFailure(), isFalse);
      expect(gate.recordFailure(), isTrue);
      expect(gate.isLocked, isTrue);
      expect(gate.retryAfterSeconds(), 30);
      t = t.add(const Duration(seconds: 31));
      expect(gate.isLocked, isFalse);
      // History was cleared by the expiry — one new failure does not re-lock.
      expect(gate.recordFailure(), isFalse);
    });

    test('old failures fall out of the window', () {
      var t = DateTime(2026, 1, 1);
      final gate = PairingGate(maxFailures: 2, now: () => t);
      gate.recordFailure();
      t = t.add(const Duration(minutes: 2));
      expect(gate.recordFailure(), isFalse);
    });

    test('success clears the failure history', () {
      final gate = PairingGate(maxFailures: 2);
      gate.recordFailure();
      gate.recordSuccess();
      expect(gate.recordFailure(), isFalse);
    });
  });
}
