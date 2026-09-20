import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/services/external_link_launcher.dart';
import 'package:rtsp_mixer/core/services/update_checker.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/core/widgets/update_banner.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart'
    show storageProvider;

import '../../support/logging.dart';

const _update = AppUpdate(
  version: '1.15.0',
  releaseUrl: 'https://github.com/fvoska/rtsp-mixer/releases/tag/v1.15.0',
);

void main() {
  installAppLoggerTestIsolation();

  late List<Uri> opened;
  late StorageService storage;

  setUp(() {
    opened = [];
    storage = StorageService.inMemory();
    externalLinkOpener = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  tearDown(() {
    externalLinkOpener = defaultExternalLinkOpener;
  });

  Future<void> pump(WidgetTester tester, AppUpdate? update) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          updateCheckProvider.overrideWith((ref) async => update),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [UpdateBanner()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the available version', (tester) async {
    await pump(tester, _update);

    expect(find.byType(UpdateBanner), findsOneWidget);
    expect(find.textContaining('1.15.0'), findsOneWidget);
  });

  testWidgets('the download action opens the update URL exactly once',
      (tester) async {
    await pump(tester, _update);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse(_update.downloadUrl)]);
  });

  testWidgets('dismissing removes the strip in the same frame', (tester) async {
    await pump(tester, _update);
    expect(find.textContaining('1.15.0'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.textContaining('1.15.0'), findsNothing);
    expect(find.text('Download'), findsNothing);
    expect(tester.getSize(find.byType(UpdateBanner)), Size.zero);
  });

  testWidgets('dismissing records the version so it stays hidden',
      (tester) async {
    await pump(tester, _update);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(await storage.read(kDismissedUpdateVersionKey), '1.15.0');
  });

  testWidgets('renders nothing when there is no update', (tester) async {
    await pump(tester, null);

    expect(find.byType(UpdateBanner), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.getSize(find.byType(UpdateBanner)), Size.zero);
  });

  testWidgets('takes no space while the check is still in flight',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          updateCheckProvider.overrideWith((ref) async {
            // Never completes during this test — the loading state must look
            // exactly like "no update".
            return Completer<AppUpdate?>().future;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [UpdateBanner()])),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(UpdateBanner)), Size.zero);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a failed check renders nothing rather than an error',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          updateCheckProvider
              .overrideWith((ref) async => throw StateError('offline')),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [UpdateBanner()])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(UpdateBanner)), Size.zero);
  });

  testWidgets('a non-http(s) download target offers no download action',
      (tester) async {
    // Inert beats fake-tappable: the same rule the changelog links follow.
    await pump(
      tester,
      const AppUpdate(version: '1.15.0', releaseUrl: 'javascript:alert(1)'),
    );

    expect(find.textContaining('1.15.0'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(opened, isEmpty);
  });
}
