import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_integration_retry_control.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_visual_capture.dart';

void main() {
  setUpAll(loadWorkflowVisualFonts);

  testWidgets(
    'integration retry needs confirmation and never starts execution',
    (tester) async {
      final repository = _Repository();
      var settled = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workflowLifecycleRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: aleraDarkTheme,
            builder: workflowVisualBoundary,
            home: Scaffold(
              body: WorkflowIntegrationRetryControl(
                integrationId: 'reservation',
                requestId: 'original-request',
                runId: 'run',
                revision: 3,
                taskId: 'task',
                workspaceId: 'workspace',
                onSettled: () => settled++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Retry Integration'));
      await tester.pumpAndSettle();
      await captureWorkflowVisual(tester, 'integration-retry-confirmation');
      expect(repository.requests, isEmpty);
      await tester.tap(find.text('Keep Attention'));
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      await tester.tap(find.text('Retry Integration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Retry Integration'));
      await tester.pumpAndSettle();
      await captureWorkflowVisual(tester, 'integration-retry-attention');
      expect(settled, 1);
      expect(repository.requests.single, {
        'integrationId': 'reservation',
        'requestId': 'original-request',
        'runId': 'run',
        'revision': 3,
        'taskId': 'task',
        'workspaceId': 'workspace',
      });
      expect(find.textContaining('still needs attention'), findsOneWidget);
      repository.integrated = true;
      await tester.tap(find.text('Retry Same Integration'));
      await tester.pumpAndSettle();
      expect(repository.requests, [
        repository.requests.first,
        repository.requests.first,
      ]);
      expect(settled, 2);
      expect(find.textContaining('Start Workflow to continue'), findsOneWidget);
      expect(repository.executionCommands, isEmpty);
    },
  );
}

class _Repository extends WorkflowLifecycleRepository {
  _Repository() : super(_UnusedClient(), _UnusedSigner());

  final requests = <Map<String, Object?>>[];
  final executionCommands = <String>[];
  bool integrated = false;

  @override
  Future<Map<String, Object?>> retryIntegration({
    required String integrationId,
    required String requestId,
    required String runId,
    required int revision,
    required String taskId,
    required String workspaceId,
  }) async {
    requests.add({
      'integrationId': integrationId,
      'requestId': requestId,
      'runId': runId,
      'revision': revision,
      'taskId': taskId,
      'workspaceId': workspaceId,
    });
    return {
      'state': integrated ? 'integrated' : 'attention',
      'error': integrated
          ? null
          : 'The integration workspace still needs attention.',
    };
  }

  @override
  Future<void> controlExecution(String document) async {
    executionCommands.add(document);
  }
}

class _UnusedClient implements RuntimeHostClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSigner implements WorkflowDecisionSigner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
