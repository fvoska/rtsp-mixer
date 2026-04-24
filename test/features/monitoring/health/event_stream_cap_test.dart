import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/models/health_event.dart';
import 'package:rtsp_mixer/features/monitoring/providers/health_events_provider.dart';

void main() {
  group('HealthEventsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    HealthEvent evt(int i) => HealthEvent(
          timestamp: DateTime.fromMillisecondsSinceEpoch(i),
          type: HealthEventType.reconnectAttempt,
          detail: 'attempt $i',
        );

    test('record appends a single event', () {
      container.read(healthEventsProvider.notifier).record(evt(1));
      expect(container.read(healthEventsProvider).length, 1);
      expect(container.read(healthEventsProvider).first.detail, 'attempt 1');
    });

    test('appending 1001 events caps at 1000 and drops oldest', () {
      final notifier = container.read(healthEventsProvider.notifier);
      for (var i = 0; i < 1001; i++) {
        notifier.record(evt(i));
      }
      final events = container.read(healthEventsProvider);
      expect(events.length, 1000);
      // oldest (i=0) dropped; first now i=1
      expect(events.first.detail, 'attempt 1');
      expect(events.last.detail, 'attempt 1000');
    });

    test('clear empties the list', () {
      final notifier = container.read(healthEventsProvider.notifier);
      notifier.record(evt(1));
      notifier.record(evt(2));
      notifier.clear();
      expect(container.read(healthEventsProvider), isEmpty);
    });
  });
}
