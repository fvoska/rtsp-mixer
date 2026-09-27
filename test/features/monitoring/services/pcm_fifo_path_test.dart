import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/pcm_fifo.dart';

void main() {
  test('POSIX pipes live in the given directory', () {
    expect(
      PcmFifo.pathFor('/tmp/x', 'tap-cam1', windows: false),
      '/tmp/x/roomtone-tap-cam1.pcm',
    );
  });

  test('Windows pipes live in the pipe namespace, keyed by process id', () {
    expect(
      PcmFifo.pathFor(r'C:\Temp', 'tap-cam1', windows: true, processId: 42),
      r'\\.\pipe\roomtone-42-tap-cam1',
    );
  });
}
