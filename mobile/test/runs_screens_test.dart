import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/new_run_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_resources_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_runs_client.dart';

Widget _app(FakeRunsClient client, Widget child) => ProviderScope(
  overrides: [
    mobileRunsClientProvider('host').overrideWith((ref) async => client),
  ],
  child: MaterialApp(home: child),
);

/// A run whose detail shows [gate] as its one pending gate.
FakeRunsClient _clientWithGate(Map<String, Object?> gate) {
  final client = FakeRunsClient();
  client.gates[gate['id']! as String] = gate;
  client.snapshots['run-1'] = runSnapshotJson(
    run: runSummaryJson(status: 'paused', bucket: 'attention'),
    pendingGates: <Map<String, Object?>>[gate],
  );
  return client;
}

Future<void> _openDetail(WidgetTester tester, FakeRunsClient client) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(client, const RunDetailScreen(hostId: 'host', runId: 'run-1')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('runs are grouped into Attention, Active and History', (
    tester,
  ) async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.runs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATTENTION'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('Needs Attention'), findsOneWidget);
    expect(find.text('1 gate'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    final attention = tester.getTopLeft(find.text('Fix flaky login test'));
    final active = tester.getTopLeft(find.text('Migrate CI to Actions'));
    final history = tester.getTopLeft(find.text('Write release notes'));
    expect(attention.dy, lessThan(active.dy));
    expect(active.dy, lessThan(history.dy));
    expect(find.text('New Run'), findsOneWidget);
    expect(
      client.callsOf('runs.board').map((call) => call.payload['bucket']),
      unorderedEquals(<String>['attention', 'active', 'history']),
    );
  });

  testWidgets('an older host shows Update Required and no New Run', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileRunsClientProvider('host')
              .overrideWith((ref) async => throw const RunsUpdateRequired()),
        ],
        child: const MaterialApp(
          home: ActivityScreen(
            hostId: 'host',
            initialSection: ActivitySection.runs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text(RunsUpdateRequired.message), findsOneWidget);
    expect(find.text('New Run'), findsNothing);
  });

  testWidgets('a plan gate approves with its digest and rejects with notes', (
    tester,
  ) async {
    final client = _clientWithGate(runGateJson(kind: 'plan', scope: 'plan'));
    addTearDown(client.dispose);
    await _openDetail(tester, client);
    expect(find.text('PLAN APPROVAL'), findsOneWidget);
    expect(
      find.text('Approving freezes this plan and starts the workers.'),
      findsOneWidget,
    );
    final reject = find.widgetWithText(TextButton, 'Reject');
    expect(tester.widget<TextButton>(reject).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey<String>('run-gate-notes-gate-1')),
      'Split the migration first',
    );
    await tester.pump();
    await tester.tap(reject);
    await tester.pumpAndSettle();
    final rejected = client.callsOf('runs.resolveGate').single.payload;
    expect(rejected['decision'], 'reject');
    expect(rejected['reason'], 'Split the migration first');
    expect(rejected['expectedEvidenceDigest'], 'sha256:evidence');

    await tester.tap(find.text('Approve Plan'));
    await tester.pumpAndSettle();
    expect(
      client.callsOf('runs.resolveGate').last.payload['decision'],
      'approve',
    );
  });

  testWidgets('a stage gate requests changes with the option id', (
    tester,
  ) async {
    final client = _clientWithGate(runGateJson());
    addTearDown(client.dispose);
    await _openDetail(tester, client);
    expect(find.text('STAGE GATE · FOUNDATION'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('run-gate-notes-gate-1')),
      'Add tests',
    );
    await tester.pump();
    await tester.tap(find.text('Request Changes'));
    await tester.pumpAndSettle();
    final sent = client.callsOf('runs.resolveGate').single.payload;
    expect(sent['decision'], 'requestChanges');
    expect(sent['reason'], 'Add tests');
    expect(find.text('Approve Gate'), findsOneWidget);
  });

  testWidgets('a stall gate offers the three fixed options', (tester) async {
    final client = _clientWithGate(
      runGateJson(kind: 'stall', scope: '', taskId: 'task-1'),
    );
    addTearDown(client.dispose);
    await _openDetail(tester, client);
    expect(find.text('Keep Waiting'), findsOneWidget);
    expect(find.text('Abort Stage'), findsOneWidget);
    await tester.tap(find.text('Kill And Failover'));
    await tester.pumpAndSettle();
    expect(
      client.callsOf('runs.resolveGate').single.payload['decision'],
      'killAndFailover',
    );
  });

  testWidgets('a decision gate sends its option or a typed answer', (
    tester,
  ) async {
    final client = _clientWithGate(
      runGateJson(
        kind: 'decision',
        scope: '',
        taskId: 'task-1',
        question: 'Which auth flow?',
      ),
    );
    addTearDown(client.dispose);
    await _openDetail(tester, client);
    expect(find.text('Which auth flow?'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('run-gate-answer-gate-1')),
      'PKCE',
    );
    await tester.pump();
    await tester.tap(find.text('Send Answer'));
    await tester.pumpAndSettle();
    final sent = client.callsOf('runs.resolveGate').single.payload;
    expect(sent['decision'], 'PKCE');
    expect(sent.containsKey('reason'), isFalse);
  });

  testWidgets('a stale gate stops offering decisions until refreshed', (
    tester,
  ) async {
    final client = _clientWithGate(runGateJson());
    addTearDown(client.dispose);
    client.failures['runs.resolveGate'] = RuntimeRequestError(
      'stale',
      code: 'gate_stale',
    );
    await _openDetail(tester, client);
    await tester.tap(find.text('Approve Gate'));
    await tester.pumpAndSettle();
    const stale =
        'The evidence changed since you opened this gate. Review it again.';
    expect(find.text(stale), findsWidgets);
    final approve = find.widgetWithText(FilledButton, 'Approve Gate');
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(approve).onPressed, isNotNull);
  });

  testWidgets('a gate notification opens Activity, then the run at the gate', (
    tester,
  ) async {
    final client = _clientWithGate(runGateJson(id: 'gate-9'));
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.runs,
          initialRunId: 'run-1',
          initialGateId: 'gate-9',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RunDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<RunDetailScreen>(find.byType(RunDetailScreen))
          .initialGateId,
      'gate-9',
    );
    expect(
      find.byKey(const ValueKey<String>('run-gate-gate-9')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('cancelling a run asks first and sends the control sequence', (
    tester,
  ) async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    client.snapshots['run-1'] = runSnapshotJson(
      run: runSummaryJson(controlSequence: 7),
    );
    await _openDetail(tester, client);
    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsWidgets);
    await tester.tap(find.text('Cancel Run').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Run'));
    await tester.pumpAndSettle();
    expect(client.callsOf('runs.control'), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel Run'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Run'));
    await tester.pumpAndSettle();
    final sent = client.callsOf('runs.control').single.payload;
    expect(sent['action'], 'cancel');
    expect(sent['expectedSequence'], 7);
  });

  testWidgets('cleanup previews, then applies only after confirmation', (
    tester,
  ) async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(client, const RunResourcesScreen(hostId: 'host', runId: 'run-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('run-resource-attempt-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Also Delete This Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Uncommitted changes will be lost.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply Cleanup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.callsOf('runs.applyCleanup'), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply Cleanup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply Cleanup').last);
    await tester.pumpAndSettle();
    final applied = client.callsOf('runs.applyCleanup').single.payload;
    expect(applied['confirm'], isTrue);
    expect(applied['digest'], 'sha256:preview');
    expect(find.text('Removed'), findsWidgets);
    expect(
      client.callsOf('runs.previewCleanup').single.payload['resources'],
      <Object?>[
        <String, Object?>{'workspaceId': 'attempt-1', 'removeBranch': true},
      ],
    );
  });

  testWidgets('New Run creates a shared run without a recipe', (tester) async {
    final client = FakeRunsClient();
    addTearDown(client.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(client, const NewRunScreen(hostId: 'host', workspaceId: 'ws-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Template'.toUpperCase()), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('new-run-objective')),
      'Add OAuth login',
    );
    await tester.tap(find.text('Shared'));
    await tester.pumpAndSettle();
    expect(find.text('TEMPLATE'), findsNothing);
    await tester.tap(find.text('Choose a profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final sent = client.callsOf('runs.create').single.payload;
    expect(sent['isolation'], 'shared');
    expect(sent.containsKey('recipeSource'), isFalse);
    expect(sent['coordinatorProfileId'], 'codex');
    expect(sent['workspaceId'], 'ws-1');
    expect(sent['objective'], 'Add OAuth login');
    expect(find.byType(RunDetailScreen), findsOneWidget);
  });

  testWidgets('Activity and a run with a plan gate fit a 360 px phone', (
    tester,
  ) async {
    final client = _clientWithGate(runGateJson(kind: 'plan', scope: 'plan'));
    addTearDown(client.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.runs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.takeException();
    expect(first, isNull, reason: '$first');
    await tester.pumpWidget(
      _app(client, const RunDetailScreen(hostId: 'host', runId: 'run-1')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Approve Plan'), findsOneWidget);
  });
}
