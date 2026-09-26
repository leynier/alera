import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/fake_workspace_hosts_client.dart';
import 'support/source_control_fixtures.dart';

const _remote = WorkspaceSummary(
  id: 'workspace-remote',
  hostId: 'ssh-mac',
  projectId: 'project-1',
  name: 'Remote',
  path: '/Users/dev/repo',
);

void main() {
  group('workspace hosts controller', () {
    test('lists hosts once and refreshes on sshTargetsChanged', () async {
      final client = FakeRemoteWorkspacesClient();
      final container = _container(client);

      final directory = await container.read(
        workspaceHostsControllerProvider('host-1').future,
      );
      expect(directory.supported, isTrue);
      expect(directory.hostOf(_remote)?.label, 'Studio Mac (macOS)');

      client
        ..workspaceHosts = const <MobileWorkspaceHost>[
          MobileWorkspaceHost(id: 'ssh-mac', alias: 'Renamed', platform: 'mac'),
        ]
        ..emitEvent('workspacesChanged');
      await Future.pause(Duration.zero);
      expect(_hostRequests(client), 1);

      client.emitEvent('sshTargetsChanged');
      await Future.pause(Duration.zero);
      final refreshed = await container.read(
        workspaceHostsControllerProvider('host-1').future,
      );
      expect(_hostRequests(client), 2);
      expect(refreshed.hostOf(_remote)?.alias, 'Renamed');
    });

    test('never asks a runtime without the capability', () async {
      final client = FakeRemoteWorkspacesClient()
        ..remoteWorkspacesSupported = false;
      final container = _container(client);

      final directory = await container.read(
        workspaceHostsControllerProvider('host-1').future,
      );
      expect(directory.supported, isFalse);
      expect(directory.hostOf(_remote), isNull);
      expect(_hostRequests(client), 0);

      final plain = FakeTerminalClient();
      final older = await _container(plain)
          .read(workspaceHostsControllerProvider('host-1').future);
      expect(older.hostOf(_remote), isNull);
    });

    test('a failed load still marks the workspace under its host id', () async {
      final client = FakeRemoteWorkspacesClient()
        ..workspaceHostsError = StateError('host unreachable');
      final container = _container(client);

      final directory = await container.read(
        workspaceHostsControllerProvider('host-1').future,
      );
      expect(directory.hostOf(_remote)?.label, 'ssh-mac');
    });

    test('a failed refresh keeps the last directory', () async {
      final client = FakeRemoteWorkspacesClient();
      final container = _container(client);
      await container.read(workspaceHostsControllerProvider('host-1').future);

      client
        ..workspaceHostsError = StateError('host unreachable')
        ..emitEvent('sshTargetsChanged');
      await Future.pause(Duration.zero);
      final directory = await container.read(
        workspaceHostsControllerProvider('host-1').future,
      );
      expect(_hostRequests(client), 2);
      expect(directory.hostOf(_remote)?.alias, 'Studio Mac');
    });
  });

  testWidgets('a remote workspace opens every panel through the hub', (
    tester,
  ) async {
    final client = _panelsClient(FakeRemoteWorkspacesClient());
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);

    expect(find.byKey(const Key('workspace-title-host')), findsOneWidget);
    expect(find.byTooltip('Studio Mac (macOS)'), findsOneWidget);

    await _openWorkspacePanel(tester, 'Explorer');
    expect(find.text('readme.md'), findsOneWidget);
    await _openWorkspacePanel(tester, 'Source Control');
    await _openWorkspacePanel(tester, 'Pull Request');
    await _openWorkspacePanel(tester, 'Search');
    await tester.enterText(find.byType(TextField).first, 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      client.calls,
      containsAll(<Matcher>[
        startsWith('listExplorerChildren workspace-remote'),
        startsWith('gitStatus workspace-remote'),
        startsWith('pullRequestSnapshot workspace-remote'),
        startsWith('searchWorkspace workspace-remote needle'),
      ]),
    );
  });

  testWidgets('a remote workspace can generate its commit message', (
    tester,
  ) async {
    final client = _panelsClient(FakeRemoteWorkspacesClient())
      ..commitMessageGenerationSupported = true
      ..onGenerateCommitMessage = (_) async =>
          const GeneratedCommitMessage(message: 'Add login flow');
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);

    await _openWorkspacePanel(tester, 'Source Control');
    await tester.tap(find.byTooltip('Generate Commit Message'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('generateCommitMessage workspace-remote'));
    expect(find.text('Add login flow'), findsOneWidget);
  });

  testWidgets('an older runtime keeps the panels and shows no host marker', (
    tester,
  ) async {
    final client = _panelsClient(
      FakeRemoteWorkspacesClient()..remoteWorkspacesSupported = false,
    );
    addTearDown(client.dispose);
    await _pumpWorkspace(tester, client);

    expect(find.byKey(const Key('workspace-title-host')), findsNothing);
    expect(_hostRequests(client), 0);
    await _openWorkspacePanel(tester, 'Explorer');
    expect(
      client.calls,
      contains(startsWith('listExplorerChildren workspace-remote')),
    );
  });
}

int _hostRequests(FakeRemoteWorkspacesClient client) =>
    client.calls.where((call) => call == 'listWorkspaceHosts').length;

FakeRemoteWorkspacesClient _panelsClient(FakeRemoteWorkspacesClient client) =>
    client
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(
          id: 'tab-1',
          title: 'Terminal 1',
          workspaceId: 'workspace-remote',
        ),
      ]
      ..explorerSupported = true
      ..workspaceSearchSupported = true
      ..sourceControlSupported = true
      ..sourceControlWritesSupported = true
      ..pullRequestsSupported = true
      ..explorerEntries = const <MobileExplorerEntry>[
        MobileExplorerEntry(
          relativePath: 'readme.md',
          name: 'readme.md',
          kind: 'file',
        ),
      ]
      ..gitStatusSnapshot = MobileGitStatusSnapshot(
        isRepository: true,
        branch: 'main',
        writable: true,
        entries: <MobileGitChange>[stagedChange()],
        actions: const MobileSourceControlActions(commit: true, fetch: true),
        primaryAction: 'commit',
        aiCommitMessageEnabled: true,
      );

ProviderContainer _container(FakeTerminalClient client) {
  final container = ProviderContainer(
    overrides: [
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    workspaceHostsControllerProvider('host-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
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
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const WorkspaceTabsScreen(hostId: 'host-1', workspace: _remote),
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
