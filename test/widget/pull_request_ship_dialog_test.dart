import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_follow_up.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_composer.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

Future<void> _pumpComposer(
  WidgetTester tester, {
  required PullRequestShipCallback onShip,
  FakeGitBackend? git,
  PullRequestShipFollowUp shipFollowUp = PullRequestShipFollowUp.none,
  PullRequestAgentWatchScope watchScope = PullRequestAgentWatchScope.defaults,
  PullRequestCreateAction createAction = PullRequestCreateAction.publish,
  ValueChanged<PullRequestShipFollowUp>? onShipFollowUpChanged,
  ValueChanged<PullRequestAgentWatchScope>? onWatchScopeChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(git ?? FakeGitBackend()),
        settingsControllerProvider.overrideWithValue(.defaults),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PullRequestComposer(
              repoPath: '/repo',
              headBranch: 'feat/ship',
              baseBranches: const <String>['main'],
              suggestedBaseBranch: 'main',
              canCreate: true,
              busy: false,
              suggestedReview: null,
              createAction: createAction,
              shipFollowUp: shipFollowUp,
              watchScope: watchScope,
              onShipFollowUpChanged: onShipFollowUpChanged,
              onWatchScopeChanged: onWatchScopeChanged,
              onCreate: (_) {},
              onShip: onShip,
              onLink: (_) {},
              onCreateActionChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

FakeGitBackend _dirtyGit() => FakeGitBackend()
  ..gitStatusResult = const GitStatusResult(
    entries: <GitChangeEntry>[
      GitChangeEntry(path: 'lib/ship.dart', area: .staged, status: .modified),
    ],
  );

void main() {
  testWidgets('ship dialog stacks staged, all, then cancel', (tester) async {
    await _pumpComposer(
      tester,
      git: _dirtyGit(),
      onShip: ({
        required baseBranch,
        required draft,
        required scope,
        required followUp,
      }) async {},
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();

    final stagedTop = tester.getTopLeft(find.text('Ship Staged Changes'));
    final allTop = tester.getTopLeft(find.text('Ship All Changes'));
    final cancelTop = tester.getTopLeft(find.text('Cancel'));
    expect(stagedTop.dy, lessThan(allTop.dy));
    expect(allTop.dy, lessThan(cancelTop.dy));
  });

  testWidgets('ship button opens dialog and forwards the scope', (
    tester,
  ) async {
    PullRequestShipScope? shippedScope;
    await _pumpComposer(
      tester,
      git: _dirtyGit(),
      onShip:
          ({
            required baseBranch,
            required draft,
            required scope,
            required followUp,
          }) async {
            shippedScope = scope;
          },
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    expect(find.text('Ship Staged Changes'), findsOneWidget);

    await tester.tap(find.text('Ship Staged Changes'));
    await tester.pumpAndSettle();
    expect(shippedScope, PullRequestShipScope.staged);
  });

  testWidgets('cancelling the ship dialog ships nothing', (tester) async {
    var shipped = false;
    await _pumpComposer(
      tester,
      git: _dirtyGit(),
      onShip:
          ({
            required baseBranch,
            required draft,
            required scope,
            required followUp,
          }) async {
            shipped = true;
          },
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shipped, isFalse);
  });

  testWidgets(
    'ships existing commits without asking for a working-tree scope',
    (tester) async {
      PullRequestShipScope? shippedScope;
      await _pumpComposer(
        tester,
        onShip:
            ({
              required baseBranch,
              required draft,
              required scope,
              required followUp,
            }) async {
              shippedScope = scope;
            },
      );

      await tester.tap(find.byKey(const Key('pull-request-ship-button')));
      await tester.pumpAndSettle();
      expect(find.text('Ship Staged Changes'), findsNothing);
      expect(shippedScope, PullRequestShipScope.staged);
    },
  );

  testWidgets('the main segment names the remembered follow-up', (
    tester,
  ) async {
    Future<void> noShip({
      required String baseBranch,
      required bool draft,
      required PullRequestShipScope scope,
      required PullRequestShipFollowUp followUp,
    }) async {}

    await _pumpComposer(tester, onShip: noShip);
    expect(find.text('Ship Changes'), findsOneWidget);

    await _pumpComposer(tester, onShip: noShip, shipFollowUp: .watchAndFix);
    expect(find.text('Ship and Watch'), findsOneWidget);

    await _pumpComposer(
      tester,
      onShip: noShip,
      shipFollowUp: .watchFixAndMerge,
    );
    expect(find.text('Ship and Merge'), findsOneWidget);
  });

  testWidgets('choosing a follow-up remembers it without shipping', (
    tester,
  ) async {
    var shipped = false;
    PullRequestShipFollowUp? chosen;
    await _pumpComposer(
      tester,
      onShip:
          ({
            required baseBranch,
            required draft,
            required scope,
            required followUp,
          }) async {
            shipped = true;
          },
      onShipFollowUpChanged: (value) => chosen = value,
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-options')));
    await tester.pumpAndSettle();
    expect(find.text('Ship, Watch and Fix'), findsOneWidget);
    expect(find.text('Failed Checks'), findsOneWidget);
    expect(find.text('Review Comments'), findsOneWidget);
    expect(find.text('Merge Conflicts'), findsOneWidget);

    await tester.tap(find.text('Ship, Watch, Fix and Merge'));
    await tester.pumpAndSettle();
    expect(chosen, PullRequestShipFollowUp.watchFixAndMerge);
    expect(shipped, isFalse);
  });

  testWidgets('watch follow-ups stay off until something is watched', (
    tester,
  ) async {
    PullRequestShipFollowUp? chosen;
    PullRequestAgentWatchScope? saved;
    await _pumpComposer(
      tester,
      watchScope: const PullRequestAgentWatchScope(
        checks: false,
        comments: false,
        conflicts: false,
      ),
      onShip: ({
        required baseBranch,
        required draft,
        required scope,
        required followUp,
      }) async {},
      onShipFollowUpChanged: (value) => chosen = value,
      onWatchScopeChanged: (value) => saved = value,
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ship, Watch and Fix'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(chosen, isNull);

    await tester.tap(find.text('Merge Conflicts'));
    await tester.pumpAndSettle();
    expect(
      saved,
      const PullRequestAgentWatchScope(checks: false, comments: false),
    );
    await tester.tap(find.text('Ship, Watch and Fix'));
    await tester.pumpAndSettle();
    expect(chosen, PullRequestShipFollowUp.watchAndFix);
  });

  testWidgets('a watch follow-up with nothing to watch does not ship', (
    tester,
  ) async {
    var shipped = false;
    await _pumpComposer(
      tester,
      shipFollowUp: .watchAndFix,
      watchScope: const PullRequestAgentWatchScope(
        checks: false,
        comments: false,
        conflicts: false,
      ),
      onShip:
          ({
            required baseBranch,
            required draft,
            required scope,
            required followUp,
          }) async {
            shipped = true;
          },
    );

    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    expect(shipped, isFalse);
    expect(find.text('Choose at least one problem to watch'), findsOneWidget);
  });

  testWidgets('ship and merge always ships a ready pull request', (
    tester,
  ) async {
    bool? shippedDraft;
    PullRequestShipFollowUp? shippedFollowUp;
    Future<void> onShip({
      required String baseBranch,
      required bool draft,
      required PullRequestShipScope scope,
      required PullRequestShipFollowUp followUp,
    }) async {
      shippedDraft = draft;
      shippedFollowUp = followUp;
    }

    await _pumpComposer(
      tester,
      createAction: .draft,
      shipFollowUp: .watchAndFix,
      onShip: onShip,
    );
    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    expect(shippedDraft, isTrue);
    expect(shippedFollowUp, PullRequestShipFollowUp.watchAndFix);

    await _pumpComposer(
      tester,
      createAction: .draft,
      shipFollowUp: .watchFixAndMerge,
      onShip: onShip,
    );
    await tester.tap(find.byKey(const Key('pull-request-ship-button')));
    await tester.pumpAndSettle();
    expect(shippedDraft, isFalse);
    expect(shippedFollowUp, PullRequestShipFollowUp.watchFixAndMerge);
  });
}
