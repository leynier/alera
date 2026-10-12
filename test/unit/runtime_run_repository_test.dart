import 'dart:async';

import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/infra/runtime_run_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_cleanup_fixture.dart';
import '../support/runs_fixtures.dart';

void main() {
  late _Client client;
  late RuntimeChangeCoalescer coalescer;
  late RuntimeRunRepository repository;

  setUp(() {
    client = _Client();
    coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 5),
      maxDelay: const Duration(seconds: 5),
    );
    repository = RuntimeRunRepository(client, coalescer);
  });
  tearDown(() async {
    coalescer.dispose();
    await client.events.close();
  });

  test('runsChanged and recipesChanged reach the app', () {
    expect(runtimeHostEventNames, contains('runsChanged'));
    expect(runtimeHostEventNames, contains('recipesChanged'));
    expect(runtimeHostEventNames, contains('conversationsChanged'));
    expect(runtimeHostEventNames, isNot(contains('orchestrationBoardChanged')));
  });

  test('a host without runsV1 fails closed without any request', () async {
    client.supported = false;
    await expectLater(
      repository.readBoard(),
      throwsA(isA<RunsUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
    expect(client.capabilities, <String>{aleraRuntimeHostRunsCapability});
  });

  test('the board sends camelCase filters and decodes rows', () async {
    client.response = <String, Object?>{
      'revision': 7,
      'counts': <String, Object?>{'attention': 2, 'active': 1, 'history': 3},
      'items': <Object?>[runSummaryJson()],
      'nextCursor': <String, Object?>{
        'createdAt': '2026-09-30T10:00:00Z',
        'id': 'run-1',
        'revision': 7,
      },
    };
    final page = await repository.readBoard(
      const RunBoardQuery(
        projectId: 'project',
        workspaceId: 'workspace',
        search: 'oauth',
        bucket: RunBucket.attention,
        limit: 10,
        cursor: RunBoardCursor(createdAt: 'at', id: 'run', revision: 3),
      ),
    );
    expect(client.calls.single, 'runs.board');
    expect(client.payload, <String, Object?>{
      'projectId': 'project',
      'workspaceId': 'workspace',
      'search': 'oauth',
      'bucket': 'attention',
      'cursor': <String, Object?>{
        'createdAt': 'at',
        'id': 'run',
        'revision': 3,
      },
      'limit': 10,
    });
    final run = page.items.single;
    expect(page.counts.attention, 2);
    expect(run.isolated, isTrue);
    expect(run.pendingGateKinds, <String>['stage']);
    expect(page.nextCursor?.id, 'run-1');
  });

  test('resolveGate carries the request id and evidence digest', () async {
    client.response = <String, Object?>{
      'requestId': 'request',
      'gate': runGateJson(status: 'resolved'),
      'runId': 'run-1',
      'runStatus': 'running',
      'planRevision': 2,
      'changesRequested': false,
      'coordinatorAction': 'none',
    };
    final receipt = await repository.resolveGate(
      requestId: 'request',
      gateId: 'gate-stage',
      decision: RunGateOptions.approve,
      expectedEvidenceDigest: 'digest-1',
    );
    expect(client.calls.single, 'runs.resolveGate');
    expect(client.payload, <String, Object?>{
      'requestId': 'request',
      'gateId': 'gate-stage',
      'decision': 'approve',
      'expectedEvidenceDigest': 'digest-1',
    });
    expect(receipt.gate.status, RunGateStatus.resolved);
  });

  test('control always sends the expected sequence', () async {
    client.response = <String, Object?>{
      'requestId': 'request',
      'runId': 'run-1',
      'action': 'pause',
      'sequence': 4,
      'status': 'paused',
    };
    await repository.control(
      requestId: 'request',
      runId: 'run-1',
      expectedSequence: 3,
      action: RunControlAction.pause,
    );
    expect(client.payload, <String, Object?>{
      'requestId': 'request',
      'runId': 'run-1',
      'expectedSequence': 3,
      'action': 'pause',
    });
  });

  test('create sends a recipe only for isolated runs', () async {
    client.response = <String, Object?>{
      'run': <String, Object?>{
        'runId': 'run-new',
        'status': 'planning',
        'isolation': 'isolated',
        'coordinatorTabId': 'tab',
        'coordinatorProfileId': 'codex',
      },
      'coordinator': null,
    };
    await repository.create(
      const RunCreateRequest(
        requestId: 'a',
        workspaceId: 'ws',
        objective: 'Ship it',
        recipeSource: <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
        coordinatorProfileId: 'codex',
        roleProfiles: <String, String>{'worker': 'codex'},
        maxConcurrent: 4,
        approvalRequired: true,
      ),
    );
    expect(client.payload, <String, Object?>{
      'requestId': 'a',
      'workspaceId': 'ws',
      'objective': 'Ship it',
      'isolation': 'isolated',
      'coordinatorProfileId': 'codex',
      'recipeSource': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
      'roleProfiles': <String, String>{'worker': 'codex'},
      'maxConcurrent': 4,
      'approvalRequired': true,
    });
    await repository.create(
      const RunCreateRequest(
        requestId: 'b',
        workspaceId: 'ws',
        objective: 'Ship it',
        isolation: RunIsolation.shared,
        recipeSource: <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
        coordinatorProfileId: 'codex',
        roleProfiles: <String, String>{'worker': 'codex'},
        workerProfileId: 'cursor',
        maxConcurrent: 2,
      ),
    );
    expect(client.payload, <String, Object?>{
      'requestId': 'b',
      'workspaceId': 'ws',
      'objective': 'Ship it',
      'isolation': 'shared',
      'coordinatorProfileId': 'codex',
      'workerProfileId': 'cursor',
      'maxConcurrent': 2,
      'approvalRequired': false,
    });
  });

  test('the timeline pages with an opaque cursor and kind filter', () async {
    client.response = <String, Object?>{
      'runId': 'run-1',
      'items': <Object?>[
        <String, Object?>{
          'id': 'm',
          'source': 'message',
          'kind': 'message',
          'createdAt': '2026-09-30T13:58:00Z',
          'summary': 'Secret missing',
          'payload': null,
          'messageType': 'escalation',
          'from': 'w-3',
          'to': 'coordinator',
          'body': 'The OAuth secret is missing.',
          'truncated': true,
        },
      ],
      'nextCursor': 'at|key',
    };
    final page = await repository.readTimeline(
      'run-1',
      cursor: 'before|key',
      kinds: const <String>['message'],
    );
    expect(client.payload, <String, Object?>{
      'runId': 'run-1',
      'cursor': 'before|key',
      'limit': 50,
      'kinds': <String>['message'],
    });
    expect(page.items.single.isMessage, isTrue);
    expect(page.items.single.truncated, isTrue);
    expect(page.nextCursor, 'at|key');
  });

  test(
    'the timeline re-reads on conversationsChanged, the board does not',
    () async {
      client.response = <String, Object?>{
        'runId': 'run-1',
        'items': <Object?>[],
      };
      final timeline = <Object?>[];
      final subscription = repository
          .watchTimeline('run-1')
          .listen(timeline.add);
      await _settle();
      expect(timeline, hasLength(1));
      client.emit('conversationsChanged');
      await _settle();
      expect(timeline, hasLength(2));
      await subscription.cancel();

      client.response = <String, Object?>{'revision': 1, 'items': <Object?>[]};
      final boards = <Object?>[];
      final board = repository.watchBoard().listen(boards.add);
      await _settle();
      client.emit('conversationsChanged');
      await _settle();
      expect(boards, hasLength(1));
      client.emit('runsChanged');
      await _settle();
      expect(boards, hasLength(2));
      await board.cancel();
    },
  );

  test('cleanup previews send the selection and apply confirms it', () async {
    client.response = cleanupPreviewFixture();
    final preview = await repository.previewCleanup('cleanup', 'run', {
      'workspace': false,
    });
    expect(client.calls.last, 'runs.previewCleanup');
    expect(client.payload, <String, Object?>{
      'id': 'cleanup',
      'runId': 'run',
      'resources': <Object?>[
        <String, Object?>{'workspaceId': 'workspace', 'removeBranch': false},
      ],
    });
    expect(preview.digest, 'reviewed-digest');
    // A preview that dropped the branch the user chose to delete is refused.
    await expectLater(
      repository.previewCleanup('cleanup', 'run', {'workspace': true}),
      throwsFormatException,
    );
    await expectLater(
      repository.previewCleanup('cleanup', 'run', const {}),
      throwsFormatException,
    );
  });

  test('apply sends confirm, retry and abandon bind the digest', () async {
    final preview = RunCleanupPreview.fromJson(cleanupPreviewFixture());
    client.response = cleanupStatusFixture('retired');
    await repository.applyCleanup(preview);
    expect(client.calls.last, 'runs.applyCleanup');
    expect(client.payload, <String, Object?>{
      'id': 'cleanup',
      'digest': 'reviewed-digest',
      'confirm': true,
    });
    await repository.applyCleanup(preview, retry: true);
    expect(client.calls.last, 'runs.retryCleanup');
    expect(client.payload, <String, Object?>{
      'id': 'cleanup',
      'digest': 'reviewed-digest',
    });
    client.response = cleanupStatusFixture('attention');
    await expectLater(
      repository.abandonCleanup(preview),
      throwsFormatException,
    );
    client.response = cleanupStatusFixture('abandoned');
    expect(
      (await repository.abandonCleanup(preview)).state,
      RunCleanupState.abandoned,
    );
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final StreamController<RuntimeHostEvent> events =
      StreamController<RuntimeHostEvent>.broadcast();
  final List<String> calls = <String>[];
  final Set<String> capabilities = <String>{};
  Map<String, Object?>? payload;
  Object? response = const <String, Object?>{};
  bool supported = true;

  void emit(String name) =>
      events.add(RuntimeHostEvent(name, const <String, Object?>{}));

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    capabilities.add(capability);
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> data = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add(type);
    payload = data;
    return response;
  }
}
