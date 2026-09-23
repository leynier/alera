import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_panel.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_run_control_section.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_controls_fixture.dart';

void main() {
  testWidgets('cancelled integration attention offers safe explicit retry', (
    tester,
  ) async {
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkflowRunControlPanel(
              controls: WorkflowRunControls.fromJson(
                workflowControlsFixture()
                  ..['status'] = 'cancelled'
                  ..['canControl'] = false
                  ..['integrationSettlementPending'] = 1
                  ..['cancellationError'] =
                      'Retained integration worktree has changes.',
              ),
              onControl: (value) => action = value,
              onReview: (_) {},
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Pending integrations: 1.'), findsOneWidget);
    expect(find.text('Start Workflow'), findsNothing);
    await tester.tap(find.text('Retry Cancellation'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not apply new Git changes'),
      findsOneWidget,
    );
    expect(action, isNull);
    await tester.tap(find.text('Confirm Cancellation'));
    expect(action, 'cancel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('only eligible human gates open review at compact text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? scope;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: WorkflowRunControlPanel(
                controls: WorkflowRunControls.fromJson(
                  workflowControlsFixture()..['canRequestChanges'] = true,
                ),
                onControl: (_) {},
                onRefresh: () {},
                onReview: (value) => scope = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Review Changes Needed'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Review Changes Needed'));
    expect(scope, 'correction');
    await tester.scrollUntilVisible(
      find.text('Review Foundation Gate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Review Foundation Gate'));
    expect(scope, 'stage:foundation');
    await tester.scrollUntilVisible(
      find.text('Review Product Gate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Review Product Gate'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  Future<void> mount(WidgetTester tester, _Client client) async {
    addTearDown(client.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowLifecycleRepositoryProvider.overrideWithValue(
            WorkflowLifecycleRepository(client, client),
          ),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: Scaffold(
            body: ListView(
              children: [
                WorkflowRunControlSection(
                  runId: 'run',
                  revision: 1,
                  onReview: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'response loss retries the exact command and closing releases reads',
    (tester) async {
      final client = _Client()..fail = true;
      await mount(tester, client);
      await tester.tap(find.text('Start Workflow'));
      await tester.pumpAndSettle();
      expect(find.text('Retry Same Command'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start Workflow'),
            )
            .onPressed,
        isNull,
      );
      client.fail = false;
      client.snapshot = workflowControlsFixture(
        sequence: 1,
        executionStatus: 'running',
      );
      await tester.tap(find.text('Retry Same Command'));
      await tester.pumpAndSettle();
      expect(client.documents.length, 2);
      expect(client.documents[0], client.documents[1]);
      expect(find.text('Pause Workflow'), findsOneWidget);
      expect(find.text('Retry Same Command'), findsNothing);
      expect(client.events.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(client.events.hasListener, isFalse);
    },
  );

  testWidgets(
    'observing a newer sequence releases an obsolete uncertain command',
    (tester) async {
      final client = _Client()..fail = true;
      await mount(tester, client);
      await tester.tap(find.text('Start Workflow'));
      await tester.pumpAndSettle();
      client.snapshot = workflowControlsFixture(sequence: 2);
      await tester.tap(find.text('Refresh Workflow'));
      await tester.pumpAndSettle();
      expect(find.text('Retry Same Command'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start Workflow'),
            )
            .onPressed,
        isNotNull,
      );
      expect(client.documents.length, 1);
    },
  );

  testWidgets('incompatible host has no executable fallback', (tester) async {
    final client = _Client()..supported = false;
    await mount(tester, client);
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Start Workflow'), findsNothing);
    expect(client.calls, isEmpty);
  });

  testWidgets(
    'cancellation requires confirmation and retains an uncertain command before approval',
    (tester) async {
      final client = _Client()..fail = true;
      client.snapshot = {
        ...workflowControlsFixture(),
        'status': 'prepared',
        'canControl': false,
      };
      await mount(tester, client);
      await tester.tap(find.text('Cancel Workflow'));
      await tester.pumpAndSettle();
      expect(client.documents, isEmpty);
      expect(
        find.textContaining('This run cannot be resumed.'),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'workflow-cancel-keep',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'workflow-cancel');
      expect(find.text('Confirm Cancellation'), findsNothing);
      await tester.tap(find.text('Cancel Workflow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Cancellation'));
      await tester.pumpAndSettle();
      expect(jsonDecode(client.documents.single)['action'], 'cancel');
      await tester.tap(find.text('Refresh Workflow'));
      await tester.pumpAndSettle();
      expect(find.text('Retry Same Command'), findsOneWidget);
      client.fail = false;
      client.snapshot = {
        ...workflowControlsFixture(sequence: 1),
        'status': 'cancelled',
        'canControl': false,
        'canCancel': false,
      };
      await tester.tap(find.text('Retry Same Command'));
      await tester.pumpAndSettle();
      expect(client.documents.length, 2);
      expect(client.documents.first, client.documents.last);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Start Workflow'), findsNothing);
      expect(find.text('Cancel Workflow'), findsNothing);
      expect(find.text('Retry Same Command'), findsNothing);
    },
  );
}

class _Client
    implements
        RuntimeHostClient,
        RuntimeHostCapabilityClient,
        WorkflowDecisionSigner {
  final events = StreamController<RuntimeHostEvent>.broadcast();
  final calls = <String>[];
  final documents = <String>[];
  var snapshot = workflowControlsFixture();
  bool supported = true;
  bool fail = false;
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;
  @override
  Future<bool> supportsRuntimeCapability(String capability) async => supported;
  @override
  Future<Uint8List> sign(String statementJson) async =>
      throw UnimplementedError('Execution controls must not sign approvals.');
  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(verb);
    if (verb == 'workflows.execution') return snapshot;
    if (verb == 'workflows.controlExecution') {
      documents.add(payload['document']! as String);
      if (fail) throw StateError('Response lost');
      return {'execution': snapshot['execution']};
    }
    throw StateError('Unexpected request: $verb');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
