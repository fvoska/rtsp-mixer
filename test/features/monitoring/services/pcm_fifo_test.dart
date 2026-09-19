@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/pcm_fifo.dart';

/// Exercises the real libc path on a POSIX host: the same calls run on
/// Android, where the CI suite cannot execute.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pcm_fifo_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('is supported on this host', () {
    expect(PcmFifo.isSupported, isTrue);
  });

  test('creates a FIFO, reads nothing without a writer, then reads what a '
      'writer sends, then nothing again after the writer closes', () async {
    final path = '${dir.path}/tap.pcm';
    final fifo = PcmFifo.open(path);
    expect(fifo, isNotNull, reason: 'mkfifo/open through libc');
    expect(FileSystemEntity.typeSync(path), FileSystemEntityType.pipe);

    // No writer yet: an empty read, and it must not block.
    expect(fifo!.readAvailable(), isEmpty);

    // A writer (dart:io opens the FIFO for writing on an IO thread; it
    // does not block because our read end is already open).
    final payload = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final sink = File(path).openWrite();
    sink.add(payload);
    await sink.flush();

    // Drain until we have everything (the write lands asynchronously).
    final got = BytesBuilder();
    for (var i = 0; i < 50 && got.length < payload.length; i++) {
      got.add(fifo.readAvailable());
      if (got.length < payload.length) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(got.takeBytes(), payload);

    await sink.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fifo.readAvailable(), isEmpty, reason: 'writer gone → EOF → empty');

    fifo.close();
    expect(File(path).existsSync(), isFalse, reason: 'unlinked on close');
    // Idempotent.
    fifo.close();
    expect(fifo.readAvailable(), isEmpty);
  });

  test('replaces a stale regular file at the same path', () async {
    final path = '${dir.path}/stale.pcm';
    File(path).writeAsStringSync('old');
    final fifo = PcmFifo.open(path);
    expect(fifo, isNotNull);
    expect(FileSystemEntity.typeSync(path), FileSystemEntityType.pipe);
    fifo!.close();
  });

  test('an unwritable location returns null instead of throwing', () {
    expect(PcmFifo.open('/proc/definitely/not/here.pcm'), isNull);
  });
}
