import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart' show storageProvider;
import '../services/external_link_launcher.dart';
import '../services/update_checker.dart';
import '../theme/spacing.dart';

/// Strip telling the parent a newer Roomtone build is on GitHub, with a
/// one-tap route to the download.
///
/// Self-hiding like `ActiveSessionBar`: it renders `SizedBox.shrink` — taking
/// no layout space at all — whenever there is nothing to say. The update
/// check's loading and error states both collapse to "nothing to say", so a
/// slow or failed check is visually identical to today's app.
///
/// Dismissal is per version: hiding 1.15.0 stays hidden across relaunches,
/// but 1.16.0 re-arms the strip.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  /// Dismissed during this run. The persisted key handles later launches;
  /// this makes the strip disappear in the frame the user taps.
  bool _dismissed = false;

  void _dismiss(AppUpdate update) {
    setState(() => _dismissed = true);
    // Fire-and-forget: the helper swallows its own failures, and losing the
    // memory costs one re-shown banner, never an exception in the UI.
    rememberDismissedUpdate(ref.read(storageProvider), update.version);
  }

  @override
  Widget build(BuildContext context) {
    // Watched before the early return so the pinned result is not re-fetched
    // after a dismissal.
    // `.value` (not the removed `valueOrNull`) — in Riverpod 3 it is the
    // nullable accessor: loading and error both read as null, which is
    // exactly the "nothing to say" this widget wants.
    final update = ref.watch(updateCheckProvider).value;
    if (update == null || _dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A non-http(s) target renders no action at all rather than a button that
    // silently does nothing — the same rule the changelog links follow.
    final link = tryParseLaunchableLink(update.downloadUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.sm, Spacing.sm),
        decoration: BoxDecoration(
          // The calm secondary pair rather than the error pair: a new build is
          // information, not a fault.
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(Radii.inner),
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Roomtone ${update.version} is available',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            if (link != null)
              TextButton(
                // openExternalLink logs, refuses non-http(s) schemes and never
                // throws, so there is nothing to await or catch here.
                onPressed: () => openExternalLink(link),
                child: const Text('Download'),
              ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Dismiss',
              color: scheme.onSecondaryContainer,
              onPressed: () => _dismiss(update),
            ),
          ],
        ),
      ),
    );
  }
}
