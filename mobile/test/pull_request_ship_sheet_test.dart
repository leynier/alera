import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_ship_follow_up.dart';
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
        onSubmit: (request) async {
          submitted = request.input;
          return (error: null, notice: null);
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

  group('Ship follow-ups', () {
    testWidgets('stay hidden without an agent picker', (tester) async {
      await _pumpSheet(tester, askWorkingTreeScope: false);
      expect(find.text('After Shipping'), findsNothing);
    });

    testWidgets('pick the agent first and ship a ready pull request', (
      tester,
    ) async {
      final events = <String>[];
      PullRequestShipRequest? submitted;
      await _pumpSheet(
        tester,
        askWorkingTreeScope: false,
        initialFollowUp: .watchFixAndMerge,
        chooseAgent: (mode) async {
          events.add('choose ${mode.name}');
          return const AgentTaskDispatchBinding(tabId: 'tab-1');
        },
        onSubmit: (request) async {
          events.add('ship');
          submitted = request;
          return (error: null, notice: null);
        },
      );

      expect(find.text('After Shipping'), findsOneWidget);
      expect(find.text('Merge Conflicts'), findsOneWidget);
      expect(find.text('Merging needs a ready pull request.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ship and Merge'));
      await tester.pumpAndSettle();

      expect(events, <String>['choose fixAndMerge', 'ship']);
      expect(submitted?.followUp, PullRequestShipFollowUp.watchFixAndMerge);
      expect(submitted?.binding?.tabId, 'tab-1');
      expect(submitted?.input.draft, isFalse);
    });

    testWidgets('a watch that fails to start replaces the success message', (
      tester,
    ) async {
      const notice =
          'Pull request #42 was created, but watching could not start.';
      await _pumpSheet(
        tester,
        askWorkingTreeScope: false,
        initialFollowUp: .watchAndFix,
        chooseAgent: (_) async => const AgentTaskDispatchBinding(tabId: 't'),
        onSubmit: (_) async => (error: null, notice: notice),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Ship and Watch'));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      expect(find.text('Ship changes completed.'), findsNothing);
      expect(find.byType(ShipPullRequestSheet), findsNothing);
    });

    testWidgets('declining the agent keeps the sheet and ships nothing', (
      tester,
    ) async {
      var shipped = false;
      await _pumpSheet(
        tester,
        askWorkingTreeScope: false,
        initialFollowUp: .watchAndFix,
        chooseAgent: (_) async => null,
        onSubmit: (_) async {
          shipped = true;
          return (error: null, notice: null);
        },
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Ship and Watch'));
      await tester.pumpAndSettle();
      expect(shipped, isFalse);
      expect(find.byType(ShipPullRequestSheet), findsOneWidget);
    });

    testWidgets('need at least one problem to watch', (tester) async {
      var chose = false;
      await _pumpSheet(
        tester,
        askWorkingTreeScope: false,
        initialFollowUp: .watchAndFix,
        initialWatchScope: const PullRequestAgentWatchScope(
          checks: false,
          comments: false,
          conflicts: false,
        ),
        chooseAgent: (_) async {
          chose = true;
          return null;
        },
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Ship and Watch'));
      await tester.pumpAndSettle();
      expect(chose, isFalse);
      expect(
        find.text('Choose at least one problem to watch.'),
        findsOneWidget,
      );
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
  Future<PullRequestShipOutcome> Function(PullRequestShipRequest request)?
  onSubmit,
  Future<AgentTaskDispatchBinding?> Function(PullRequestAgentWatchMode mode)?
  chooseAgent,
  PullRequestShipFollowUp initialFollowUp = PullRequestShipFollowUp.none,
  PullRequestAgentWatchScope initialWatchScope =
      PullRequestAgentWatchScope.defaults,
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
                initialFollowUp: initialFollowUp,
                initialWatchScope: initialWatchScope,
                chooseAgent: chooseAgent,
                onSubmit: onSubmit ?? (_) async => (error: null, notice: null),
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
