import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/stream_liveness.dart';

void main() {
  group('hasRealTrack', () {
    test('real audio track alongside the auto/no pseudo entries -> true', () {
      final tracks = Tracks(
        audio: [
          AudioTrack.auto(),
          AudioTrack.no(),
          const AudioTrack('1', null, null),
        ],
      );
      expect(hasRealTrack(tracks), isTrue);
    });

    test('only a real video track (mic-disabled camera) -> true', () {
      final tracks = Tracks(
        audio: [AudioTrack.auto(), AudioTrack.no()],
        video: [
          VideoTrack.auto(),
          VideoTrack.no(),
          const VideoTrack('1', null, null),
        ],
      );
      expect(hasRealTrack(tracks), isTrue);
    });

    test('only auto/no pseudo tracks in both lists -> false', () {
      final tracks = Tracks(
        audio: [AudioTrack.auto(), AudioTrack.no()],
        video: [VideoTrack.auto(), VideoTrack.no()],
      );
      expect(hasRealTrack(tracks), isFalse);
    });

    test('default/empty Tracks() -> false', () {
      expect(hasRealTrack(const Tracks()), isFalse);
    });

    test('subtitle tracks are ignored', () {
      final tracks = Tracks(
        audio: [AudioTrack.auto(), AudioTrack.no()],
        video: [VideoTrack.auto(), VideoTrack.no()],
        subtitle: [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          const SubtitleTrack('1', null, null),
        ],
      );
      expect(hasRealTrack(tracks), isFalse);
    });

    test('never throws', () {
      expect(() => hasRealTrack(const Tracks()), returnsNormally);
    });
  });

  group('parseTrackCount', () {
    test("'0' -> 0", () {
      expect(parseTrackCount('0'), 0);
    });

    test("'3' -> 3", () {
      expect(parseTrackCount('3'), 3);
    });

    test("' 2 ' -> 2 (trims whitespace)", () {
      expect(parseTrackCount(' 2 '), 2);
    });

    test('null -> null', () {
      expect(parseTrackCount(null), isNull);
    });

    test("'' -> null", () {
      expect(parseTrackCount(''), isNull);
    });

    test("'garbage' -> null", () {
      expect(parseTrackCount('garbage'), isNull);
    });

    test('never throws', () {
      expect(() => parseTrackCount('garbage'), returnsNormally);
      expect(() => parseTrackCount(null), returnsNormally);
    });
  });
}
