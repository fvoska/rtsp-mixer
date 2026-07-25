import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/services/external_link_launcher.dart';
import 'package:rtsp_mixer/features/about/screens/about_screen.dart';

/// A changelog carrying the three link shapes that matter: a normal issue
/// link, a commit link, and a target the app must refuse to launch.
const _changelog = '''
# Changelog

## [1.9.2](https://github.com/fvoska/rtsp-mixer/compare/v1.9.1...v1.9.2) (2026-07-24)


### Documentation

* **readme:** rewrite README ([#35](https://github.com/fvoska/rtsp-mixer/issues/35)) ([12fb9ed](https://github.com/fvoska/rtsp-mixer/commit/12fb9ed))
* **danger:** hostile target ([sketchy](javascript:alert(1)))
''';

/// Serves [_changelog] for `CHANGELOG.md` so the test does not assert against
/// the repo's real, ever-changing changelog.
class _StubAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'CHANGELOG.md') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(_changelog)));
    }
    throw FlutterError('Unexpected asset requested in test: $key');
  }
}

/// Finds the rendered [TextSpan] whose text is exactly [text], so a test can
/// assert on the span's recognizer instead of only on tap side effects.
TextSpan? _spanFor(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    TextSpan? match;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        match = span;
        return false;
      }
      return true;
    });
    if (match != null) return match;
  }
  return null;
}

void main() {
  late List<Uri> launched;

  setUp(() {
    launched = [];
    externalLinkOpener = (url) async {
      launched.add(url);
      return true;
    };
  });

  tearDown(() {
    externalLinkOpener = defaultExternalLinkOpener;
  });

  /// Pumps the About screen with the stub changelog and expands the release,
  /// since ExpansionTile starts collapsed.
  Future<void> pumpExpandedAbout(WidgetTester tester) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _StubAssetBundle(),
        child: const MaterialApp(home: AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.9.2'), findsOneWidget);
    await tester.tap(find.text('1.9.2'));
    await tester.pumpAndSettle();
  }

  group('AboutScreen changelog links', () {
    testWidgets('tapping an issue link opens it in the browser', (
      tester,
    ) async {
      await pumpExpandedAbout(tester);

      await tester.tapOnText(find.textRange.ofSubstring('#35'));
      await tester.pumpAndSettle();

      expect(launched, [
        Uri.parse('https://github.com/fvoska/rtsp-mixer/issues/35'),
      ]);
    });

    testWidgets('tapping a commit link opens that commit', (tester) async {
      await pumpExpandedAbout(tester);

      await tester.tapOnText(find.textRange.ofSubstring('12fb9ed'));
      await tester.pumpAndSettle();

      expect(launched, [
        Uri.parse('https://github.com/fvoska/rtsp-mixer/commit/12fb9ed'),
      ]);
    });

    testWidgets('the compare URL from the release header is a link', (
      tester,
    ) async {
      await pumpExpandedAbout(tester);

      expect(find.text('View changes on GitHub'), findsOneWidget);
      await tester.tap(find.text('View changes on GitHub'));
      await tester.pumpAndSettle();

      expect(launched, [
        Uri.parse(
          'https://github.com/fvoska/rtsp-mixer/compare/v1.9.1...v1.9.2',
        ),
      ]);
    });

    testWidgets('a non-http link renders but never launches', (tester) async {
      await pumpExpandedAbout(tester);

      // The label is still shown — only the tap handler is withheld.
      expect(find.textRange.ofSubstring('sketchy'), findsOneWidget);
      await tester.tapOnText(find.textRange.ofSubstring('sketchy'));
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
    });

    testWidgets('only launchable links get a tap recognizer', (tester) async {
      await pumpExpandedAbout(tester);

      // Asserted on the span rather than on the tap: openExternalLink would
      // refuse a javascript: target anyway, so a tap-only test would pass even
      // if the renderer wrongly made the span tappable.
      expect(_spanFor(tester, '#35')?.recognizer, isNotNull);
      expect(_spanFor(tester, '12fb9ed')?.recognizer, isNotNull);
      expect(_spanFor(tester, 'sketchy'), isNotNull);
      expect(_spanFor(tester, 'sketchy')?.recognizer, isNull);
    });

    testWidgets('link markup is stripped from the rendered bullet', (
      tester,
    ) async {
      await pumpExpandedAbout(tester);

      // Regression guard: the raw markdown must not leak into the UI.
      expect(find.textContaining('](https://'), findsNothing);
      expect(find.textContaining('**readme:**'), findsNothing);
    });
  });

  group('openExternalLink', () {
    test('refuses a non-http(s) scheme without calling the launcher', () async {
      final result = await openExternalLink(Uri.parse('javascript:alert(1)'));
      expect(result, isFalse);
      expect(launched, isEmpty);
    });

    test('refuses an http URL with no host', () async {
      expect(await openExternalLink(Uri.parse('http:///nowhere')), isFalse);
      expect(launched, isEmpty);
    });

    test('a throwing launcher resolves to false instead of propagating', () async {
      externalLinkOpener = (_) async => throw PlatformException(code: 'boom');
      expect(
        await openExternalLink(Uri.parse('https://example.com')),
        isFalse,
      );
    });

    test('a declined launch resolves to false', () async {
      externalLinkOpener = (_) async => false;
      expect(
        await openExternalLink(Uri.parse('https://example.com')),
        isFalse,
      );
    });

    test('a successful launch resolves to true', () async {
      expect(await openExternalLink(Uri.parse('https://example.com')), isTrue);
      expect(launched, [Uri.parse('https://example.com')]);
    });
  });

  group('tryParseLaunchableLink', () {
    test('accepts http and https', () {
      expect(tryParseLaunchableLink('https://example.com'), isNotNull);
      expect(tryParseLaunchableLink('http://example.com'), isNotNull);
    });

    test('rejects empty, relative, and non-http(s) targets', () {
      expect(tryParseLaunchableLink(''), isNull);
      expect(tryParseLaunchableLink('   '), isNull);
      expect(tryParseLaunchableLink('/relative/path'), isNull);
      expect(tryParseLaunchableLink('javascript:alert(1)'), isNull);
      expect(tryParseLaunchableLink('mailto:someone@example.com'), isNull);
    });
  });
}
