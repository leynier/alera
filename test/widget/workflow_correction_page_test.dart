import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/domain/workflow_correction_selection.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_correction_page.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Client client, {
    bool compact = false,
  }) async {
    if (compact) {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowLifecycleRepositoryProvider.overrideWithValue(
            _WidgetRepository(client),
          ),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(compact ? 2 : 1),
              ),
              child: WorkflowCorrectionPage(
                runId: 'run',
                revision: 1,
                onBack: () {},
                onCreated: (id) => client.created.add(id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'correction creation is explicit and retries the identical frozen selection',
    (tester) async {
      final client = _Client()..fail = true;
      await mount(tester, client);
      expect(client.documents, isEmpty);
      expect(find.text('Frozen Agent (Revision 7)'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Preserve completed work and add coverage.',
      );
      await tester.ensureVisible(find.text('Propose Correction'));
      await tester.tap(find.text('Propose Correction'));
      await tester.pumpAndSettle();
      expect(client.created, isEmpty);
      expect(client.launches, isEmpty);
      expect(find.text('Retry Correction'), findsOneWidget);
      final request = jsonDecode(client.documents.single) as Map;
      expect(request['runId'], 'run');
      expect(request['revision'], 1);
      expect(request['planDigest'], 'frozen-digest');
      expect(request.containsKey('profiles'), isFalse);
      client.fail = false;
      await tester.tap(find.text('Retry Correction'));
      await tester.pumpAndSettle();
      expect(client.documents.length, 2);
      expect(client.documents.first, client.documents.last);
      expect(client.created, client.launches);
      expect(client.created.length, 1);
    },
  );

  testWidgets(
    'refresh retains correction notes and blocks an obsolete revision',
    (tester) async {
      final client = _Client();
      await mount(tester, client);
      await tester.enterText(find.byType(TextField), 'Keep these notes.');
      client.currentRevision = 2;
      await tester.ensureVisible(find.text('Refresh Revision'));
      await tester.tap(find.text('Refresh Revision'));
      await tester.pumpAndSettle();
      expect(find.text('Keep these notes.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Propose Correction'),
            )
            .onPressed,
        isNull,
      );
      expect(client.documents, isEmpty);
    },
  );

  testWidgets(
    'correction form supports compact 200 percent text and local validation',
    (tester) async {
      final client = _Client();
      await mount(tester, client, compact: true);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'x' * 4097);
      await tester.scrollUntilVisible(
        find.text('Propose Correction'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Propose Correction'));
      await tester.pumpAndSettle();
      expect(client.documents, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old host cannot prepare a correction through a fallback', (
    tester,
  ) async {
    final client = _Client()..supported = false;
    await mount(tester, client);
    expect(find.text('Update Required'), findsOneWidget);
    expect(client.calls, isEmpty);
  });
}

class _Client
    implements
        RuntimeHostClient,
        RuntimeHostCapabilityClient,
        WorkflowDecisionSigner {
  bool supported = true;
  bool fail = false;
  int currentRevision = 1;
  final calls = <String>[];
  final documents = <String>[];
  final created = <String>[];
  final launches = <String>[];
  @override
  Future<bool> supportsRuntimeCapability(String capability) async => supported;
  @override
  Future<Uint8List> sign(String statementJson) =>
      throw UnimplementedError('Proposals never sign approvals.');
  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(verb);
    if (verb == 'workflows.plan') {
      return {
        'runId': 'run',
        'revision': 1,
        'currentRevision': currentRevision,
        'status': 'changesRequested',
        'changeReason': 'Add regression coverage',
        'plan': {
          'digest': 'frozen-digest',
          'objective': 'Deliver the workflow',
          'sourceSha': 'a' * 40,
          'recipe': {
            'recipe': {'name': 'Feature Delivery'},
          },
          'profiles': {
            'profile': {'name': 'Frozen Agent', 'revision': 7},
          },
        },
      };
    }
    if (verb == 'workflows.createCorrection') {
      final document = payload['document']! as String;
      documents.add(document);
      if (fail) throw StateError('Response lost');
      return {'id': (jsonDecode(document) as Map)['requestId']};
    }
    if (verb == 'workflows.startCoordinator') {
      launches.add(payload['id']! as String);
      return <String, Object?>{};
    }
    throw StateError('Unexpected request: $verb');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Real isolate execution is covered by repository tests outside FakeAsync.
class _WidgetRepository extends WorkflowLifecycleRepository {
  _WidgetRepository(_Client fixture) : super(fixture, fixture);
  @override
  Future<WorkflowCorrectionSelection> correctionSelection(
    String runId,
    int revision,
  ) async {
    final selection = WorkflowCorrectionSelection.fromJson(
      await request('workflows.plan', {'runId': runId, 'revision': revision}),
    );
    selection.requireCurrent(runId, revision);
    return selection;
  }
}
