@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/pcm_fifo.dart';

/// Exercises the real kernel32 named-pipe path. Only runs on a Windows
/// host; CI is Linux, so run it locally with `flutter test` on Windows.
void main() {
  test('is supported on this host', () {
    expect(PcmFifo.isSupported, isTrue);
  });

  test('reads nothing without a writer, then what a writer sends, and '
      're-arms for a second writer after the first leaves', () async {
    final path = PcmFifo.pathFor(Directory.systemTemp.path, 'test-tap');
    final fifo = PcmFifo.open(path);
    expect(fifo, isNotNull, reason: 'CreateNamedPipeW');
    expect(fifo!.readAvailable(), isEmpty);

    Future<void> sendAndExpect(Uint8List payload) async {
      // A client open, like mpv's CreateFileW(GENERIC_WRITE).
      final raf = File(path).openSync(mode: FileMode.writeOnly);
      raf.writeFromSync(payload);
      final got = BytesBuilder();
      for (var i = 0; i < 50 && got.length < payload.length; i++) {
        got.add(fifo.readAvailable());
        if (got.length < payload.length) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(got.takeBytes(), payload);
      raf.closeSync();
      // The next poll notices the writer is gone and re-arms the pipe.
      expect(fifo.readAvailable(), isEmpty);
    }

    await sendAndExpect(
      Uint8List.fromList(List.generate(5000, (i) => i % 251)),
    );
    await sendAndExpect(Uint8List.fromList(List.generate(300, (i) => i)));

    fifo.close();
    fifo.close(); // Idempotent.
    expect(fifo.readAvailable(), isEmpty);
  });
}
