import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';

void main() {
  late _Client client;
  late WorkflowCleanupRepository repository;
  setUp(() {
    client = _Client();
    repository = WorkflowCleanupRepository(
      WorkflowLifecycleRepository(client, _Signer()),
    );
  });
  test('old host refuses cleanup without sending a legacy request', () async {
    client.supported = false;
    await expectLater(
      repository.prepare('cleanup', 'run', {'workspace': false}),
      throwsA(isA<WorkflowLifecycleUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
  });
  test(
    'resource pages decode ownership and preserve the keyset cursor',
    () async {
      final item = (cleanupPreviewFixture()['items']! as List).single as Map;
      client.response = {
        'runId': 'run',
        'revision': 4,
        'nextBeforeRow': 10,
        'items': [
          {
            'identity': item['identity'],
            'phase': 'ready',
            'registered': true,
            'retired': false,
            'cleanupId': null,
            'cleanupState': null,
          },
        ],
      };
      final page = await repository.resources('run', beforeRow: 20);
      expect(page.items.single.canSelect, true);
      expect(page.nextBeforeRow, 10);
      expect(client.calls.single.$2, {'runId': 'run', 'beforeRow': 20});
      await expectLater(repository.resources('foreign'), throwsFormatException);
    },
  );
  test(
    'preview validates exact resource and branch selection across isolate',
    () async {
      client.response = cleanupPreviewFixture();
      final result = await repository.prepare('cleanup', 'run', {
        'workspace': false,
      });
      expect(result.items.single.removeBranch, false);
      expect(() => result.items.clear(), throwsUnsupportedError);
      final request =
          jsonDecode(client.calls.single.$2['document']! as String) as Map;
      expect(request.keys.toSet(), {'id', 'runId', 'resources'});
      expect(request['resources'], [
        {'workspaceId': 'workspace', 'removeBranch': false},
      ]);
      await expectLater(
        repository.prepare('cleanup', 'run', {'foreign': false}),
        throwsFormatException,
      );
      await expectLater(
        repository.prepare('cleanup', 'run', {'workspace': true}),
        throwsFormatException,
      );
      await expectLater(
        repository.prepare('other', 'run', {'workspace': false}),
        throwsFormatException,
      );
      await expectLater(
        repository.prepare('cleanup', 'foreign', {'workspace': false}),
        throwsFormatException,
      );
    },
  );
  test(
    'apply and explicit retry send only the reviewed id and digest',
    () async {
      final preview = WorkflowCleanupPreview.fromJson(cleanupPreviewFixture());
      client.fail = true;
      await expectLater(repository.apply(preview), throwsStateError);
      client.fail = false;
      client.response = cleanupStatusFixture('retired');
      expect(
        (await repository.apply(preview)).state,
        WorkflowCleanupState.retired,
      );
      await repository.apply(preview, retry: true);
      expect(client.calls.map((call) => call.$1), [
        'workflows.applyCleanup',
        'workflows.applyCleanup',
        'workflows.retryCleanup',
      ]);
      expect(
        client.calls.map((call) => call.$2).toList(),
        List.filled(3, {'id': 'cleanup', 'digest': 'reviewed-digest'}),
      );
      (client.response['preview']! as Map)['digest'] = 'changed';
      await expectLater(repository.apply(preview), throwsFormatException);
    },
  );
  test('malformed or foreign receipts cannot claim retirement', () {
    final foreign = cleanupStatusFixture('retired')
      ..['retiredWorkspaceIds'] = ['foreign'];
    expect(
      () => WorkflowCleanupStatus.fromJson(foreign),
      throwsFormatException,
    );
    final missing = cleanupStatusFixture('retired')
      ..['retiredWorkspaceIds'] = <String>[];
    expect(
      () => WorkflowCleanupStatus.fromJson(missing),
      throwsFormatException,
    );
    final duplicated = cleanupStatusFixture('retired')
      ..['retiredWorkspaceIds'] = ['workspace', 'workspace'];
    expect(
      () => WorkflowCleanupStatus.fromJson(duplicated),
      throwsFormatException,
    );
    final dirty = WorkflowCleanupPreview.fromJson(
      cleanupPreviewFixture(dirty: true),
    );
    expect(dirty.canConfirm(DateTime.utc(2026)), false);
    final clean = WorkflowCleanupPreview.fromJson(cleanupPreviewFixture());
    expect(clean.canConfirm(clean.expiresAt), false);
  });
}

class _Signer implements WorkflowDecisionSigner {
  @override
  Future<Uint8List> sign(String statementJson) async =>
      throw StateError('Cleanup must not sign a plan decision.');
}

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = true;
  bool fail = false;
  Map<String, Object?> response = {};
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Future<bool> supportsRuntimeCapability(String capability) async => supported;
  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add((verb, payload));
    if (fail) throw StateError('Response lost');
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
