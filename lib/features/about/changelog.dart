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

/// One run of inline content inside a bullet — plain text, bold text, or a
/// markdown link.
///
/// The renderer maps these to `TextSpan`s. Keeping the parse here (rather than
/// inside a private widget helper) makes it unit-testable and keeps the widget
/// free of regexes.
class ChangelogInline {
  const ChangelogInline.text(this.text)
    : isBold = false,
      url = null;

  const ChangelogInline.bold(this.text)
    : isBold = true,
      url = null;

  const ChangelogInline.link(this.text, String this.url) : isBold = false;

  /// The text to display. For a link this is the label, not the target.
  final String text;

  /// Whether the run came from `**…**`.
  final bool isBold;

  /// The raw link target for `[label](target)`, else null. Not validated here —
  /// the renderer decides whether it is launchable.
  final String? url;

  /// Whether this run is a link.
  bool get isLink => url != null;
}

/// Matches `**bold**` or `[label](target)`.
final RegExp _inlineMarkdown = RegExp(
  r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)]*)\)',
);

/// Splits a raw changelog bullet into ordered inline runs.
///
/// Unmatched text passes through verbatim, so an unbalanced `**` or a stray
/// bracket renders as the literal characters rather than being dropped.
///
/// Defensive per CLAUDE.md: any failure degrades to a single plain-text run
/// carrying [raw] unchanged — a malformed bullet must never break the page.
List<ChangelogInline> parseInlineMarkdown(String raw) {
  try {
    if (raw.isEmpty) return const [];

    final parts = <ChangelogInline>[];
    var last = 0;
    for (final match in _inlineMarkdown.allMatches(raw)) {
      if (match.start > last) {
        parts.add(ChangelogInline.text(raw.substring(last, match.start)));
      }
      final bold = match.group(1);
      if (bold != null) {
        parts.add(ChangelogInline.bold(bold));
      } else {
        parts.add(ChangelogInline.link(match.group(2)!, match.group(3) ?? ''));
      }
      last = match.end;
    }
    if (last < raw.length) {
      parts.add(ChangelogInline.text(raw.substring(last)));
    }
    if (parts.isEmpty) return [ChangelogInline.text(raw)];
    return parts;
  } catch (_) {
    return [ChangelogInline.text(raw)];
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
