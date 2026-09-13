import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

const _firstSnapshot = MobileGitStatusSnapshot(
  isRepository: true,
  branch: 'main',
  entries: <MobileGitChange>[
    MobileGitChange(
      path: 'lib/first.dart',
      area: 'unstaged',
      status: 'modified',
    ),
  ],
);

const _secondSnapshot = MobileGitStatusSnapshot(
  isRepository: true,
  branch: 'main',
  entries: <MobileGitChange>[
    MobileGitChange(path: 'lib/second.dart', area: 'unstaged', status: 'added'),
  ],
);

void main() {
  group('SourceControlController.reload', () {
    test('keeps the last snapshot while the refresh is in flight', () async {
      final client = _panelsClient()..gitStatusSnapshot = _firstSnapshot;
      final container = _containerFor(client);
      final provider = sourceControlControllerProvider('host-1', 'workspace-1');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);

      final gate = client.gitStatusGate = Completer<void>();
      client.gitStatusSnapshot = _secondSnapshot;
      final reload = container.read(provider.notifier).reload();
      await Future<void>.delayed(Duration.zero);

      final loading = container.read(provider);
      expect(loading.isLoading, isTrue);
      expect(loading.value, _firstSnapshot);

      gate.complete();
      await reload;
      expect(container.read(provider).value, _secondSnapshot);
    });

    test('keeps the last snapshot when the refresh fails', () async {
      final client = _panelsClient()..gitStatusSnapshot = _firstSnapshot;
      final container = _containerFor(client);
      final provider = sourceControlControllerProvider('host-1', 'workspace-1');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);

      client.gitStatusError = StateError('runtime connection lost');
      await container.read(provider.notifier).reload();

      final failed = container.read(provider);
      expect(failed, isA<AsyncError<MobileGitStatusSnapshot>>());
      expect(failed.hasValue, isTrue);
      expect(failed.value, _firstSnapshot);
    });
  });

  testWidgets('source control keeps its list on screen while refreshing', (
    tester,
  ) async {
    final client = _panelsClient()..gitStatusSnapshot = _firstSnapshot;
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Source Control');
    expect(find.text('first.dart'), findsOneWidget);

    final gate = client.gitStatusGate = Completer<void>();
    client.gitStatusSnapshot = _secondSnapshot;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump();

    expect(find.text('first.dart'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('second.dart'), findsOneWidget);
    expect(find.text('first.dart'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a failed source control refresh keeps the list and explains', (
    tester,
  ) async {
    final client = _panelsClient()..gitStatusSnapshot = _firstSnapshot;
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Source Control');

    client.gitStatusError = StateError('runtime connection lost');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('first.dart'), findsOneWidget);
    final notice = find.widgetWithText(
      AleraNotice,
      'Could not refresh source control. Bad state: runtime connection lost',
    );
    expect(notice, findsOneWidget);
    expect(
      find.descendant(of: notice, matching: find.text('Retry')),
      findsOneWidget,
    );

    client.gitStatusError = null;
    await tester.tap(find.descendant(of: notice, matching: find.text('Retry')));
    await tester.pumpAndSettle();
    expect(find.byType(AleraNotice), findsOneWidget);
    expect(find.textContaining('Could not refresh'), findsNothing);
  });

  testWidgets('a clean working tree can still be refreshed', (tester) async {
    final client = _panelsClient()
      ..gitStatusSnapshot = const MobileGitStatusSnapshot(
        isRepository: true,
        branch: 'main',
      );
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Source Control');
    expect(find.text('Clean working tree'), findsOneWidget);

    client.gitStatusSnapshot = _firstSnapshot;
    await tester.tap(find.widgetWithText(TextButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('first.dart'), findsOneWidget);
    expect(
      client.calls.where((call) => call == 'gitStatus workspace-1'),
      hasLength(2),
    );
  });

  testWidgets('explorer keeps its rows on screen while refreshing', (
    tester,
  ) async {
    final client = _panelsClient()
      ..explorerEntries = const <MobileExplorerEntry>[
        MobileExplorerEntry(
          relativePath: 'readme.md',
          name: 'readme.md',
          kind: 'file',
        ),
      ];
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Explorer');
    expect(find.text('readme.md'), findsOneWidget);

    final gate = client.explorerGate = Completer<void>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump();

    expect(find.text('readme.md'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('readme.md'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('pull request keeps its review on screen while refreshing', (
    tester,
  ) async {
    final client = _panelsClient()
      ..pullRequest = MobilePullRequestSnapshot.fromJson(
        const <String, Object?>{
          'branch': 'feat/panels',
          'review': <String, Object?>{
            'number': 756,
            'title': 'Keep panels visible',
            'state': 'OPEN',
            'url': '',
            'checks': <Object?>[],
            'comments': <Object?>[],
          },
        },
      );
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Pull Request');
    expect(find.text('Keep panels visible'), findsOneWidget);

    final gate = client.pullRequestGate = Completer<void>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keep panels visible'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a host reconnect does not blank source control', (tester) async {
    final client = _panelsClient()..gitStatusSnapshot = _firstSnapshot;
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);
    await _openWorkspacePanel(tester, 'Source Control');
    expect(find.text('first.dart'), findsOneWidget);

    // A reconnect rebuilds the client provider every panel watches, which is
    // a dependency change rather than a refresh the panel asked for.
    final gate = client.gitStatusGate = Completer<void>();
    client.gitStatusSnapshot = _secondSnapshot;
    ProviderScope.containerOf(tester.element(find.byType(WorkspaceTabsScreen)))
        .invalidate(workspaceClientProvider('host-1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('first.dart'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('second.dart'), findsOneWidget);
  });
}

FakeTerminalClient _panelsClient() => FakeTerminalClient()
  ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
  ..explorerSupported = true
  ..workspaceSearchSupported = true
  ..sourceControlSupported = true
  ..pullRequestsSupported = true;

ProviderContainer _containerFor(FakeTerminalClient client) {
  // Automatic retries would keep refreshing a failure after the test ends.
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return container;
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  FakeTerminalClient client,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const WorkspaceTabsScreen(
          hostId: 'host-1',
          workspace: WorkspaceSummary(
            id: 'workspace-1',
            projectId: 'project-1',
            name: 'Workspace',
            path: '/repo',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openWorkspacePanel(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
