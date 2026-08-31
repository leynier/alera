import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/task_inspection.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';

RunSummary boardRun({
  String id = 'run-1',
  String? objective,
  RunBoardBucket bucket = RunBoardBucket.attention,
}) => RunSummary(
  id: id,
  objective: objective ?? 'Deliver reviewed workflow plans',
  status: bucket == RunBoardBucket.history ? 'completed' : 'running',
  bucket: bucket,
  workspaceId: 'ws-1',
  workspaceName: 'Workflow Delivery',
  projectId: 'project-1',
  projectName: 'Alera',
  createdAt: '2026-08-30T10:00:00Z',
  lastActivityAt: '2026-08-30T10:01:00Z',
  policyStatus: bucket == RunBoardBucket.attention ? 'draft' : 'approved',
  taskCount: 3,
  completedCount: bucket == RunBoardBucket.history
      ? 3
      : bucket == RunBoardBucket.attention
      ? 2
      : 1,
  runningCount: bucket == RunBoardBucket.active ? 1 : 0,
  failedCount: 0,
  stalledCount: 0,
  blockedCount: bucket == RunBoardBucket.attention ? 1 : 0,
  pendingGateCount: bucket == RunBoardBucket.attention ? 1 : 0,
);

RunBoardSnapshot boardSnapshot({
  int revision = 1,
  List<RunSummary>? items,
  RunBoardCursor? nextCursor,
}) => RunBoardSnapshot(
  revision: revision,
  counts: const RunBoardCounts(attention: 1, active: 1, history: 1),
  items:
      items ??
      [
        boardRun(),
        boardRun(
          id: 'run-2',
          objective: 'Repair terminal navigation',
          bucket: RunBoardBucket.active,
        ),
        boardRun(
          id: 'run-3',
          objective: 'Refresh shared tokens',
          bucket: RunBoardBucket.history,
        ),
      ],
  nextCursor: nextCursor,
);

RunSnapshot boardRunDetail({
  int revision = 1,
  String runId = 'run-1',
  String? nextTaskId,
  List<RunTaskSummary>? tasks,
}) => RunSnapshot(
  revision: revision,
  run: boardRun(id: runId),
  objective: 'Deliver reviewed workflow plans with explicit human approvals and traceable evidence.',
  objectiveTruncated: false,
  nextTaskId: nextTaskId,
  tasks:
      tasks ??
      const [
        RunTaskSummary(
          id: 'task-1',
          title: 'Define the plan contract',
          status: 'completed',
          workspaceId: 'ws-1',
          stageId: 'Foundation',
          workflowState: 'integrated',
        ),
        RunTaskSummary(
          id: 'task-2',
          title: 'Build the review surface',
          status: 'completed',
          workspaceId: 'ws-1',
          stageId: 'Product',
          dependencies: ['task-1'],
          workflowState: 'result_ready',
        ),
        RunTaskSummary(
          id: 'task-3',
          title: 'Verify keyboard and recovery',
          status: 'blocked',
          workspaceId: 'ws-1',
          stageId: 'Product',
          dependencies: ['task-2'],
        ),
      ],
);

TaskInspection boardTask({
  int revision = 1,
  String taskId = 'task-2',
  String status = 'completed',
  String workflowState = 'result_ready',
  String? workflowError,
  String? terminalHandle = 'session-1',
  List<TaskHistoryEntry>? history,
  TaskHistoryCursor? nextCursor,
}) => TaskInspection(
  revision: revision,
  taskId: taskId,
  runId: 'run-1',
  title: 'Build the review surface',
  description:
      'Keep reviews accessible, durable and bound to the exact plan revision.',
  status: status,
  workspaceId: 'ws-1',
  workspaceName: 'Workflow Delivery',
  workspacePath: '/projects/alera/workflow-delivery',
  branch: 'feature/review-surface',
  profile: 'Implementation',
  terminalHandle: terminalHandle,
  workflow: TaskWorkflowInspection(
    state: workflowState,
    executionWorkspaceId: 'workflow-attempt-2',
    launchId: 'launch-2',
    worktree: '/projects/alera/workflow-attempt-2',
    branch: 'alera/workflows/workflow-attempt-2',
    baseSha: '1234567890abcdef1234567890abcdef12345678',
    error: workflowError,
  ),
  dependencies: const ['task-1'],
  result: const TaskResultInspection(
    summary: 'Review surface implemented.',
    completionKind: 'success',
    artifacts: ['docs/review-flow.md'],
    validation: ['Widget tests passed; keyboard traversal verified.'],
  ),
  history:
      history ??
      const [
        TaskHistoryEntry(
          id: 'attempt-1',
          occurredAt: '2026-08-30T10:01:00Z',
          kind: 'attempt',
          status: 'completed',
          summary: 'Implementation',
        ),
      ],
  nextCursor: nextCursor,
);

class BoardTestForeground implements AppForeground {
  bool visible = true;
  final events = StreamController<bool>.broadcast(sync: true);
  @override
  bool get isForeground => visible;
  @override
  Stream<bool> get changes => events.stream;
  void setVisible(bool value) {
    visible = value;
    events.add(value);
  }

  @override
  void dispose() {
    unawaited(events.close());
  }
}

class BoardTestRepository implements RuntimeRunBoardRepository {
  RunBoardSnapshot board = boardSnapshot();
  RunSnapshot run = boardRunDetail();
  TaskInspection task = boardTask();
  Object? error;
  final events = StreamController<void>.broadcast(sync: true);
  int watchers = 0;
  int boardReads = 0;
  int runReads = 0;
  int taskReads = 0;
  final queries = <RunBoardQuery>[];
  Future<RunBoardSnapshot>? nextBoard;
  Future<RunSnapshot>? nextRun;
  Future<TaskInspection>? nextTask;

  Stream<T> _watch<T>(Future<T> Function() read) => Stream<T>.multi((output) {
    watchers++;
    var closed = false;
    Future<void> emit() async {
      try {
        final value = await read();
        if (!closed) output.add(value);
      } on Object catch (error, stack) {
        if (!closed) output.addError(error, stack);
      }
    }

    final subscription = events.stream.listen((_) => unawaited(emit()));
    unawaited(emit());
    output.onCancel = () async {
      closed = true;
      watchers--;
      await subscription.cancel();
    };
  });
  @override
  Future<RunBoardSnapshot> readBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) async {
    boardReads++;
    queries.add(query);
    if (error != null) throw error!;
    return query.cursor == null
        ? board
        : await (nextBoard ?? Future.value(board));
  }

  @override
  Future<RunSnapshot> readRun(
    String runId, {
    String? afterTaskId,
    int? revision,
    int limit = 100,
  }) async {
    runReads++;
    if (error != null) throw error!;
    return afterTaskId == null ? run : await (nextRun ?? Future.value(run));
  }

  @override
  Future<TaskInspection> readTask(
    String runId,
    String taskId, {
    TaskHistoryCursor? cursor,
    int limit = 20,
  }) async {
    taskReads++;
    if (error != null) throw error!;
    return cursor == null ? task : await (nextTask ?? Future.value(task));
  }

  @override
  Stream<RunBoardSnapshot> watchBoard([
    RunBoardQuery query = const RunBoardQuery(),
  ]) => _watch(() => readBoard(query));
  @override
  Stream<RunSnapshot> watchRun(String runId) => _watch(() => readRun(runId));
  @override
  Stream<TaskInspection> watchTask(String runId, String taskId) =>
      _watch(() => readTask(runId, taskId));
  void dispose() {
    unawaited(events.close());
  }
}
