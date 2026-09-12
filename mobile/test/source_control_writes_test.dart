import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_actions_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_commit_draft.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('parses the writable snapshot the runtime sends', () {
    final snapshot = MobileGitStatusSnapshot.fromJson(const <String, Object?>{
      'isRepository': true,
      'branch': 'main',
      'writable': true,
      'entries': <Object?>[
        <String, Object?>{
          'path': 'lib/main.dart',
          'area': 'unstaged',
          'status': 'modified',
          'canStage': true,
          'canDiscard': true,
          'isSubmodule': false,
        },
      ],
      'repository': <String, Object?>{
        'upstream': 'origin/main',
        'ahead': 2,
        'behind': 1,
        'hasConflicts': false,
        'headMessage': 'init',
        'detached': false,
      },
      'stashes': <Object?>[
        <String, Object?>{'index': 0, 'message': 'WIP on main'},
      ],
      'actions': <String, Object?>{'stageAll': true, 'sync': true},
      'primaryAction': 'sync',
      'aiCommitMessageEnabled': true,
    });

    expect(snapshot.writable, isTrue);
    expect(snapshot.entries.single.canStage, isTrue);
    expect(snapshot.entries.single.canUnstage, isFalse);
    expect(snapshot.repository.upstream, 'origin/main');
    expect(snapshot.repository.ahead, 2);
    expect(snapshot.stashes.single.message, 'WIP on main');
    expect(snapshot.actions.sync, isTrue);
    expect(snapshot.actions.commit, isFalse);
    expect(snapshot.primaryAction, 'sync');
    expect(snapshot.aiCommitMessageEnabled, isTrue);

    final legacy = MobileGitStatusSnapshot.fromJson(const <String, Object?>{
      'isRepository': true,
      'entries': <Object?>[],
    });
    expect(legacy.writable, isFalse);
    expect(legacy.actions.fetch, isFalse);
  });

  test('writes map to runtime verbs and payloads', () {
    expect(MobileGitWrite.stage(path: 'a.txt', area: 'unstaged').payload('w'), {
      'workspaceId': 'w',
      'path': 'a.txt',
      'area': 'unstaged',
    });
    expect(MobileGitWrite.stage().payload('w'), {'workspaceId': 'w'});
    final commit = MobileGitWrite.commit('msg', then: .push);
    expect(commit.action.verb, 'mobile.git.commit');
    expect(commit.payload('w'), {
      'workspaceId': 'w',
      'message': 'msg',
      'then': 'push',
    });
    expect(commit.usesNetwork, isTrue);
    expect(MobileGitWrite.commit('msg', amend: true).usesNetwork, isFalse);
    expect(MobileGitWrite.stashPop(2).payload('w')['stashIndex'], 2);
    expect(MobileGitWrite.fetch().usesNetwork, isTrue);
    expect(MobileGitWrite.discard(path: 'a').usesNetwork, isFalse);
  });

  testWidgets('an older runtime keeps the panel read-only', (tester) async {
    final client = _client(
      _snapshot(writable: false, entries: <MobileGitChange>[_unstaged()]),
    );
    addTearDown(client.dispose);

    await _pumpPanel(tester, client);

    expect(
      find.text(
        'Update the paired Alera runtime to stage and commit from mobile.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Stage'), findsNothing);
    expect(find.byTooltip('Source Control Actions'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Fetch'), findsNothing);
  });

  testWidgets('stage applies the snapshot the runtime answers with', (
    tester,
  ) async {
    final client = _client(_snapshot(entries: <MobileGitChange>[_unstaged()]))
      ..onGitWrite = (_) => _snapshot(
        entries: <MobileGitChange>[_staged()],
        actions: const MobileSourceControlActions(commit: true, fetch: true),
      );
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await tester.tap(find.byTooltip('Stage'));
    await tester.pumpAndSettle();

    final write = client.gitWrites.single;
    expect(write.action, MobileGitWriteAction.stage);
    expect(write.arguments, {'path': 'lib/main.dart', 'area': 'unstaged'});
    expect(find.text('STAGED'), findsOneWidget);
    expect(find.byTooltip('Unstage'), findsOneWidget);
    expect(find.text('Staged'), findsOneWidget);
    expect(
      client.calls.where((call) => call.startsWith('gitStatus')),
      hasLength(1),
    );
  });

  testWidgets('discard all asks first and sends nothing when cancelled', (
    tester,
  ) async {
    final client = _client(
      _snapshot(
        entries: <MobileGitChange>[_unstaged()],
        actions: const MobileSourceControlActions(
          discardAll: true,
          fetch: true,
        ),
      ),
    );
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await _openMenu(tester, 'Discard All');
    expect(find.text('Discard All Changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.gitWrites, isEmpty);

    await _openMenu(tester, 'Discard All');
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(client.gitWrites.single.action, MobileGitWriteAction.discard);
    expect(client.gitWrites.single.arguments, isEmpty);
  });

  testWidgets('commit needs a message and clears it afterwards', (
    tester,
  ) async {
    final staged = _snapshot(
      entries: <MobileGitChange>[_staged()],
      actions: const MobileSourceControlActions(
        commit: true,
        commitPush: true,
        fetch: true,
      ),
      primaryAction: 'publishBranch',
    );
    final client = _client(staged)..onGitWrite = (_) => _snapshot();
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    expect(find.widgetWithText(FilledButton, 'Publish Branch'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Add login flow');
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Commit'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Commit'));
    await tester.pumpAndSettle();

    final write = client.gitWrites.single;
    expect(write.action, MobileGitWriteAction.commit);
    expect(write.arguments, {'message': 'Add login flow'});
    expect(find.text('Committed'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SourceControlPanel)),
    );
    expect(
      container.read(sourceControlCommitDraftProvider('host-1', 'workspace-1')),
      isEmpty,
    );
  });

  testWidgets('commit options send commit and push', (tester) async {
    final client = _client(
      _snapshot(
        entries: <MobileGitChange>[_staged()],
        actions: const MobileSourceControlActions(
          commit: true,
          commitPush: true,
          commitSync: true,
          amend: true,
          fetch: true,
        ),
      ),
    );
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();
    await tester.tap(find.byTooltip('Commit Options'));
    await tester.pumpAndSettle();
    expect(find.text('Commit & Sync'), findsOneWidget);
    await tester.tap(find.text('Commit & Push'));
    await tester.pumpAndSettle();

    expect(client.gitWrites.single.arguments, {
      'message': 'Ship it',
      'then': 'push',
    });
    expect(find.text('Committed and pushed'), findsOneWidget);
  });

  testWidgets('amend edits the HEAD message', (tester) async {
    final client = _client(
      _snapshot(
        entries: <MobileGitChange>[_staged()],
        actions: const MobileSourceControlActions(commit: true, amend: true),
        headMessage: 'Initial commit',
      ),
    );
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await tester.tap(find.byTooltip('Commit Options'));
    await tester.pumpAndSettle();
    expect(find.text('Commit & Push'), findsNothing);
    await tester.tap(find.text('Commit Amend'));
    await tester.pumpAndSettle();
    expect(find.text('Initial commit'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'Initial commit, amended',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Amend'));
    await tester.pumpAndSettle();

    expect(client.gitWrites.single.arguments, {
      'message': 'Initial commit, amended',
      'amend': true,
    });
  });

  testWidgets('stash pop picks among several stashes', (tester) async {
    final client = _client(
      _snapshot(
        actions: const MobileSourceControlActions(stashPop: true, fetch: true),
        stashes: const <MobileGitStash>[
          MobileGitStash(index: 0, message: 'WIP newest'),
          MobileGitStash(index: 1, message: 'WIP older'),
        ],
      ),
    );
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await _openMenu(tester, 'Stash Pop');
    await tester.tap(find.text('stash@{1}: WIP older'));
    await tester.pumpAndSettle();

    expect(client.gitWrites.single.arguments, {'stashIndex': 1});
  });

  testWidgets('a failed write shows the runtime message and reloads', (
    tester,
  ) async {
    final client =
        _client(
            _snapshot(
              actions: const MobileSourceControlActions(
                sync: true,
                fetch: true,
              ),
            ),
          )
          ..onGitWrite = (_) =>
              throw StateError('Publish this branch before syncing.');
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await _openMenu(tester, 'Sync');

    expect(find.text('Publish this branch before syncing.'), findsOneWidget);
    expect(
      client.calls.where((call) => call.startsWith('gitStatus')),
      hasLength(2),
    );
  });

  testWidgets('controls are disabled while a write is in flight', (
    tester,
  ) async {
    final client = _client(_snapshot(entries: <MobileGitChange>[_unstaged()]))
      ..gitWriteGate = Completer<void>();
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await tester.tap(find.byTooltip('Stage'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final fetch = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Fetch'),
    );
    expect(fetch.onPressed, isNull);
    await tester.tap(find.byTooltip('Stage'));
    await tester.pump();
    expect(client.gitWrites, hasLength(1));

    client.gitWriteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('staging from the diff returns to the refreshed list', (
    tester,
  ) async {
    final client = _client(_snapshot(entries: <MobileGitChange>[_unstaged()]))
      ..gitDiffFile = const MobileGitDiffFile(
        path: 'lib/main.dart',
        area: 'unstaged',
      )
      ..onGitWrite = (_) => _snapshot(entries: <MobileGitChange>[_staged()]);
    addTearDown(client.dispose);
    await _pumpPanel(tester, client);

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('File Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Stage'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('File Actions'), findsNothing);
    expect(find.text('STAGED'), findsOneWidget);
  });

  test('a write outlives the panel and clears the committed draft', () async {
    final client = _client(_snapshot(entries: <MobileGitChange>[_staged()]))
      ..onGitWrite = (_) => _snapshot();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final draft = sourceControlCommitDraftProvider('host-1', 'workspace-1');
    container.read(draft.notifier).update('Ship it');

    // Nothing watches the controller here: the panel is off screen while the
    // write runs, which used to dispose it mid-flight.
    final error = await container
        .read(
          sourceControlActionsControllerProvider(
            'host-1',
            'workspace-1',
          ).notifier,
        )
        .run(MobileGitWrite.commit('Ship it'));

    expect(error, isNull);
    expect(container.read(draft), isEmpty);
    expect(
      container
          .read(sourceControlControllerProvider('host-1', 'workspace-1'))
          .value
          ?.entries,
      isEmpty,
    );
    expect(
      container.read(
        sourceControlActionsControllerProvider('host-1', 'workspace-1'),
      ),
      isNull,
    );
  });

  test('an amend leaves the composer draft alone', () async {
    final client = _client(_snapshot())..onGitWrite = (_) => _snapshot();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final draft = sourceControlCommitDraftProvider('host-1', 'workspace-1');
    container.read(draft.notifier).update('Next commit');

    await container
        .read(
          sourceControlActionsControllerProvider(
            'host-1',
            'workspace-1',
          ).notifier,
        )
        .run(MobileGitWrite.commit('Amended', amend: true));

    expect(container.read(draft), 'Next commit');
  });

  test('non-git failures keep their own message', () {
    expect(
      sourceControlErrorMessage(const HostUnreachableException()),
      'Could not reach the host',
    );
    expect(
      sourceControlErrorMessage(const RuntimeConnectionLost()),
      'Lost the connection to the host',
    );
    expect(
      sourceControlErrorMessage(StateError('Nothing to commit.')),
      'Nothing to commit.',
    );
    expect(
      sourceControlErrorMessage(
        TimeoutException('x', const Duration(seconds: 1)),
      ),
      'The runtime did not answer in time.',
    );
  });
}

MobileGitChange _unstaged() => const MobileGitChange(
  path: 'lib/main.dart',
  area: 'unstaged',
  status: 'modified',
  canStage: true,
  canDiscard: true,
);

MobileGitChange _staged() => const MobileGitChange(
  path: 'lib/main.dart',
  area: 'staged',
  status: 'modified',
  canUnstage: true,
);

MobileGitStatusSnapshot _snapshot({
  bool writable = true,
  List<MobileGitChange> entries = const <MobileGitChange>[],
  MobileSourceControlActions actions = const MobileSourceControlActions(
    stageAll: true,
    fetch: true,
  ),
  String primaryAction = 'fetch',
  String? headMessage,
  List<MobileGitStash> stashes = const <MobileGitStash>[],
}) => MobileGitStatusSnapshot(
  isRepository: true,
  branch: 'main',
  writable: writable,
  entries: entries,
  actions: actions,
  primaryAction: primaryAction,
  repository: MobileGitRepositoryState(
    upstream: 'origin/main',
    headMessage: headMessage,
  ),
  stashes: stashes,
);

FakeTerminalClient _client(MobileGitStatusSnapshot snapshot) =>
    FakeTerminalClient()
      ..sourceControlSupported = true
      ..sourceControlWritesSupported = true
      ..gitStatusSnapshot = snapshot;

Future<void> _openMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Source Control Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
}

Future<void> _pumpPanel(WidgetTester tester, FakeTerminalClient client) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const Scaffold(
          body: SourceControlPanel(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
