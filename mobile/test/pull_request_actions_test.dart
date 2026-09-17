import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_operation_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/fake_terminal_client.dart';

part 'pull_request_actions_widget_cases.dart';
part 'pull_request_actions_removal_cases.dart';

MobilePullRequestSnapshot _snapshot({
  String state = 'OPEN',
  bool isDraft = false,
  String? mergeable = 'MERGEABLE',
  List<String> mergeMethods = const <String>['squash', 'rebase'],
  List<Map<String, Object?>> comments = const <Map<String, Object?>>[],
  bool withReview = true,
  bool aiAssistEnabled = false,
}) {
  return MobilePullRequestSnapshot.fromJson(<String, Object?>{
    'branch': 'feat/actions',
    'provider': 'github',
    'authStatus': 'authenticated',
    'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
    'canComment': state == 'OPEN',
    'viewerLogin': 'me',
    'mergeMethods': mergeMethods,
    'baseBranches': <String>['develop', 'feat/actions', 'main'],
    'suggestedBaseBranch': 'main',
    'aiAssistEnabled': aiAssistEnabled,
    'review': withReview
        ? <String, Object?>{
            'number': 700,
            'title': 'feat: mobile actions',
            'state': state,
            'isDraft': isDraft,
            'mergeable': mergeable,
            'url': 'https://github.com/leynier/alera/pull/700',
            'checks': <Object?>[],
            'comments': comments,
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

  group('availablePullRequestReviewActions', () {
    List<String> labels(
      MobilePullRequestSnapshot snapshot, {
      bool offerRemoveWorkspace = true,
    }) => <String>[
      for (final action in availablePullRequestReviewActions(
        snapshot,
        offerRemoveWorkspace: offerRemoveWorkspace,
      ))
        action.label,
    ];

    test('an open pull request offers merges, draft, close, and unlink', () {
      expect(labels(_snapshot()), <String>[
        'Squash and Merge',
        'Rebase and Merge',
        'Convert To Draft',
        'Close Pull Request',
        'Unlink Pull Request',
      ]);
    });

    test('a draft offers ready first and cannot merge', () {
      final snapshot = _snapshot(isDraft: true);
      expect(labels(snapshot).first, 'Mark Ready For Review');
      expect(labels(snapshot), isNot(contains('Convert To Draft')));
      final merge = availablePullRequestReviewActions(snapshot)
          .firstWhere((action) => action.kind == .merge);
      expect(pullRequestReviewActionEnabled(merge, snapshot.review!), isFalse);
    });

    test('a conflicting pull request lists merges but disables them', () {
      final snapshot = _snapshot(mergeable: 'CONFLICTING');
      final merge = availablePullRequestReviewActions(snapshot).first;
      expect(merge.kind, MobilePullRequestReviewActionKind.merge);
      expect(pullRequestReviewActionEnabled(merge, snapshot.review!), isFalse);
    });

    test('a merged pull request defaults to Remove Workspace', () {
      expect(labels(_snapshot(state: 'MERGED')), <String>[
        'Remove Workspace',
        'Unlink Pull Request',
      ]);
    });

    test('a merged pull request omits Remove Workspace when not offered', () {
      expect(
        labels(_snapshot(state: 'MERGED'), offerRemoveWorkspace: false),
        <String>['Unlink Pull Request'],
      );
    });

    test('a closed pull request only offers unlink', () {
      expect(labels(_snapshot(state: 'CLOSED')), <String>[
        'Unlink Pull Request',
      ]);
    });

    test('prefers the first listed merge method', () {
      expect(
        preferredMobilePullRequestMergeMethod(const <String>[
          'octopus',
          'squash',
          'rebase',
        ]),
        MobilePullRequestMergeMethod.squash,
      );
    });

    test('unknown merge methods are ignored', () {
      expect(
        labels(_snapshot(mergeMethods: <String>['octopus', 'mergeCommit'])),
        contains('Create Merge Commit'),
      );
    });
  });

  test('confirmation copy matches the desktop dialogs', () {
    const close = MobilePullRequestReviewAction(kind: .close);
    final copy = pullRequestActionConfirmation(close, 7);
    expect(copy.title, 'Close Pull Request #7?');
    expect(copy.destructive, isTrue);
    const squash = MobilePullRequestReviewAction(
      kind: .merge,
      method: MobilePullRequestMergeMethod.squash,
    );
    expect(
      pullRequestActionConfirmation(squash, 7).title,
      'Squash and Merge PR #7?',
    );
  });

  test('runtime errors keep their wording', () {
    expect(
      pullRequestActionErrorMessage(StateError('Push first.')),
      'Push first.',
    );
    expect(
      pullRequestActionErrorMessage(TimeoutException('slow')),
      'The paired computer did not answer in time.',
    );
  });

  _registerPullRequestActionsWidgetTests();

  test('a write snapshot survives a refresh that started before it', () async {
    final client = _client(_snapshot());
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final provider = pullRequestControllerProvider('host-1', 'workspace-1');
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    final gate = Completer<void>();
    client.pullRequestSnapshotGate = gate;
    final refresh = notifier.refresh();
    notifier.applySnapshot(_snapshot(state: 'MERGED'));
    gate.complete();

    expect(await refresh, isNull);
    await Future<void>.value();
    expect(container.read(provider).value?.review?.state, 'MERGED');
    expect(container.read(provider).isLoading, isFalse);
  });

  _registerPullRequestActionsRemovalTests();
}

FakeTerminalClient _client(MobilePullRequestSnapshot snapshot) {
  return FakeTerminalClient()
    ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
    ..pullRequestsSupported = true
    ..pullRequestActionsSupported = true
    ..pullRequest = snapshot;
}

const _workspace = WorkspaceSummary(
  id: 'workspace-1',
  projectId: 'project-1',
  name: 'Workspace',
  path: '/repo',
  branch: 'feat/actions',
);

Future<void> _openPullRequest(
  WidgetTester tester,
  FakeTerminalClient client, {
  Widget? home,
}) async {
  client.workspaces = <WorkspaceSummary>[_workspace];
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
        builder: (context, child) => Stack(
          children: [
            child!,
            const Align(
              alignment: Alignment.bottomCenter,
              child: BackgroundOperationCards(),
            ),
          ],
        ),
        home:
            home ??
            const WorkspaceTabsScreen(hostId: 'host-1', workspace: _workspace),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (home != null) {
    await tester.tap(find.text('Workspace List'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pull Request'));
  await tester.pumpAndSettle();
}
