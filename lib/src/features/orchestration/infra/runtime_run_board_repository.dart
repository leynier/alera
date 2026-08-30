import 'dart:convert';
import 'package:alera/src/features/orchestration/domain/task_inspection.dart';

import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/run_board_watch.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RunBoardUpdateRequired implements Exception {
  const RunBoardUpdateRequired();

  @override
  String toString() => 'Update the runtime to use Run Board.';
}

class RuntimeRunBoardRepository {
  RuntimeRunBoardRepository(this._client, this._coalescer);

  final RuntimeHostClient _client;
  final RuntimeChangeCoalescer _coalescer;

  Future<void> _requireCapability() async {
    final client = _client;
    if (client is! RuntimeHostCapabilityClient ||
        !await (client as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(aleraRuntimeHostRunBoardCapability)) {
      throw const RunBoardUpdateRequired();
    }
  }

  Future<RunBoardSnapshot> readBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) async {
    await _requireCapability();
    final payload = await _client.runtimeRequest(
      'orchestration.boardSnapshot',
      query.toJson(),
      runtimeSnapshotRequestTimeout,
    );
    return RunBoardSnapshot.fromJson(boardJsonObject(payload));
  }

  Future<RunSnapshot> readRun(
    String runId, {
    String? afterTaskId,
    int? revision,
    int limit = 100,
  }) async {
    await _requireCapability();
    final payload = await _client.runtimeRequest('orchestration.runSnapshot', {
      'run_id': runId,
      'after_task_id': ?afterTaskId,
      'revision': ?revision,
      'limit': limit,
    }, runtimeSnapshotRequestTimeout);
    return RunSnapshot.fromJson(boardJsonObject(payload));
  }

  Stream<RunBoardSnapshot> watchBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) => watchRunBoard(
    client: _client,
    coalescer: _coalescer,
    key: 'run-board:${jsonEncode(query.toJson())}',
    read: () => readBoard(query),
  );

  Stream<RunSnapshot> watchRun(String runId) => watchRunBoard(
    client: _client,
    coalescer: _coalescer,
    key: 'run-board-detail:$runId',
    read: () => readRun(runId),
  );

  Future<TaskInspection> readTask(
    String runId,
    String taskId, {
    TaskHistoryCursor? cursor,
    int limit = 20,
  }) async {
    await _requireCapability();
    final payload = await _client
        .runtimeRequest('orchestration.taskInspection', {
          'run_id': runId,
          'task_id': taskId,
          'cursor': ?cursor?.toJson(),
          'limit': limit,
        }, runtimeSnapshotRequestTimeout);
    return TaskInspection.fromJson(boardJsonObject(payload));
  }

  Stream<TaskInspection> watchTask(String runId, String taskId) =>
      watchRunBoard(
        client: _client,
        coalescer: _coalescer,
        key: 'run-board-task:$runId:$taskId',
        read: () => readTask(runId, taskId),
      );
}
