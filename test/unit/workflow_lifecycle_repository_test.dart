import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/features/orchestration/domain/workflow_review_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);
  Map<String, Object?> review() => {
    'challenge': {
      'version': 1,
      'nonce': 'nonce',
      'audience': 'connection',
      'runId': 'run',
      'revision': 3,
      'scope': 'plan',
      'planDigest': 'digest',
      'evidenceDigest': 'evidence',
      'integrationSha': 'sha',
      'expiresAt': now.millisecondsSinceEpoch ~/ 1000 + 300,
    },
    'plan': {'digest': 'digest', 'objective': 'Scoped change'},
    'tasks': [],
  };

  test('old hosts cannot fall back to legacy workflow approval', () async {
    final client = _Client()..supported = false;
    final signer = _Signer();
    final repository = WorkflowLifecycleRepository(client, signer);
    await expectLater(
      repository.review('run', 3, 'plan'),
      throwsA(isA<WorkflowLifecycleUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
    expect(signer.statements, isEmpty);
  });

  test(
    'correction selection crosses the isolate and rejects obsolete identity',
    () async {
      final client = _Client()
        ..response = {
          'runId': 'run',
          'revision': 1,
          'currentRevision': 1,
          'status': 'changesRequested',
          'changeReason': 'Fix regression',
          'plan': {
            'digest': 'digest',
            'sourceSha': 'a' * 40,
            'objective': 'Deliver feature',
            'recipe': {
              'recipe': {'name': 'Feature Delivery'},
            },
            'profiles': {
              'p': {
                'name': 'Frozen Agent',
                'revision': 7,
                'command': 'private command',
              },
            },
          },
        };
      final repository = WorkflowLifecycleRepository(client, _Signer());
      final selection = await repository.correctionSelection('run', 1);
      expect(selection.reason, 'Fix regression');
      expect(selection.profileNames, ['Frozen Agent (Revision 7)']);
      expect(
        () => selection.profileNames.add('changed'),
        throwsUnsupportedError,
      );
      await expectLater(
        repository.correctionSelection('other', 1),
        throwsStateError,
      );
      await expectLater(
        repository.correctionSelection('run', 2),
        throwsStateError,
      );
      (client.response as Map)['currentRevision'] = 2;
      await expectLater(
        repository.correctionSelection('run', 1),
        throwsStateError,
      );
    },
  );

  test(
    'new run document binds source, origin and roles without executable tasks',
    () async {
      final client = _Client();
      final repository = WorkflowLifecycleRepository(client, _Signer());
      final bindings = {'implementer': 'profile'};
      final document = await repository.proposalDocument(
        requestId: 'stable-request',
        source: {
          'workspace': {'workspaceId': 'workspace', 'instanceId': 'instance'},
          'sha': 'a' * 40,
        },
        recipe: {
          'source': {
            'origin': 'project',
            'workspaceId': 'workspace',
            'path': '.alera/workflows/feature.yaml',
          },
          'digest': 'digest',
        },
        objective: 'Scoped change',
        coordinatorProfileId: 'coordinator',
        roleProfiles: bindings,
        maxConcurrent: 4,
      );
      bindings['implementer'] = 'changed';
      final wire = jsonDecode(document) as Map;
      expect(wire['expectedSource']['instanceId'], 'instance');
      final proposal = wire['request']['proposal'] as Map;
      expect(proposal['tasks'], isEmpty);
      expect(proposal['sourceSha'], 'a' * 40);
      expect(proposal['recipeSource']['origin'], 'project');
      expect(proposal['roleProfiles']['implementer'], 'profile');
      expect(client.calls, isEmpty);
      client.response = {'id': 'stable-request'};
      await repository.createProposal(document);
      await repository.createProposal(document);
      expect(client.documents, [document, document]);
    },
  );

  test('review validates requested identity and frozen plan digest', () async {
    final client = _Client()..response = review();
    final repository = WorkflowLifecycleRepository(client, _Signer());
    expect((await repository.review('run', 3, 'plan')).revision, 3);
    await expectLater(
      repository.review('other', 3, 'plan'),
      throwsFormatException,
    );
    await expectLater(
      repository.review('run', 4, 'plan'),
      throwsFormatException,
    );
    await expectLater(
      repository.review('run', 3, 'stage:product'),
      throwsFormatException,
    );
    client.response = review()..['plan'] = {'digest': 'different'};
    await expectLater(
      repository.review('run', 3, 'plan'),
      throwsFormatException,
    );
  });

  test(
    'integration retry reuses the exact request and checks its receipt',
    () async {
      final client = _Client()
        ..response = {
          'state': 'integrated',
          'request': {
            'id': 'integration-id',
            'run_id': 'run',
            'revision': 3,
            'task_id': 'task',
            'source': {'id': 'workspace'},
          },
        };
      final repository = WorkflowLifecycleRepository(client, _Signer());
      Future<Map<String, Object?>> retry() => repository.retryIntegration(
        integrationId: 'integration-id',
        requestId: 'original-request-id',
        runId: 'run',
        revision: 3,
        taskId: 'task',
        workspaceId: 'workspace',
      );
      expect((await retry())['state'], 'integrated');
      expect(client.calls, ['workflows.integrateResult']);
      expect(client.payloads.single, {
        'requestId': 'original-request-id',
        'runId': 'run',
        'revision': 3,
        'taskId': 'task',
        'workspaceId': 'workspace',
      });
      (client.response['request']! as Map)['id'] = 'another-integration';
      await expectLater(retry(), throwsFormatException);
    },
  );

  test(
    'response loss replays the exact signed statement without signing again',
    () async {
      final client = _Client()..response = review();
      final signer = _Signer();
      final repository = WorkflowLifecycleRepository(
        client,
        signer,
        now: () => now,
      );
      final snapshot = await repository.review('run', 3, 'plan');
      final pending = await repository.prepareDecision(
        snapshot,
        WorkflowHumanDecision.approve,
        '',
      );
      client.fail = true;
      await expectLater(repository.submitDecision(pending), throwsStateError);
      client.fail = false;
      client.response = {'decisionId': 'receipt'};
      await repository.submitDecision(pending);
      expect(signer.statements, hasLength(1));
      expect(client.calls, [
        'workflows.review',
        'workflows.decide',
        'workflows.decide',
      ]);
      expect(client.documents, [pending.document, pending.document]);
      final wire = jsonDecode(pending.document) as Map;
      expect(wire['statement']['challenge']['revision'], 3);
      expect(wire['proof'], hasLength(32));
      expect(wire.containsKey('actor'), isFalse);
    },
  );

  test('snapshot retains its challenge when the source map changes', () async {
    final source = review();
    final snapshot = WorkflowReviewSnapshot.fromJson(source);
    (source['challenge']! as Map)['revision'] = 9;
    snapshot.challenge['revision'] = 8;
    expect(snapshot.revision, 3);
  });

  test('rendered nested plan and evidence remain immutable', () {
    final stages = [
      {'id': 'foundation'},
    ];
    final artifacts = ['original'];
    final source = review();
    source['plan'] = <String, Object?>{
      ...source['plan']! as Map<String, Object?>,
      'stages': stages,
    };
    source['tasks'] = [
      {'artifacts': artifacts},
    ];
    final snapshot = WorkflowReviewSnapshot.fromJson(source);
    stages.first['id'] = 'changed';
    artifacts.add('changed');
    final frozenStages = snapshot.plan['stages']! as List;
    final frozenArtifacts = snapshot.tasks.first['artifacts']! as List;
    expect((frozenStages.first as Map)['id'], 'foundation');
    expect(frozenArtifacts, ['original']);
    expect(
      () => (frozenStages.first as Map)['id'] = 'changed',
      throwsUnsupportedError,
    );
    expect(() => frozenStages.clear(), throwsUnsupportedError);
    expect(() => frozenArtifacts.add('changed'), throwsUnsupportedError);
  });

  test('expired reviews and invalid reasons are never signed', () async {
    final signer = _Signer();
    final client = _Client();
    var clock = now.add(const Duration(minutes: 6));
    final repository = WorkflowLifecycleRepository(
      client,
      signer,
      now: () => clock,
    );
    final snapshot = WorkflowReviewSnapshot.fromJson(review());
    await expectLater(
      repository.prepareDecision(snapshot, WorkflowHumanDecision.approve, ''),
      throwsStateError,
    );
    clock = now;
    for (final reason in ['', '  ', '\u0000', '🚀' * 1025]) {
      await expectLater(
        repository.prepareDecision(
          snapshot,
          WorkflowHumanDecision.requestChanges,
          reason,
        ),
        throwsFormatException,
      );
    }
    expect(signer.statements, isEmpty);
    expect(client.calls, isEmpty);
  });
}

class _Signer implements WorkflowDecisionSigner {
  final statements = <String>[];
  @override
  Future<Uint8List> sign(String statementJson) async {
    statements.add(statementJson);
    return Uint8List(32);
  }
}

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = true;
  bool fail = false;
  final calls = <String>[];
  final payloads = <Map<String, Object?>>[];
  final documents = <String>[];
  Map<String, Object?> response = {};
  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    expect(capability, 'workflowRunLifecycleV1');
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(verb);
    payloads.add(Map.of(payload));
    if (payload['document'] case final String document) documents.add(document);
    if (fail) throw StateError('Response lost');
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
