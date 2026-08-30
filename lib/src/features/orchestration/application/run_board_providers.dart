import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_board_providers.g.dart';

@riverpod
RuntimeRunBoardRepository runBoardRepository(Ref ref) =>
    RuntimeRunBoardRepository(
      ref.watch(runtimeHostClientProvider),
      ref.watch(runtimeChangeCoalescerProvider),
    );

@riverpod
Stream<RunBoardSnapshot> runBoardSnapshot(
  Ref ref, {
  String? projectId,
  String? workspaceId,
  String? search,
  RunBoardBucket? bucket,
}) => ref
    .watch(runBoardRepositoryProvider)
    .watchBoard(
      RunBoardQuery(
        projectId: projectId,
        workspaceId: workspaceId,
        search: search,
        bucket: bucket,
      ),
    );

@riverpod
Stream<RunSnapshot> orchestrationRunSnapshot(Ref ref, String runId) =>
    ref.watch(runBoardRepositoryProvider).watchRun(runId);
