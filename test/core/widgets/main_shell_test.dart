import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rtsp_mixer/core/widgets/main_shell.dart';
import 'package:rtsp_mixer/features/auth/models/auth_state.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/monitoring/providers/session_history_provider.dart';

// Minimal fakes so ActiveSessionBar (inside MainShell) resolves without disk.
class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      AuthState.authenticated(host: 'h', resumeMonitoring: false);
}

class _FakeSession extends SessionHistoryNotifier {
  @override
  Future<SessionHistory> build() async => const SessionHistory();
}

/// Branch screen that counts how many times its State is created (initState).
class _Probe extends StatefulWidget {
  const _Probe(this.label, this.mounts);
  final String label;
  final Map<String, int> mounts;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.mounts[widget.label] = (widget.mounts[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('screen-${widget.label}')));
}

GoRouter _router(Map<String, int> mounts) => GoRouter(
      initialLocation: '/monitoring',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/monitoring',
                  builder: (_, _) => _Probe('mon', mounts))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/sessions', builder: (_, _) => _Probe('ses', mounts))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/logs', builder: (_, _) => _Probe('log', mounts))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/settings', builder: (_, _) => _Probe('set', mounts))
            ]),
          ],
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, Map<String, int> mounts) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuth()),
        sessionHistoryProvider.overrideWith(() => _FakeSession()),
      ],
      child: MaterialApp.router(routerConfig: _router(mounts)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('branch state survives tab switches and the rail breakpoint',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600); // 400dp — phone
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.reset());

    final mounts = <String, int>{};
    await _pump(tester, mounts);

    expect(find.text('screen-mon'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(mounts['mon'], 1);

    // Switch to Sessions, then back to Monitor.
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    expect(find.text('screen-ses'), findsOneWidget);
    expect(mounts['ses'], 1);

    await tester.tap(find.text('Monitor'));
    await tester.pumpAndSettle();
    expect(find.text('screen-mon'), findsOneWidget);
    // The monitoring branch was kept alive — NOT re-created.
    expect(mounts['mon'], 1,
        reason: 'monitor branch must survive a tab switch');

    // Cross the 600dp breakpoint to the NavigationRail layout.
    tester.view.physicalSize = const Size(1600, 1600); // 800dp — rail
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(mounts['mon'], 1,
        reason: 'monitor branch must survive the rail/bottom-nav breakpoint');

    // Back to phone width.
    tester.view.physicalSize = const Size(800, 1600);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(mounts['mon'], 1);
  });

  testWidgets('tapping tabs navigates between branches', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.reset());

    final mounts = <String, int>{};
    await _pump(tester, mounts);

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('screen-log'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('screen-set'), findsOneWidget);
  });
}
