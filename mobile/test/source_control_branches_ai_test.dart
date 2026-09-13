import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/source_control_fixtures.dart';

void main() {
  testWidgets('branch sheet switches to the chosen branch', (tester) async {
    final client = sourceControlClient(writableSnapshot())
      ..gitBranchesResult = const MobileGitBranches(
        branches: <String>['feature/login', 'main', 'origin/release'],
        localBranches: <String>['feature/login', 'main'],
        current: 'main',
      );
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('Switch Branch'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'release');
    await tester.pumpAndSettle();
    expect(find.text('feature/login'), findsNothing);
    await tester.tap(find.text('origin/release'));
    await tester.pumpAndSettle();

    expect(client.gitWrites.single.action, MobileGitWriteAction.checkout);
    expect(client.gitWrites.single.arguments, {'branch': 'origin/release'});
    expect(find.text('Switched to origin/release'), findsOneWidget);
  });

  testWidgets('choosing the current branch does nothing', (tester) async {
    final client = sourceControlClient(writableSnapshot())
      ..gitBranchesResult = const MobileGitBranches(branches: <String>['main']);
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'main'));
    await tester.pumpAndSettle();

    expect(client.gitWrites, isEmpty);
  });

  testWidgets('create branch validates the name first', (tester) async {
    final client = sourceControlClient(writableSnapshot())
      ..gitBranchesResult = const MobileGitBranches(
        branches: <String>['main'],
        localBranches: <String>['main'],
      );
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Create Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.text('Branch name is required'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'main');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.text('A branch named "main" already exists'), findsOneWidget);
    expect(client.gitWrites, isEmpty);

    await tester.enterText(find.byType(TextField), ' feature/login ');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(client.gitWrites.single.action, MobileGitWriteAction.createBranch);
    expect(client.gitWrites.single.arguments, {'branch': 'feature/login'});
  });

  final staged = writableSnapshot(
    entries: <MobileGitChange>[stagedChange()],
    actions: const MobileSourceControlActions(commit: true, fetch: true),
  );

  testWidgets('generate stays hidden while AI Assist is off', (tester) async {
    final client = sourceControlClient(staged)
      ..commitMessageGenerationSupported = true;
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    expect(find.byTooltip('Generate Commit Message'), findsNothing);
  });

  testWidgets('generate stays hidden on an older runtime', (tester) async {
    final client = sourceControlClient(_withAi(staged));
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    expect(find.byTooltip('Generate Commit Message'), findsNothing);
  });

  testWidgets('generated message fills the field', (tester) async {
    final client = _aiClient()
      ..onGenerateCommitMessage = (_) async =>
          const GeneratedCommitMessage(message: 'Add login flow');
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    await tester.tap(find.byTooltip('Generate Commit Message'));
    await tester.pumpAndSettle();

    expect(find.text('Add login flow'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Commit'), findsOneWidget);
  });

  testWidgets('stop cancels the run and keeps the draft', (tester) async {
    final gate = Completer<GeneratedCommitMessage>();
    final client = _aiClient()..onGenerateCommitMessage = (_) => gate.future;
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);
    await tester.enterText(find.byType(TextField), 'My own words');
    await tester.pump();

    await tester.tap(find.byTooltip('Generate Commit Message'));
    await tester.pump();
    expect(find.byTooltip('Stop Generating'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop Generating'));
    await tester.pump();

    expect(
      client.calls.where((call) => call.startsWith('cancelCommitMessage')),
      hasLength(1),
    );
    // The stopped run is still in flight, so the button stays Stop and a
    // second Generate cannot start another agent for the same workspace.
    expect(find.byTooltip('Stop Generating'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop Generating'));
    await tester.pump();
    expect(
      client.calls.where((call) => call.startsWith('generateCommitMessage')),
      hasLength(1),
    );

    gate.complete(const GeneratedCommitMessage(message: 'Too late'));
    await tester.pumpAndSettle();
    expect(find.text('Too late'), findsNothing);
    expect(find.text('My own words'), findsOneWidget);
    expect(find.byTooltip('Generate Commit Message'), findsOneWidget);
  });

  testWidgets('a failed generation reports the runtime message', (
    tester,
  ) async {
    final client = _aiClient()
      ..onGenerateCommitMessage = (_) async =>
          throw StateError('AI Assist is disabled.');
    addTearDown(client.dispose);
    await pumpSourceControlPanel(tester, client);

    await tester.tap(find.byTooltip('Generate Commit Message'));
    await tester.pumpAndSettle();

    expect(find.text('AI Assist is disabled.'), findsOneWidget);
    expect(find.byTooltip('Generate Commit Message'), findsOneWidget);
  });
}

MobileGitStatusSnapshot _withAi(MobileGitStatusSnapshot snapshot) =>
    MobileGitStatusSnapshot(
      isRepository: snapshot.isRepository,
      branch: snapshot.branch,
      writable: snapshot.writable,
      entries: snapshot.entries,
      actions: snapshot.actions,
      primaryAction: snapshot.primaryAction,
      repository: snapshot.repository,
      aiCommitMessageEnabled: true,
    );

FakeTerminalClient _aiClient() => sourceControlClient(
  _withAi(
    writableSnapshot(
      entries: <MobileGitChange>[stagedChange()],
      actions: const MobileSourceControlActions(commit: true, fetch: true),
    ),
  ),
)..commitMessageGenerationSupported = true;
