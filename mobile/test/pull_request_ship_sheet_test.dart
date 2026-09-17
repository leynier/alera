import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_ship_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/memory_explorer_preferences_repository.dart';

const _dirtySnapshot = MobileGitStatusSnapshot(
  isRepository: true,
  entries: <MobileGitChange>[
    MobileGitChange(
      path: 'lib/ship.dart',
      area: 'unstaged',
      status: 'modified',
    ),
  ],
);

void main() {
  group('shipShowsWorkingTreeScopeChoice', () {
    test('hides All/Staged when git status has no entries', () {
      expect(
        shipShowsWorkingTreeScopeChoice(const MobileGitStatusSnapshot()),
        isFalse,
      );
    });

    test('keeps All/Staged when the working tree is dirty', () {
      expect(shipShowsWorkingTreeScopeChoice(_dirtySnapshot), isTrue);
    });

    test('keeps All/Staged when status cannot be read', () {
      expect(shipShowsWorkingTreeScopeChoice(null), isTrue);
    });
  });

  group('ShipPullRequestSheet', () {
    testWidgets('hides All/Staged and ships staged on a clean tree', (
      tester,
    ) async {
      MobilePullRequestShipInput? submitted;
      await _pumpSheet(
        tester,
        askWorkingTreeScope: false,
        onSubmit: (input) async {
          submitted = input;
          return null;
        },
      );

      expect(find.text('All Changes'), findsNothing);
      expect(find.text('Staged Changes'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Ship'));
      await tester.pumpAndSettle();
      expect(submitted?.stagedOnly, isTrue);
    });

    testWidgets('keeps All vs Staged when the working tree is dirty', (
      tester,
    ) async {
      await _pumpSheet(tester, askWorkingTreeScope: true);

      expect(find.text('All Changes'), findsOneWidget);
      expect(find.text('Staged Changes'), findsOneWidget);
    });
  });

  group('Ship from the pull request panel', () {
    testWidgets('hides All/Staged when source control is clean', (
      tester,
    ) async {
      final client = _shipClient()
        ..sourceControlSupported = true
        ..gitStatusSnapshot = const MobileGitStatusSnapshot();
      addTearDown(client.dispose);
      await _openPullRequest(tester, client);

      await tester.tap(find.text('Ship Changes'));
      await tester.pumpAndSettle();

      expect(find.text('All Changes'), findsNothing);
      expect(find.text('Staged Changes'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Ship'));
      await tester.pumpAndSettle();
      expect(
        client.calls,
        contains('shipPullRequest main draft:false staged:true'),
      );
    });

    testWidgets('keeps All vs Staged when source control is dirty', (
      tester,
    ) async {
      final client = _shipClient()
        ..sourceControlSupported = true
        ..gitStatusSnapshot = _dirtySnapshot;
      addTearDown(client.dispose);
      await _openPullRequest(tester, client);

      await tester.tap(find.text('Ship Changes'));
      await tester.pumpAndSettle();

      expect(find.text('All Changes'), findsOneWidget);
      expect(find.text('Staged Changes'), findsOneWidget);
    });

    testWidgets('keeps All vs Staged when git status fails', (tester) async {
      final client = _shipClient()
        ..sourceControlSupported = true
        ..gitStatusError = StateError('The runtime is unreachable.');
      addTearDown(client.dispose);
      await _openPullRequest(tester, client);

      await tester.tap(find.text('Ship Changes'));
      await tester.pumpAndSettle();

      expect(find.text('All Changes'), findsOneWidget);
      expect(find.text('Staged Changes'), findsOneWidget);
    });

    testWidgets(
      'keeps All vs Staged when a nested source control root is clean',
      (tester) async {
        final client = _shipClient()
          ..sourceControlSupported = true
          ..sourceControlRootSupported = true
          ..gitStatusSnapshot = _dirtySnapshot;
        addTearDown(client.dispose);
        final preferences = MemoryExplorerPreferencesRepository()
          ..saved['host-1/workspace-1'] = const ExplorerPreferences(
            sourceControlRoot: 'service',
          );
        await _openPullRequest(tester, client, preferences: preferences);

        await tester.tap(find.text('Ship Changes'));
        await tester.pumpAndSettle();

        expect(client.calls, contains('gitStatus workspace-1'));
        expect(client.calls, isNot(contains('gitStatus workspace-1 service')));
        expect(find.text('All Changes'), findsOneWidget);
        expect(find.text('Staged Changes'), findsOneWidget);
      },
    );
  });
}

FakeTerminalClient _shipClient() {
  return FakeTerminalClient()
    ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
    ..pullRequestsSupported = true
    ..pullRequestActionsSupported = true
    ..pullRequestShipSupported = true
    ..pullRequest = MobilePullRequestSnapshot.fromJson(const <String, Object?>{
      'branch': 'feat/actions',
      'provider': 'github',
      'authStatus': 'authenticated',
      'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
      'aiAssistEnabled': true,
      'baseBranches': <String>['develop', 'feat/actions', 'main'],
      'suggestedBaseBranch': 'main',
      'unavailableReason': 'No open pull request is linked to this branch.',
    });
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required bool askWorkingTreeScope,
  Future<String?> Function(MobilePullRequestShipInput input)? onSubmit,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShipPullRequestSheet(
                context,
                headBranch: 'feat/ship',
                baseBranches: const ['main'],
                suggestedBaseBranch: 'main',
                askWorkingTreeScope: askWorkingTreeScope,
                onSubmit: onSubmit ?? (_) async => null,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _openPullRequest(
  WidgetTester tester,
  FakeTerminalClient client, {
  MemoryExplorerPreferencesRepository? preferences,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        if (preferences != null)
          explorerPreferencesRepositoryProvider.overrideWith(
            (ref) => preferences,
          ),
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
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pull Request'));
  await tester.pumpAndSettle();
}
