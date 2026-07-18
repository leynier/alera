import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_activity_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_activity_controller.g.dart';

/// Delay between an activity event and its batched write to Drift so bursts of
/// agent transitions produce a single disk write.
const Duration workspaceActivityFlushDelay = Duration(seconds: 2);

/// Tracks the last discrete activity timestamp per workspace (agent state
/// transitions, terminal lifecycle) and persists it with a debounce. State is
/// the in-memory map used by the Agent Activity sort as its recency fallback.
@Riverpod(keepAlive: true)
class WorkspaceActivityController extends _$WorkspaceActivityController {
  WorkspaceActivityRepository? _repository;
  final Map<String, DateTime> _dirty = <String, DateTime>{};
  Timer? _flushTimer;

  @override
  Map<String, DateTime> build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
    });
    return const <String, DateTime>{};
  }

  /// Injects the persistence backend and seeds state from disk. Called by the
  /// coordinator once the database is available.
  Future<void> attachRepository(WorkspaceActivityRepository repository) async {
    _repository = repository;
    final persisted = await repository.loadAll();
    // In-memory entries recorded before the seed win: they are newer.
    state = <String, DateTime>{...persisted, ...state};
  }

  void recordActivity(String workspaceId, DateTime at) {
    final current = state[workspaceId];
    if (current != null && !at.isAfter(current)) {
      return;
    }
    state = <String, DateTime>{...state, workspaceId: at};
    _dirty[workspaceId] = at;
    _scheduleFlush();
  }

  void removeWorkspace(String workspaceId) {
    if (!state.containsKey(workspaceId)) {
      return;
    }
    final next = Map<String, DateTime>.from(state)..remove(workspaceId);
    state = next;
    _dirty.remove(workspaceId);
    final repository = _repository;
    if (repository != null) {
      unawaited(repository.remove(workspaceId).catchError((_) {}));
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(workspaceActivityFlushDelay, () {
      _flushTimer = null;
      final repository = _repository;
      if (repository == null || _dirty.isEmpty) {
        return;
      }
      final batch = Map<String, DateTime>.from(_dirty);
      _dirty.clear();
      unawaited(repository.upsertAll(batch).catchError((_) {}));
    });
  }
}

/// Feeds [WorkspaceActivityController] from discrete agent status transitions.
/// Tool-by-tool updates within one state do not count as activity - only a
/// `state`/`stateStartedAt` change marks the workspace as active.
@Riverpod(keepAlive: true)
void workspaceActivityCoordinator(Ref ref) {
  ref.listen<Map<String, AgentStatusEntry>>(agentStatusControllerProvider, (
    previous,
    next,
  ) {
    final controller = ref.read(workspaceActivityControllerProvider.notifier);
    for (final entry in next.entries) {
      final before = previous?[entry.key];
      final after = entry.value;
      final transitioned =
          before == null ||
          before.state != after.state ||
          before.stateStartedAt != after.stateStartedAt ||
          before.interrupted != after.interrupted;
      if (transitioned) {
        controller.recordActivity(after.workspaceId, after.stateStartedAt);
      }
    }
  });
}
