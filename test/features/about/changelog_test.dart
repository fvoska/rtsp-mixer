import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/about/changelog.dart';

/// A trimmed-down excerpt that mirrors the real release-please CHANGELOG.md
/// shape: an H1 header, multiple releases newest-first, several section
/// types, and bullets carrying bold scope prefixes and markdown links.
const _realShape = '''
# Changelog

## [1.9.2](https://github.com/fvoska/rtsp-mixer/compare/v1.9.1...v1.9.2) (2026-07-24)


### Documentation

* **readme:** rewrite README as a selling-point overview ([#35](https://github.com/fvoska/rtsp-mixer/issues/35)) ([12fb9ed](https://github.com/fvoska/rtsp-mixer/commit/12fb9ed))

## [1.8.0](https://github.com/fvoska/rtsp-mixer/compare/v1.7.0...v1.8.0) (2026-07-23)


### Features

* **monitoring:** absolute SPL level bar ([#29](https://github.com/fvoska/rtsp-mixer/issues/29)) ([e6b980a](https://github.com/fvoska/rtsp-mixer/commit/e6b980a))


### Bug Fixes

* **monitoring:** require positive liveness evidence ([#28](https://github.com/fvoska/rtsp-mixer/issues/28)) ([48e824c](https://github.com/fvoska/rtsp-mixer/commit/48e824c))
''';

void main() {
  group('parseChangelog', () {
    test('parses real changelog shape into ordered, grouped releases', () {
      final releases = parseChangelog(_realShape);

      expect(releases.length, 2);

      // Newest first, order preserved from the source.
      expect(releases[0].version, '1.9.2');
      expect(releases[1].version, '1.8.0');

      // Compare URL and date captured on the first release.
      expect(releases[0].compareUrl, isNotNull);
      expect(
        releases[0].compareUrl,
        'https://github.com/fvoska/rtsp-mixer/compare/v1.9.1...v1.9.2',
      );
      expect(releases[0].date, '2026-07-24');

      // First release: one Documentation section, one entry.
      expect(releases[0].sections.length, 1);
      expect(releases[0].sections[0].heading, 'Documentation');
      expect(releases[0].sections[0].entries.length, 1);
      expect(
        releases[0].sections[0].entries[0],
        contains('rewrite README'),
      );

      // Second release: two sections, in source order.
      expect(releases[1].sections.length, 2);
      expect(releases[1].sections[0].heading, 'Features');
      expect(releases[1].sections[1].heading, 'Bug Fixes');
      expect(releases[1].sections[0].entries.length, 1);
      expect(releases[1].sections[1].entries.length, 1);
    });

    test('ignores the top-level "# Changelog" H1 header', () {
      final releases = parseChangelog(_realShape);
      // No release should be named "Changelog".
      expect(
        releases.where((r) => r.version.toLowerCase() == 'changelog'),
        isEmpty,
      );
    });

    test('empty input returns an empty list', () {
      expect(parseChangelog(''), isEmpty);
      expect(parseChangelog('   \n\n  '), isEmpty);
    });

    test('input with no release headers returns an empty list', () {
      const noReleases = '''
# Changelog

Some prose that is not a release.

Just text, no version headers here.
''';
      expect(parseChangelog(noReleases), isEmpty);
    });

    test('a release with no body yields empty sections without throwing', () {
      const emptyBody = '''
# Changelog

## [2.0.0](https://example.com/compare) (2026-08-01)

## [1.0.0](https://example.com/compare2) (2026-01-01)


### Features

* **core:** first release ([abc1234](https://example.com/commit))
''';
      final releases = parseChangelog(emptyBody);
      expect(releases.length, 2);
      expect(releases[0].version, '2.0.0');
      expect(releases[0].sections, isEmpty);
      expect(releases[1].version, '1.0.0');
      expect(releases[1].sections.length, 1);
    });

    test('a release header without a URL or date still parses', () {
      const bareHeader = '''
# Changelog

## [1.2.3]


### Features

* **x:** something
''';
      final releases = parseChangelog(bareHeader);
      expect(releases.length, 1);
      expect(releases[0].version, '1.2.3');
      expect(releases[0].compareUrl, isNull);
      expect(releases[0].date, isNull);
      expect(releases[0].sections.length, 1);
    });

    test('supports "-" bullets in addition to "*" bullets', () {
      const dashBullets = '''
# Changelog

## [1.0.0](https://example.com) (2026-01-01)


### Features

- first
- second
''';
      final releases = parseChangelog(dashBullets);
      expect(releases.single.sections.single.entries.length, 2);
    });
  });

  group('parseInlineMarkdown', () {
    test('plain text yields a single text run', () {
      final parts = parseInlineMarkdown('just some text');
      expect(parts.length, 1);
      expect(parts.single.text, 'just some text');
      expect(parts.single.isBold, isFalse);
      expect(parts.single.isLink, isFalse);
    });

    test('empty input yields no runs', () {
      expect(parseInlineMarkdown(''), isEmpty);
    });

    test('bold marks the run bold without the asterisks', () {
      final parts = parseInlineMarkdown('**monitoring:** absolute SPL bar');
      expect(parts.length, 2);
      expect(parts[0].text, 'monitoring:');
      expect(parts[0].isBold, isTrue);
      expect(parts[1].text, ' absolute SPL bar');
      expect(parts[1].isBold, isFalse);
    });

    test('link captures label and target separately', () {
      final parts = parseInlineMarkdown('see [#35](https://example.com/35)');
      expect(parts.length, 2);
      expect(parts[0].text, 'see ');
      expect(parts[1].isLink, isTrue);
      expect(parts[1].text, '#35');
      expect(parts[1].url, 'https://example.com/35');
    });

    test('parses a real release-please bullet end to end', () {
      final parts = parseInlineMarkdown(
        '**readme:** rewrite README '
        '([#35](https://github.com/fvoska/rtsp-mixer/issues/35)) '
        '([12fb9ed](https://github.com/fvoska/rtsp-mixer/commit/12fb9ed))',
      );

      // Bold scope, then two links, with plain text between/around them.
      expect(parts.first.isBold, isTrue);
      expect(parts.first.text, 'readme:');

      final links = parts.where((p) => p.isLink).toList();
      expect(links.length, 2);
      expect(links[0].text, '#35');
      expect(links[0].url, 'https://github.com/fvoska/rtsp-mixer/issues/35');
      expect(links[1].text, '12fb9ed');
      expect(links[1].url, 'https://github.com/fvoska/rtsp-mixer/commit/12fb9ed');

      // Nothing is lost: concatenating the runs rebuilds the visible text.
      expect(
        parts.map((p) => p.text).join(),
        'readme: rewrite README (#35) (12fb9ed)',
      );
    });

    test('link with an empty target still parses, with an empty url', () {
      final parts = parseInlineMarkdown('[label]()');
      expect(parts.single.isLink, isTrue);
      expect(parts.single.text, 'label');
      expect(parts.single.url, '');
    });

    test('unbalanced markers pass through as literal text', () {
      final parts = parseInlineMarkdown('**not closed and [not a link');
      expect(parts.single.isBold, isFalse);
      expect(parts.single.isLink, isFalse);
      expect(parts.single.text, '**not closed and [not a link');
    });
  });
}
