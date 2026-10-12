import 'package:alera_mobile/src/features/runs/domain/new_run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_inspection_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_timeline_models.dart';
import 'package:alera_mobile/src/features/runs/infra/mobile_runtime_run_repository.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_reader.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_run_providers.g.dart';

/// The paired runtime as the run screens see it. Rebuilds with every
/// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].
@riverpod
Future<MobileRunsClient> mobileRunsClient(Ref ref, String hostId) async {
  final client = await watchHostConnection(ref, hostId);
  if (!client.supportsRuns) throw const RunsUpdateRequired();
  return client;
}

@riverpod
Future<MobileRuntimeRunRepository> mobileRunRepository(
  Ref ref,
  String hostId,
) async => MobileRuntimeRunRepository(
  await ref.watch(mobileRunsClientProvider(hostId).future),
);

/// Runs per board page.
const int runBoardPageSize = 25;

/// One board group, filtered by the runtime, a page at a time. A change or
/// new filters start again from the first page.
@riverpod
class MobileRunBoard extends _$MobileRunBoard {
  bool _loadingMore = false;

  @override
  Future<RunBoardPage> build(
    String hostId, {
    RunBucket? bucket,
    String? search,
    String? workspaceId,
  }) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.board(
      bucket: bucket,
      search: search,
      workspaceId: workspaceId,
      limit: runBoardPageSize,
    );
  }

  /// Appends the next page, skipping runs already shown.
  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      final next = await repository.board(
        bucket: bucket,
        search: search,
        workspaceId: workspaceId,
        cursor: cursor,
        limit: runBoardPageSize,
      );
      if (!ref.mounted || state.value != current) return;
      state = AsyncData(mergeRunBoardPages(current, next));
    } finally {
      _loadingMore = false;
    }
  }
}

RunBoardPage mergeRunBoardPages(RunBoardPage current, RunBoardPage next) {
  final seen = <String>{for (final run in current.items) run.id};
  return RunBoardPage(
    revision: next.revision,
    counts: next.counts,
    items: <RunSummary>[
      ...current.items,
      for (final run in next.items)
        if (seen.add(run.id)) run,
    ],
    nextCursor: next.nextCursor,
  );
}

/// Runs needing attention, for the dashboard and the Runs segment.
@riverpod
Future<int> mobileRunAttentionCount(Ref ref, String hostId) async {
  final page = await ref.watch(
    mobileRunBoardProvider(hostId, bucket: RunBucket.attention).future,
  );
  return page.counts.attention;
}

/// One run. A failed refresh keeps the last snapshot in `state.value`.
@riverpod
class MobileRunDetail extends _$MobileRunDetail {
  @override
  Future<RunDetail> build(String hostId, String runId) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.snapshot(runId);
  }
}

/// Events per timeline page.
const int runTimelinePageSize = 50;

/// A run's timeline, newest first; Load Older Events appends a page.
@riverpod
class MobileRunTimeline extends _$MobileRunTimeline {
  bool _loadingMore = false;

  @override
  Future<RunTimelinePage> build(
    String hostId,
    String runId, {
    String? taskId,
  }) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.timelineChanges.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(subscription.cancel);
    return repository.timeline(
      runId,
      taskId: taskId,
      limit: runTimelinePageSize,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      final next = await repository.timeline(
        runId,
        cursor: cursor,
        taskId: taskId,
        limit: runTimelinePageSize,
      );
      if (!ref.mounted || state.value != current) return;
      state = AsyncData(current.merge(next));
    } finally {
      _loadingMore = false;
    }
  }
}

/// One gate with its plan or evidence.
@riverpod
class MobileRunGate extends _$MobileRunGate {
  @override
  Future<RunGateDetail> build(String hostId, String gateId) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.gate(gateId);
  }
}

/// One task with its result, attempt, gates and history.
@riverpod
class MobileRunTask extends _$MobileRunTask {
  @override
  Future<RunTaskInspection> build(
    String hostId,
    String runId,
    String taskId,
  ) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.task(runId, taskId);
  }
}

/// Templates New Run offers, project recipes of [workspaceId] included.
@riverpod
Future<RecipeCatalog> mobileRecipeCatalog(
  Ref ref,
  String hostId, {
  String? workspaceId,
}) async {
  final repository = await ref.watch(
    mobileRunRepositoryProvider(hostId).future,
  );
  final subscription = repository.recipeChanges.listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(subscription.cancel);
  return repository.recipeCatalog(workspaceId: workspaceId);
}

@riverpod
Future<List<WorkspaceSummary>> mobileRunWorkspaces(
  Ref ref,
  String hostId,
) async {
  final repository = await ref.watch(
    mobileRunRepositoryProvider(hostId).future,
  );
  return repository.workspaces();
}

@riverpod
Future<List<AgentProfileSummary>> mobileRunAgentProfiles(
  Ref ref,
  String hostId,
) async {
  final repository = await ref.watch(
    mobileRunRepositoryProvider(hostId).future,
  );
  return repository.agentProfiles();
}

/// The commit an isolated run in [workspaceId] would start from.
@riverpod
Future<RunSourceSnapshot> mobileRunSource(
  Ref ref,
  String hostId,
  String workspaceId,
) async {
  final repository = await ref.watch(
    mobileRunRepositoryProvider(hostId).future,
  );
  return repository.source(workspaceId);
}

class const MobileRunListState({
  final RunBucket? bucket,
  final String search = '',
  final String? workspaceId,
}) {
  bool get isFiltered =>
      bucket != null || search.trim().isNotEmpty || workspaceId != null;

  /// Groups the list shows, in order.
  List<RunBucket> get buckets =>
      bucket == null ? RunBucket.values : <RunBucket>[bucket!];
}

/// Filters of the runs list, kept per host while the app runs.
@Riverpod(keepAlive: true)
class MobileRunListController extends _$MobileRunListController {
  @override
  MobileRunListState build(String hostId) => const MobileRunListState();

  void setBucket(RunBucket? bucket) => state = MobileRunListState(
    bucket: bucket,
    search: state.search,
    workspaceId: state.workspaceId,
  );

  void setSearch(String search) => state = MobileRunListState(
    bucket: state.bucket,
    search: search,
    workspaceId: state.workspaceId,
  );

  void setWorkspace(String? workspaceId) => state = MobileRunListState(
    bucket: state.bucket,
    search: state.search,
    workspaceId: workspaceId,
  );

  void clear() => state = const MobileRunListState();
}
