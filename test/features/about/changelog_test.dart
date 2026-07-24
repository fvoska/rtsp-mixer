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
}
