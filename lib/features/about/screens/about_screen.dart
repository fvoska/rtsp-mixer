import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/spacing.dart';
import '../changelog.dart';

/// Static "About" detail page reachable from Settings. Mirrors HelpScreen's
/// layout (Scaffold + AppBar + centered, width-constrained scroll view).
///
/// Every runtime read (package info, bundled CHANGELOG asset) degrades
/// gracefully per CLAUDE.md — a failure resolves to a fallback state, never
/// an exception, so the page always renders and can never crash the app.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _contactEmail = 'filip@voska.tech';
  static const String _appName = 'RTSP Mixer';

  /// Reads package info, swallowing any failure into null so the caller can
  /// render an "unavailable" state instead of throwing.
  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  /// Loads the bundled CHANGELOG, resolving load failures to null.
  Future<String?> _loadChangelog() async {
    try {
      return await rootBundle.loadString('CHANGELOG.md');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Version — resolves to "unavailable" if package_info fails.
                FutureBuilder<PackageInfo?>(
                  future: _loadPackageInfo(),
                  builder: (context, snapshot) {
                    final String versionText;
                    if (snapshot.connectionState != ConnectionState.done) {
                      versionText = 'Version …';
                    } else if (snapshot.data == null) {
                      versionText = 'Version unavailable';
                    } else {
                      final info = snapshot.data!;
                      versionText =
                          'Version ${info.version} (build ${info.buildNumber})';
                    }
                    return _Section(
                      icon: Icons.info_outline,
                      title: _appName,
                      child: Text(
                        versionText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: Spacing.md),
                // Made by — attribution + selectable contact email.
                _Section(
                  icon: Icons.person_outline,
                  title: 'Made by',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filip Voska',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Spacing.xs),
                      SelectableText(
                        _contactEmail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),
                // Changelog — bundled asset; null/empty shows a fallback line.
                FutureBuilder<String?>(
                  future: _loadChangelog(),
                  builder: (context, snapshot) {
                    final Widget body;
                    if (snapshot.connectionState != ConnectionState.done) {
                      body = Text(
                        'Loading…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    } else {
                      final text = snapshot.data?.trim();
                      if (text == null || text.isEmpty) {
                        body = Text(
                          'Changelog is not available.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      } else {
                        // Parse the release-please subset by hand (no markdown
                        // renderer dependency). A non-empty result renders as
                        // collapsible per-release sections; an empty result
                        // (unexpected shape) degrades to plain text so the page
                        // never loses the changelog.
                        final releases = parseChangelog(text);
                        if (releases.isEmpty) {
                          body = SelectableText(
                            text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          );
                        } else {
                          body = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final release in releases)
                                _ReleaseTile(release: release),
                            ],
                          );
                        }
                      }
                    }
                    return _Section(
                      icon: Icons.history_outlined,
                      title: 'Changelog',
                      child: body,
                    );
                  },
                ),
                const SizedBox(height: Spacing.md),
                // Open-source licenses — standard Flutter license list.
                _Section(
                  icon: Icons.description_outlined,
                  title: 'Legal',
                  child: FutureBuilder<PackageInfo?>(
                    future: _loadPackageInfo(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.gavel_outlined),
                        title: const Text('Open-source licenses'),
                        subtitle: const Text(
                          'View the licenses of bundled libraries.',
                        ),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: _appName,
                          applicationVersion: version,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled card with an icon header, matching the visual weight of the
/// Help screen sections without the accordion behaviour.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// One collapsible release inside the Changelog card — collapsed by default
/// (ExpansionTile's default) so the page stays scannable as history grows.
/// Mirrors the Help screen's accordion pattern (Border() shapes to suppress
/// ExpansionTile's own divider lines).
class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({required this.release});

  final ChangelogRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = release.date;
    return ExpansionTile(
      // Align the header with the card's own padding instead of the default
      // ExpansionTile inset, since this tile lives inside a padded Card.
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        release.version,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: date == null
          ? null
          : Text(
              date,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      childrenPadding: const EdgeInsets.only(bottom: Spacing.sm),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (release.sections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(
              'No details recorded for this release.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final section in release.sections)
            _ReleaseSection(section: section),
      ],
    );
  }
}

/// A grouped change section (Features, Bug Fixes, …) with its bullets.
class _ReleaseSection extends StatelessWidget {
  const _ReleaseSection({required this.section});

  final ChangelogSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.xs),
          child: Text(
            section.heading,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final entry in section.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: _inlineSpans(entry, theme)),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Converts a raw release-please bullet into styled inline spans without a
/// markdown package: `**scope:**` renders bold, and `[text](url)` renders the
/// link text in the primary color (styling only — no tap handler is in scope).
///
/// Defensive per CLAUDE.md: any parse trouble falls back to the raw text so a
/// bullet can never throw while building the page.
List<InlineSpan> _inlineSpans(String raw, ThemeData theme) {
  try {
    final pattern = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)]*)\)');
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in pattern.allMatches(raw)) {
      if (match.start > last) {
        spans.add(TextSpan(text: raw.substring(last, match.start)));
      }
      final bold = match.group(1);
      if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else {
        // Link: show the link text distinguished in the primary color.
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        );
      }
      last = match.end;
    }
    if (last < raw.length) {
      spans.add(TextSpan(text: raw.substring(last)));
    }
    if (spans.isEmpty) return [TextSpan(text: raw)];
    return spans;
  } catch (_) {
    return [TextSpan(text: raw)];
  }
}
