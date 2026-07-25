import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/services/audio_handler.dart';

/// The handler pushes to BaseAudioHandler's own streams, so it is safe to
/// exercise without `AudioService.init` (see the note on audioHandlerProvider).
final _probe = Provider<MonitoringAudioHandler>(
  (ref) => MonitoringAudioHandler(ref),
);

void main() {
  late ProviderContainer container;
  late MonitoringAudioHandler handler;

  setUp(() {
    container = ProviderContainer();
    handler = container.read(_probe);
  });

  tearDown(() => container.dispose());

  group('lock-screen media item', () {
    test('camera names land in the subtitle with the healthy title', () {
      handler.setCameraNames(['Neo', 'Porch']);
      expect(handler.mediaItem.value?.title, 'Listening');
      expect(handler.mediaItem.value?.artist, 'Monitoring: Neo, Porch');
    });

    test('a status title replaces "Listening" and keeps the camera names', () {
      handler.setCameraNames(['Neo']);
      handler.setStatusTitle('Reconnecting…');
      expect(handler.mediaItem.value?.title, 'Reconnecting…');
      expect(handler.mediaItem.value?.artist, 'Monitoring: Neo');
    });

    test('a camera-list change preserves the current status title', () {
      handler.setStatusTitle('Stream failed');
      handler.setCameraNames(['Neo', 'Porch']);
      expect(handler.mediaItem.value?.title, 'Stream failed');
      expect(handler.mediaItem.value?.artist, 'Monitoring: Neo, Porch');
    });

    test('an unchanged title emits nothing (the 1s poll calls this)', () async {
      handler.setCameraNames(['Neo']);
      final emissions = <String?>[];
      final sub = handler.mediaItem.listen((item) => emissions.add(item?.title));
      addTearDown(sub.cancel);
      // The BehaviorSubject replays the current value first.
      await Future<void>.delayed(Duration.zero);
      expect(emissions, ['Listening']);

      handler.setStatusTitle('Listening');
      await Future<void>.delayed(Duration.zero);
      expect(emissions, ['Listening']);

      handler.setStatusTitle('Connecting…');
      await Future<void>.delayed(Duration.zero);
      expect(emissions, ['Listening', 'Connecting…']);
    });
  });
}
