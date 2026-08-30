import 'package:alera/src/features/orchestration/domain/run_board_location.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_board_navigation.g.dart';

// Retain only navigation, never runtime snapshots or subscriptions.
@Riverpod(keepAlive: true)
class RunBoardNavigation extends _$RunBoardNavigation {
  @override
  RunBoardLocation build() => const RunBoardLocation();
  void open() => state = state.copyWith(visible: true);
  void close() => state = state.copyWith(visible: false);
  void selectRun(String? id) => state = state.copyWith(runId: id, taskId: null);
  void selectTask(String? id) => state = state.copyWith(taskId: id);
  void search(String value) => state = state.copyWith(search: value);
  void selectBucket(RunBoardBucket? bucket) =>
      state = state.copyWith(bucket: bucket);
  void selectProject(String? id) =>
      state = state.copyWith(projectId: id, workspaceId: null);
  void selectWorkspace(String? id) => state = state.copyWith(workspaceId: id);
  void clearFilters() => state = state.copyWith(
    projectId: null,
    workspaceId: null,
    search: '',
    bucket: null,
  );
}
