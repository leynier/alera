import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/orchestration/application/run_board_providers.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/task_inspection.dart';
import 'package:alera/src/features/orchestration/infra/foreground_board_watch.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_board_pages.g.dart';

class RunBoardRead<T> {
  const RunBoardRead(this.data, {this.loadingMore = false, this.pageError});
  final T data;
  final bool loadingMore;
  final Object? pageError;
}

class TaskInspectionPage {
  TaskInspectionPage(this.inspection, this.history, this.nextCursor);
  final TaskInspection inspection;
  final List<TaskHistoryEntry> history;
  final TaskHistoryCursor? nextCursor;
}

Duration? _noRetry(int count, Object error) => null;

@Riverpod(retry: _noRetry)
Stream<RunBoardCounts> runBoardAttention(Ref ref) {
  final repository = ref.watch(runBoardRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository
        .watchBoard(const RunBoardQuery(limit: 1))
        .map((page) => page.counts),
  );
}

@Riverpod(retry: _noRetry)
class RunBoardListPage extends _$RunBoardListPage {
  @override
  Stream<RunBoardRead<RunBoardSnapshot>> build({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBoardBucket? bucket,
  }) {
    final repository = ref.watch(runBoardRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository
          .watchBoard(
            RunBoardQuery(
              projectId: projectId,
              workspaceId: workspaceId,
              search: search.isEmpty ? null : search,
              bucket: bucket,
            ),
          )
          .map(RunBoardRead.new),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextCursor == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunBoardRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runBoardRepositoryProvider)
          .readBoard(
            RunBoardQuery(
              projectId: projectId,
              workspaceId: workspaceId,
              search: search.isEmpty ? null : search,
              bucket: bucket,
              cursor: data.nextCursor,
            ),
          );
      if (!ref.mounted || !identical(state.value?.data, data)) return;
      if (next.revision != data.revision) {
        throw StateError('The run list changed. Refresh to continue.');
      }
      state = AsyncData(
        RunBoardRead(
          RunBoardSnapshot(
            revision: next.revision,
            counts: next.counts,
            items: [...data.items, ...next.items],
            nextCursor: next.nextCursor,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.value?.data, data)) {
        state = AsyncData(RunBoardRead(data, pageError: error));
      }
    }
  }
}

@Riverpod(retry: _noRetry)
class RunTaskPage extends _$RunTaskPage {
  @override
  Stream<RunBoardRead<RunSnapshot>> build(String runId) {
    final repository = ref.watch(runBoardRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository.watchRun(runId).map(RunBoardRead.new),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextTaskId == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunBoardRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runBoardRepositoryProvider)
          .readRun(
            runId,
            afterTaskId: data.nextTaskId,
            revision: data.revision,
          );
      if (!ref.mounted || !identical(state.value?.data, data)) return;
      if (next.revision != data.revision) {
        throw StateError('Tasks changed. Refresh to continue.');
      }
      state = AsyncData(
        RunBoardRead(
          RunSnapshot(
            revision: next.revision,
            run: next.run,
            objective: next.objective,
            objectiveTruncated: next.objectiveTruncated,
            tasks: [...data.tasks, ...next.tasks],
            nextTaskId: next.nextTaskId,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.value?.data, data)) {
        state = AsyncData(RunBoardRead(data, pageError: error));
      }
    }
  }
}

@Riverpod(retry: _noRetry)
class RunTaskInspectionPage extends _$RunTaskInspectionPage {
  @override
  Stream<RunBoardRead<TaskInspectionPage>> build(String runId, String taskId) {
    final repository = ref.watch(runBoardRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository
          .watchTask(runId, taskId)
          .map(
            (task) => RunBoardRead(
              TaskInspectionPage(task, task.history, task.nextCursor),
            ),
          ),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextCursor == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunBoardRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runBoardRepositoryProvider)
          .readTask(runId, taskId, cursor: data.nextCursor);
      if (!ref.mounted || !identical(state.value?.data, data)) return;
      if (next.revision != data.inspection.revision) {
        throw StateError('History changed. Refresh to continue.');
      }
      state = AsyncData(
        RunBoardRead(
          TaskInspectionPage(
            data.inspection,
            List.unmodifiable([...data.history, ...next.history]),
            next.nextCursor,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.value?.data, data)) {
        state = AsyncData(RunBoardRead(data, pageError: error));
      }
    }
  }
}
