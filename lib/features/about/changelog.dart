/// Dependency-free parser for the fixed release-please CHANGELOG.md subset.
///
/// The app deliberately ships no markdown renderer package (flutter_markdown
/// is discontinued upstream). Instead we parse the small, well-known shape
/// release-please emits by hand and let the About screen render native
/// widgets from the model below.
///
/// Parsing is intentionally tolerant per CLAUDE.md: any unexpected line is
/// skipped rather than fatal, and a total parse miss returns an empty list so
/// the screen can fall back to plain text instead of losing the changelog.
library;

/// A single released version and its grouped change sections.
class ChangelogRelease {
  const ChangelogRelease({
    required this.version,
    required this.sections,
    this.compareUrl,
    this.date,
  });

  /// The semver string, e.g. `1.9.2`.
  final String version;

  /// The release-please compare URL, when present in the header.
  final String? compareUrl;

  /// The release date string as written (e.g. `2026-07-24`), when present.
  final String? date;

  /// Grouped change sections (Features, Bug Fixes, …), in source order.
  /// May be empty for a release header with no following body.
  final List<ChangelogSection> sections;
}

/// A titled group of change entries under one release (e.g. "Features").
class ChangelogSection {
  const ChangelogSection({required this.heading, required this.entries});

  /// The `###` heading text, e.g. `Features`.
  final String heading;

  /// Raw bullet text for each entry, markdown left intact for the renderer.
  final List<String> entries;
}

/// Matches a release header line: `## [1.2.3](url) (2026-07-24)`.
///
/// The URL and date are optional so a bare `## [1.2.3]` still parses. The
/// version group is required — anything else is not treated as a release.
final RegExp _releaseHeader = RegExp(
  r'^##\s+\[([^\]]+)\](?:\(([^)]*)\))?(?:\s+\(([^)]*)\))?\s*$',
);

/// Matches a section heading line: `### Features`.
final RegExp _sectionHeader = RegExp(r'^###\s+(.+?)\s*$');

/// Matches a bullet line: `* text` or `- text`.
final RegExp _bullet = RegExp(r'^[*-]\s+(.*)$');

/// Parses [raw] release-please changelog text into ordered releases, newest
/// first (source order preserved).
///
/// Returns an empty list for empty input, input that contains no release
/// headers, or any unexpected failure — signalling the caller to fall back to
/// plain-text rendering rather than throwing.
List<ChangelogRelease> parseChangelog(String raw) {
  try {
    if (raw.trim().isEmpty) return const [];

    final lines = raw.split('\n');

    // Accumulators for the release currently being built.
    final releases = <ChangelogRelease>[];
    _ReleaseBuilder? current;
    _SectionBuilder? section;

    void closeSection() {
      if (current != null && section != null) {
        current!.sections.add(
          ChangelogSection(heading: section!.heading, entries: section!.entries),
        );
        section = null;
      }
    }

    void closeRelease() {
      closeSection();
      if (current != null) {
        releases.add(
          ChangelogRelease(
            version: current!.version,
            compareUrl: current!.compareUrl,
            date: current!.date,
            sections: current!.sections,
          ),
        );
        current = null;
      }
    }

    for (final line in lines) {
      try {
        final releaseMatch = _releaseHeader.firstMatch(line);
        if (releaseMatch != null) {
          closeRelease();
          final url = releaseMatch.group(2);
          final date = releaseMatch.group(3);
          current = _ReleaseBuilder(
            version: releaseMatch.group(1)!.trim(),
            compareUrl: (url != null && url.trim().isNotEmpty) ? url.trim() : null,
            date: (date != null && date.trim().isNotEmpty) ? date.trim() : null,
          );
          continue;
        }

        // Only interpret sections/bullets once inside a release.
        if (current == null) continue;

        final sectionMatch = _sectionHeader.firstMatch(line);
        if (sectionMatch != null) {
          closeSection();
          section = _SectionBuilder(sectionMatch.group(1)!.trim());
          continue;
        }

        final bulletMatch = _bullet.firstMatch(line);
        if (bulletMatch != null && section != null) {
          final text = bulletMatch.group(1)!.trim();
          if (text.isNotEmpty) section!.entries.add(text);
        }
      } catch (_) {
        // Defensive: any single malformed line is skipped, never fatal.
        continue;
      }
    }

    closeRelease();
    return releases;
  } catch (_) {
    // Total parse miss degrades to empty so the screen falls back to text.
    return const [];
  }
}

class _ReleaseBuilder {
  _ReleaseBuilder({required this.version, this.compareUrl, this.date});

  final String version;
  final String? compareUrl;
  final String? date;
  final List<ChangelogSection> sections = [];
}

class _SectionBuilder {
  _SectionBuilder(this.heading);

  final String heading;
  final List<String> entries = [];
}
