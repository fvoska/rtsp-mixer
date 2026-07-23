import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/monitoring/models/player_state.dart';
import 'package:rtsp_mixer/features/monitoring/widgets/camera_audio_card.dart';

/// True if the paragraph rendered on more than one line.
bool _wrapped(RenderParagraph rp) =>
    rp.size.height > rp.getMaxIntrinsicHeight(double.infinity) + 1.0;

/// Multi-line text is only expected for the full-sentence silence warning and
/// the (up-to-3-line) error banner copy. Every short status label
/// (`Live`, `Connecting…`, `Reconnecting…`) must still be single-line.
bool _mayWrap(String data) =>
    data.startsWith('No audio for') || data.startsWith('Microphone is disabled');

Future<void> _pumpCard(
  WidgetTester tester,
  CameraAudioState state,
  double widthDp, {
  bool badge = false,
  bool debug = false,
}) async {
  tester.view.physicalSize = Size(widthDp * 2, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() => tester.view.reset());
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          // SingleChildScrollView mirrors the real live-view host and gives the
          // card unbounded height so a genuine wrap grows rather than overflows.
          body: SingleChildScrollView(
            child: CameraAudioCard(
              cameraState: state,
              cameraIndex: 0,
              showSourceBadge: badge,
              showDebugInfo: debug,
              onToggleVideo: () {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectClean(WidgetTester tester, String label) {
  expect(tester.takeException(), isNull,
      reason: '$label: header/row overflowed');
  for (final el in find.byType(Text).evaluate()) {
    final data = (el.widget as Text).data ?? '';
    if (data.isEmpty || _mayWrap(data)) continue;
    // Text inside a SelectionArea (the debug panel) resolves to a non-paragraph
    // render object; skip those — the header/controls texts we care about are
    // plain RenderParagraphs.
    final ro = el.renderObject;
    if (ro is! RenderParagraph) continue;
    expect(_wrapped(ro), isFalse,
        reason: '$label: text wrapped unexpectedly: "$data"');
  }
}

void main() {
  // A deliberately long name + long error to stress single-line ellipsis.
  const longName = 'Downstairs Living Room Camera North';
  const longError =
      'Microphone is disabled on this camera -- enable it in Protect camera settings';

  CameraAudioState state(CameraConnectionStatus status,
          {Map<String, String> qualities = const {
            'low': 'a',
            'medium': 'b',
            'high': 'c'
          },
          String activeQuality = 'low',
          double silence = 0,
          bool manual = false}) =>
      CameraAudioState(
        cameraId: 'c',
        cameraName: longName,
        connectionStatus: status,
        errorMessage:
            status == CameraConnectionStatus.error ? longError : null,
        activeQuality: activeQuality,
        availableQualities: qualities,
        silenceDuration: silence,
        isManual: manual,
      );

  final scenarios = <String, CameraAudioState>{
    'playing': state(CameraConnectionStatus.playing),
    'connecting': state(CameraConnectionStatus.connecting),
    'reconnecting': state(CameraConnectionStatus.reconnecting),
    'error': state(CameraConnectionStatus.error),
    'silent': state(CameraConnectionStatus.playing,
        qualities: {'high': 'c'}, activeQuality: 'high', silence: 42),
    'manual-single-quality': state(CameraConnectionStatus.playing,
        qualities: {'stream': 'rtsp://x/s'},
        activeQuality: 'stream',
        manual: true),
  };

  // Reasonable live-card widths: the fluid grid floors card width at ~340dp;
  // a phone is typically ~360-411dp, tablets wider.
  const widths = [340.0, 360.0, 411.0, 480.0];

  for (final w in widths) {
    for (final entry in scenarios.entries) {
      testWidgets('${entry.key} @ ${w}dp renders single-line, no overflow',
          (tester) async {
        await _pumpCard(tester, entry.value, w);
        _expectClean(tester, '${entry.key}@$w');
      });

      testWidgets(
          '${entry.key} @ ${w}dp with source badge + details renders clean',
          (tester) async {
        await _pumpCard(tester, entry.value, w, badge: true, debug: true);
        _expectClean(tester, '${entry.key}@$w badge+debug');
      });
    }
  }

  testWidgets('volume percentage never wraps (100%)', (tester) async {
    await _pumpCard(tester, scenarios['playing']!, 340);
    final rp = tester.renderObject<RenderParagraph>(find.text('100%'));
    expect(_wrapped(rp), isFalse);
  });

  testWidgets('reconnecting @ 340dp renders full "Reconnecting…" single line',
      (tester) async {
    // Pins the fixed "Re…" truncation bug: on the narrowest live-card width the
    // full label must render as one un-truncated line in its own banner.
    await _pumpCard(tester, scenarios['reconnecting']!, 340);
    final rp = tester.renderObject<RenderParagraph>(find.text('Reconnecting…'));
    expect(_wrapped(rp), isFalse);
  });
}
