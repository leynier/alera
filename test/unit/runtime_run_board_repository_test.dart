import 'dart:async';

import 'package:alera/src/features/orchestration/domain/task_inspection.dart';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  late _Client client;
  late RuntimeChangeCoalescer coalescer;
  late RuntimeRunBoardRepository repository;

  setUp(() {
    client = _Client();
    coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 5),
      maxDelay: const Duration(seconds: 5),
    );
    repository = RuntimeRunBoardRepository(client, coalescer);
  });
  tearDown(() async {
    coalescer.dispose();
    await client.events.close();
  });

  test('one aggregate request preserves filters and cursor', () async {
    final snapshot = await repository.readBoard(
      const RunBoardQuery(
        projectId: 'project',
        workspaceId: 'workspace',
        search: '%',
        bucket: RunBoardBucket.attention,
        limit: 10,
        cursor: RunBoardCursor('now', 'run', 7),
      ),
    );
    expect(client.calls, ['orchestration.boardSnapshot']);
    expect(client.payload, {
      'project_id': 'project',
      'workspace_id': 'workspace',
      'search': '%',
      'bucket': 'attention',
      'limit': 10,
      'cursor': {'created_at': 'now', 'id': 'run', 'revision': 7},
    });
    expect(snapshot.counts.attention, 3);
    expect(snapshot.items, isEmpty);
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
  });

  test('old host fails closed without issuing legacy calls', () async {
    client.supported = false;
    await expectLater(
      repository.readBoard(),
      throwsA(isA<RunBoardUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
    await expectLater(
      repository.readRun('run'),
      throwsA(isA<RunBoardUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
    await expectLater(
      repository.readTask('run', 'task'),
      throwsA(isA<RunBoardUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
  });

  test('task inspection uses the bounded endpoint and preserves evidence and cursor', () async {
    client.response = {
      'revision': 7,
      'task_id': 'task',
      'run_id': 'run',
      'title': 'Review',
      'description': 'Check the evidence',
      'description_truncated': false,
      'status': 'completed',
      'workspace_id': 'workspace',
      'stage_id': 'review',
      'workspace_name': 'Feature',
      'workspace_path': '/project/feature',
      'branch': 'feature',
      'base_sha': null,
      'profile': 'Reviewer',
      'terminal_handle': 'terminal',
      'dependencies': ['prior'],
      'dependencies_truncated': false,
      'result': {
        'summary': 'Verified',
        'completion_kind': 'success',
        'artifacts': ['report.md'],
        'validation': ['Tests passed'],
        'preview': null,
        'truncated': false,
      },
      'history': [
        {
          'id': 'event',
          'occurred_at': 'now',
          'kind': 'audit',
          'status': 'completed',
          'summary': 'Reviewed',
        },
      ],
      'next_cursor': {'occurred_at': 'now', 'id': 'event', 'revision': 7},
      'workflow': {
        'state': 'conflict',
        'execution_workspace_id': 'attempt',
        'integration_id': 'integration',
        'launch_id': 'launch',
        'worktree': '/project/attempt',
        'branch': 'alera/workflows/attempt',
        'base_sha': 'base',
        'integrated_sha': null,
        'conflict_paths': ['lib/feature.dart'],
        'conflicts_truncated': false,
        'error': null,
      },
    };
    final task = await repository.readTask(
      'run',
      'task',
      cursor: const TaskHistoryCursor('later', 'newer', 7),
      limit: 5,
    );
    expect(client.calls, ['orchestration.taskInspection']);
    expect(client.payload, {
      'run_id': 'run',
      'task_id': 'task',
      'limit': 5,
      'cursor': {'occurred_at': 'later', 'id': 'newer', 'revision': 7},
    });
    expect(task.baseSha, isNull);
    expect(task.profile, 'Reviewer');
    expect(task.result.summary, 'Verified');
    expect(task.result.artifacts, ['report.md']);
    expect(task.result.validation, ['Tests passed']);
    expect(task.history.single.summary, 'Reviewed');
    expect(task.nextCursor!.toJson(), {
      'occurred_at': 'now',
      'id': 'event',
      'revision': 7,
    });
    expect(task.workflow!.state, 'conflict');
    expect(task.workflow!.executionWorkspaceId, 'attempt');
    expect(task.workflow!.conflictPaths, ['lib/feature.dart']);
    expect(() => task.history.clear(), throwsUnsupportedError);
    expect(() => task.dependencies.clear(), throwsUnsupportedError);
    expect(() => task.result.artifacts.clear(), throwsUnsupportedError);
  });

  test(
    'populated board preserves run ownership and pagination cursor',
    () async {
      const cursor = {'created_at': '2026-08-29', 'id': 'run', 'revision': 7};
      client.response = {
        ..._snapshot,
        'items': [
          {..._run, 'project_id': 'project', 'project_name': 'Alera'},
        ],
        'next_cursor': cursor,
      };
      final snapshot = await repository.readBoard();
      expect(snapshot.revision, 7);
      expect(snapshot.counts.attention, 3);
      expect(snapshot.counts.active, 4);
      expect(snapshot.counts.history, 8);
      final run = snapshot.items.single;
      expect(run.id, 'run');
      expect(run.objective, 'Objective');
      expect(run.workspaceId, 'owner');
      expect(run.projectId, 'project');
      expect(run.projectName, 'Alera');
      expect(run.bucket, RunBoardBucket.attention);
      expect(run.policyStatus, 'draft');
      expect(run.taskCount, 1);
      expect(snapshot.nextCursor!.createdAt, '2026-08-29');
      expect(snapshot.nextCursor!.id, 'run');
      expect(snapshot.nextCursor!.revision, 7);
      expect(snapshot.nextCursor!.toJson(), cursor);
      expect(() => snapshot.items.clear(), throwsUnsupportedError);
    },
  );

  test('malformed payload is not mistaken for an empty board', () async {
    client.response = {'items': []};
    await expectLater(repository.readBoard(), throwsA(isA<TypeError>()));
  });

  test(
    'bursts refresh once; cancelled watcher releases events and queued work',
    () => fakeAsync((time) {
      final snapshots = <RunBoardSnapshot>[];
      final sub = repository.watchBoard().listen(snapshots.add);
      time.flushMicrotasks();
      expect(client.calls.length, 1);
      for (var i = 0; i < 50; i++) {
        client.emit(runBoardChangedEvent);
      }
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 10));
      expect(client.calls.length, 2);
      expect(snapshots.length, 2);
      client.emit(runBoardChangedEvent);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect(client.events.hasListener, isFalse);
      expect(client.calls.length, 2);
    }),
  );

  test(
    'errors remain visible and reconnect recovers the same subscription',
    () async {
      final errors = <Object>[];
      final snapshots = <RunBoardSnapshot>[];
      client.fail = true;
      final sub = repository.watchBoard().listen(
        snapshots.add,
        onError: errors.add,
      );
      addTearDown(sub.cancel);
      await _settle();
      expect(errors, hasLength(1));
      expect(client.calls, hasLength(1));
      await _settle();
      expect(client.calls, hasLength(1), reason: 'no hidden polling');
      client.fail = false;
      client.emit(aleraRuntimeHostConnectedEvent);
      await _settle();
      expect(snapshots, hasLength(1));
      client.emit(aleraRuntimeHostDisconnectedEvent);
      await _settle();
      expect(errors.last, isA<TerminalHostConnectionClosedException>());
      expect(client.calls, hasLength(2));
    },
  );

  test('unsupported host does not spin and can recover after update', () async {
    client.supported = false;
    final errors = <Object>[];
    final sub = repository.watchBoard().listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);
    await _settle();
    expect(errors.single, isA<RunBoardUpdateRequired>());
    expect(client.calls, isEmpty);
    client.supported = true;
    client.emit(aleraRuntimeHostConnectedEvent);
    await _settle();
    expect(client.calls, hasLength(1));
  });

  test(
    'events during a request do not overlap reads and cause one follow-up',
    () async {
      final pending = Completer<Object?>();
      client.pending = pending.future;
      final sub = repository.watchBoard().listen((_) {});
      addTearDown(sub.cancel);
      await _settle();
      for (var i = 0; i < 30; i++) {
        client.emit(runBoardChangedEvent);
      }
      await _settle();
      expect(client.calls, hasLength(1));
      client.pending = null;
      pending.complete(_snapshot);
      await _settle();
      expect(client.calls, hasLength(2));
      expect(client.maxInFlight, 1);
    },
  );

  test(
    'cancellation during initial read drops the result and any follow-up',
    () async {
      final pending = Completer<Object?>();
      client.pending = pending.future;
      final snapshots = <RunBoardSnapshot>[];
      final sub = repository.watchBoard().listen(snapshots.add);
      await _settle();
      client.emit(runBoardChangedEvent);
      await sub.cancel();
      pending.complete(_snapshot);
      await _settle();
      expect(snapshots, isEmpty);
      expect(client.calls, hasLength(1));
    },
  );

  test('a late response cannot hide a disconnection', () async {
    final pending = Completer<Object?>();
    client.pending = pending.future;
    final snapshots = <RunBoardSnapshot>[];
    final errors = <Object>[];
    final sub = repository.watchBoard().listen(
      snapshots.add,
      onError: errors.add,
    );
    addTearDown(sub.cancel);
    await _settle();
    client.emit(aleraRuntimeHostDisconnectedEvent);
    await _settle();
    pending.complete(_snapshot);
    await _settle();
    expect(snapshots, isEmpty);
    expect(errors.single, isA<TerminalHostConnectionClosedException>());
  });

  test(
    'run reads send bounded paging coordinates and parse immutable tasks',
    () async {
      client.response = {
        'revision': 7,
        'run': _run,
        'objective': 'Objective',
        'objective_truncated': false,
        'tasks': [
          {
            'id': 'task',
            'title': 'Task',
            'status': 'pending',
            'workspace_id': 'worker',
            'stage_id': 'build',
          },
        ],
        'next_task_id': 'task',
      };
      final snapshot = await repository.readRun(
        'run',
        afterTaskId: 'before',
        revision: 7,
        limit: 12,
      );
      expect(client.calls, ['orchestration.runSnapshot']);
      expect(client.payload, {
        'run_id': 'run',
        'after_task_id': 'before',
        'revision': 7,
        'limit': 12,
      });
      expect(snapshot.tasks.single.workspaceId, 'worker');
      expect(snapshot.run.workspaceId, 'owner');
      expect(() => snapshot.tasks.clear(), throwsUnsupportedError);
    },
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

const _snapshot = <String, Object?>{
  'revision': 7,
  'counts': {'attention': 3, 'active': 4, 'history': 8},
  'items': [],
  'next_cursor': null,
};

const _run = <String, Object?>{
  'id': 'run',
  'objective': 'Objective',
  'status': 'running',
  'bucket': 'attention',
  'workspace_id': 'owner',
  'created_at': '2026-08-29',
  'last_activity_at': '2026-08-29',
  'policy_status': 'draft',
  'task_count': 1,
  'completed_count': 0,
  'running_count': 0,
  'failed_count': 0,
  'stalled_count': 0,
  'blocked_count': 0,
  'pending_gate_count': 0,
};

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final events = StreamController<RuntimeHostEvent>.broadcast();
  final calls = <String>[];
  Map<String, Object?>? payload;
  Object? response = _snapshot;
  Future<Object?>? pending;
  bool supported = true;
  bool fail = false;
  int inFlight = 0;
  int maxInFlight = 0;

  void emit(String name) => events.add(RuntimeHostEvent(name, const {}));

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    expect(capability, aleraRuntimeHostRunBoardCapability);
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> data = const {},
    Duration? timeout,
  ]) async {
    calls.add(type);
    payload = data;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (fail) throw StateError('Disconnected');
      return await (pending ?? Future.value(response));
    } finally {
      inFlight--;
    }
  }
}
