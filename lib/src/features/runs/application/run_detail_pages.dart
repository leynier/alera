import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runs/application/run_board_pages.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_plan.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/infra/foreground_board_watch.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_detail_pages.g.dart';

/// One run: Overview, Tasks and the planning view all read it.
@Riverpod(retry: runNoRetry)
class RunDetail extends _$RunDetail {
  @override
  Stream<RunPageRead<RunSnapshot>> build(String runId) {
    final repository = ref.watch(runRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository.watchRun(runId).map(RunPageRead.new),
    );
  }

  Future<void> loadMoreTasks() async {
    final current = state.asData?.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextTaskId == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunPageRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runRepositoryProvider)
          .readRun(
            runId,
            afterTaskId: data.nextTaskId,
            revision: data.revision,
          );
      if (!ref.mounted || !identical(state.asData?.value.data, data)) return;
      if (next.revision != data.revision) {
        throw StateError('Tasks changed. Refresh to continue.');
      }
      state = AsyncData(
        RunPageRead(
          data.copyWith(
            tasks: List.unmodifiable([...data.tasks, ...next.tasks]),
            nextTaskId: next.nextTaskId,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.asData?.value.data, data)) {
        state = AsyncData(RunPageRead(data, pageError: error));
      }
    }
  }
}

/// One task with its history; older history loads on demand.
@Riverpod(retry: runNoRetry)
class RunTaskInspectionPage extends _$RunTaskInspectionPage {
  @override
  Stream<RunPageRead<TaskInspection>> build(String runId, String taskId) {
    final repository = ref.watch(runRepositoryProvider);
    return foregroundBoardWatch(
      ref.watch(appForegroundProvider),
      () => repository.watchTask(runId, taskId).map(RunPageRead.new),
    );
  }

  Future<void> loadMoreHistory() async {
    final current = state.asData?.value;
    if (current == null ||
        current.loadingMore ||
        current.data.nextCursor == null) {
      return;
    }
    final data = current.data;
    state = AsyncData(RunPageRead(data, loadingMore: true));
    try {
      final next = await ref
          .read(runRepositoryProvider)
          .readTask(runId, taskId, cursor: data.nextCursor);
      if (!ref.mounted || !identical(state.asData?.value.data, data)) return;
      if (next.revision != data.revision) {
        throw StateError('History changed. Refresh to continue.');
      }
      state = AsyncData(
        RunPageRead(
          data.copyWith(
            history: List.unmodifiable([...data.history, ...next.history]),
            nextCursor: next.nextCursor,
          ),
        ),
      );
    } on Object catch (error) {
      if (ref.mounted && identical(state.asData?.value.data, data)) {
        state = AsyncData(RunPageRead(data, pageError: error));
      }
    }
  }
}

/// A gate with its plan and evidence, read when a card expands.
@Riverpod(retry: runNoRetry)
Stream<RunGateDetail> runGateDetail(Ref ref, String gateId) =>
    ref.watch(runRepositoryProvider).watchGate(gateId);

/// The current plan of a run, for the approver and recipe facts. Keyed by
/// revision and approval state, so it re-reads when either changes.
@Riverpod(retry: runNoRetry)
Future<RunPlanView?> runPlan(
  Ref ref,
  String runId, {
  int? revision,
  String? state,
}) => ref.watch(runRepositoryProvider).plan(runId, revision: revision);
