import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/theme/app_theme.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/monitoring/models/session.dart';
import 'package:rtsp_mixer/features/monitoring/providers/session_history_provider.dart';
import 'package:rtsp_mixer/features/monitoring/widgets/active_session_bar.dart';

/// Test double — returns a pre-seeded SessionHistory without touching disk.
class _FakeSessionHistoryNotifier extends SessionHistoryNotifier {
  _FakeSessionHistoryNotifier(this.seed);
  final SessionHistory seed;

  @override
  Future<SessionHistory> build() async => seed;
}

/// Test double — returns a pre-seeded AuthState without touching storage.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this.seed);
  final AuthState seed;

  @override
  Future<AuthState> build() async => seed;
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required int selectedIndex,
  Session? currentSession,
  bool resumeMonitoring = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionHistoryProvider.overrideWith(
          () => _FakeSessionHistoryNotifier(
            SessionHistory(current: currentSession, past: const []),
          ),
        ),
        authNotifierProvider.overrideWith(
          () => _FakeAuthNotifier(
            AuthState.authenticated(
              host: '10.0.0.1',
              resumeMonitoring: resumeMonitoring,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ActiveSessionBar(selectedIndex: selectedIndex),
          ),
        ),
      ),
    ),
  );
  // Let the AsyncNotifier settle.
  await tester.pump(const Duration(milliseconds: 50));
}

Session _liveSession() => Session(
      id: 'sess-1',
      startedAt: DateTime.now().subtract(const Duration(minutes: 7)),
      endedAt: null,
      events: const [],
      cameras: const [(id: 'cam1', name: 'Nursery')],
    );

void main() {
  group('ActiveSessionBar visibility', () {
    testWidgets('hidden on Monitor tab even when a session is active',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 0,
        currentSession: _liveSession(),
      );
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('hidden when no session and no resume pending', (tester) async {
      await _pumpBar(tester, selectedIndex: 1);
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('shown with uptime when a session is active on non-monitor tab',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 1,
        currentSession: _liveSession(),
      );
      // Uptime format is "7m" for a 7-minute-old session.
      expect(find.text('Monitoring · 7m'), findsOneWidget);
    });

    testWidgets(
        'shows "resuming…" when auth signals resume but session not yet set',
        (tester) async {
      // Relaunch race: was_monitoring=true is on disk, auth has surfaced it
      // via resumeMonitoring, but SessionHistoryNotifier.beginSession hasn't
      // run yet. The user must still see the bar so they can tap-to-return.
      await _pumpBar(
        tester,
        selectedIndex: 1,
        resumeMonitoring: true,
      );
      expect(find.text('Monitoring · resuming…'), findsOneWidget);
    });

    testWidgets(
        'resume flag is ignored on Monitor tab (inline banner takes over)',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 0,
        resumeMonitoring: true,
      );
      expect(find.textContaining('Monitoring'), findsNothing);
    });

    testWidgets('actual session beats resume flag (uptime not "resuming…")',
        (tester) async {
      await _pumpBar(
        tester,
        selectedIndex: 2,
        currentSession: _liveSession(),
        resumeMonitoring: true,
      );
      expect(find.text('Monitoring · resuming…'), findsNothing);
      expect(find.text('Monitoring · 7m'), findsOneWidget);
    });
  });
}
