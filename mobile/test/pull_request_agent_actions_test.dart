import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_agent_actions.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dispatch_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/fake_terminal_client.dart';

MobilePullRequestSnapshot _snapshot({
  List<Map<String, Object?>> checks = const <Map<String, Object?>>[],
  bool withReview = true,
}) {
  return MobilePullRequestSnapshot.fromJson(<String, Object?>{
    'branch': 'feat/actions',
    'provider': 'github',
    'authStatus': 'authenticated',
    'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
    'canComment': true,
    'mergeMethods': <String>['squash'],
    'baseBranches': <String>['main'],
    'suggestedBaseBranch': 'main',
    'review': withReview
        ? <String, Object?>{
            'number': 700,
            'title': 'feat: mobile actions',
            'state': 'OPEN',
            'url': 'https://github.com/leynier/alera/pull/700',
            'headSha': 'abc123',
            'checks': checks,
            'comments': <Object?>[],
          }
        : null,
    if (!withReview)
      'unavailableReason': 'No open pull request is linked to this branch.',
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  testWidgets('watch sheet starts either mode with the chosen scope', (
    tester,
  ) async {
    late PullRequestWatchSheetResult result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final selected = await showPullRequestWatchSheet(
                  context,
                  initialScope: PullRequestAgentWatchScope.defaults,
                  canFixAndMerge: true,
                );
                if (selected != null) {
                  result = selected;
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Failed Checks'), findsOneWidget);
    expect(find.text('Review Comments'), findsOneWidget);
    expect(find.text('Merge Conflicts'), findsOneWidget);
    await tester.tap(find.text('Review Comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    expect(result.scope, const PullRequestAgentWatchScope(comments: false));
  });

  testWidgets('watch sheet disables modes for an empty scope', (tester) async {
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final selected = await showPullRequestWatchSheet(
                  context,
                  initialScope: const PullRequestAgentWatchScope(
                    checks: false,
                    comments: false,
                    conflicts: false,
                  ),
                  canFixAndMerge: true,
                );
                started = selected != null;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch and Fix'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(started, isFalse);
    expect(find.text('Watch and Fix'), findsOneWidget);
  });

  testWidgets('dispatch sheet lists profiles hidden from the new-tab menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const Scaffold(
          body: WorkspaceAgentCommentDispatchSheet(
            title: 'Restack',
            runningAgents: [],
            profiles: <AgentProfileSummary>[
              AgentProfileSummary(
                id: 'hidden',
                name: 'Hidden Profile',
                agentType: 'codex',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Restack'), findsOneWidget);
    expect(find.text('Hidden Profile'), findsOneWidget);
  });

  testWidgets('restack sits above merge and opens the shared picker', (
    tester,
  ) async {
    final client = _client(_snapshot());
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    final restack = tester.getTopLeft(
      find.byKey(const Key('pull-request-restack-button')),
    );
    final merge = tester.getTopLeft(find.text('Squash and Merge'));
    expect(restack.dy, lessThan(merge.dy));

    await tester.tap(find.byKey(const Key('pull-request-restack-button')));
    await tester.pumpAndSettle();
    expect(find.text('Restack'), findsWidgets);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Hidden Grok'), findsOneWidget);
  });

  testWidgets('fix failed checks hides while a watch is running', (
    tester,
  ) async {
    final client = _client(
      _snapshot(
        checks: <Map<String, Object?>>[
          <String, Object?>{'name': 'build', 'bucket': 'fail'},
        ],
      ),
    );
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.text('Fix Failed Checks'), findsOneWidget);
    await tester.tap(find.byTooltip('Ask Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();

    expect(find.text('Fix Failed Checks'), findsNothing);
    expect(find.text('Watching: Fix'), findsOneWidget);
    await tester.tap(find.byTooltip('Watching: Fix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop Watching'));
    await tester.pumpAndSettle();
    expect(find.text('Fix Failed Checks'), findsOneWidget);
  });

  testWidgets('restack stays on a linked review without write capability', (
    tester,
  ) async {
    final client = _client(_snapshot())..pullRequestActionsSupported = false;
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.textContaining('Comments are read-only'), findsOneWidget);
    expect(find.text('Squash and Merge'), findsNothing);
    expect(
      find.byKey(const Key('pull-request-restack-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pull-request-restack-button')));
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets('restack on the empty composer sits above ship', (tester) async {
    final client = _client(_snapshot(withReview: false))
      ..pullRequestShipSupported = true;
    client.pullRequest = _snapshot(withReview: false).copyWithAiAssist();
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(
      find.byKey(const Key('pull-request-restack-button')),
      findsOneWidget,
    );
    final restack = tester.getTopLeft(
      find.byKey(const Key('pull-request-restack-button')),
    );
    final ship = tester.getTopLeft(find.text('Ship Changes'));
    expect(restack.dy, lessThan(ship.dy));
  });
}

extension on MobilePullRequestSnapshot {
  MobilePullRequestSnapshot copyWithAiAssist() {
    return MobilePullRequestSnapshot.fromJson(<String, Object?>{
      'branch': branch,
      'provider': provider,
      'authStatus': authStatus,
      'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
      'unavailableReason': unavailableReason,
      'aiAssistEnabled': true,
      'baseBranches': baseBranches,
      'suggestedBaseBranch': suggestedBaseBranch,
    });
  }
}

FakeTerminalClient _client(MobilePullRequestSnapshot snapshot) {
  return FakeTerminalClient()
    ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
    ..pullRequestsSupported = true
    ..pullRequestActionsSupported = true
    ..pullRequest = snapshot
    ..agentProfiles = const <AgentProfileSummary>[
      AgentProfileSummary(id: 'profile-1', name: 'Codex', agentType: 'codex'),
      AgentProfileSummary(
        id: 'profile-2',
        name: 'Hidden Grok',
        agentType: 'grok',
      ),
    ];
}

Future<void> _openPullRequest(
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
