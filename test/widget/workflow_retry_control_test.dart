import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_retry_control.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'new attempt needs confirmation and preserves the request on response loss',
    (tester) async {
      final repository = _Repository();
      var prepared = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workflowLifecycleRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: aleraDarkTheme,
            home: Scaffold(
              body: WorkflowRetryControl(
                runId: 'run',
                taskId: 'task',
                revision: 3,
                workspaceId: 'prior',
                onPrepared: () => prepared++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare New Attempt'));
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      await tester.tap(find.text('Keep Current Attempt'));
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      await tester.tap(find.text('Prepare New Attempt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm New Attempt'));
      await tester.pumpAndSettle();
      expect(prepared, 0);
      expect(repository.requests.single['retryOf'], 'prior');
      expect(repository.requests.single['revision'], 3);
      expect(repository.requests.single['taskId'], 'task');
      repository.fail = false;
      await tester.tap(find.text('Retry Preparation'));
      await tester.pumpAndSettle();
      expect(repository.requests[0], repository.requests[1]);
      expect(prepared, 1);
      expect(find.text('Confirm New Attempt'), findsNothing);
    },
  );
}

class _Repository extends WorkflowLifecycleRepository {
  _Repository() : super(_UnusedClient(), _UnusedSigner());
  final requests = <Map<String, Object?>>[];
  bool fail = true;
  @override
  Future<Map<String, Object?>> prepareRetry(
    Map<String, Object?> payload,
  ) async {
    requests.add(Map.of(payload));
    if (fail) throw StateError('Response lost');
    return {'phase': 'ready'};
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
