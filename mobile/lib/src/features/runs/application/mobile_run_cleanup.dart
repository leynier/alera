import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_cleanup_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mobile_run_cleanup.g.dart';

/// The worktrees an isolated run kept and the cleanups already tried.
class const RunResourcesSnapshot({
  required final List<RunResource> resources,
  required final List<RunCleanupHistoryEntry> history,
});

@riverpod
class MobileRunResources extends _$MobileRunResources {
  @override
  Future<RunResourcesSnapshot> build(String hostId, String runId) async {
    final repository = await ref.watch(
      mobileRunRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    final resources = await repository.resources(runId);
    final history = await repository.cleanups(runId);
    return RunResourcesSnapshot(resources: resources.items, history: history);
  }
}

/// Selection, preview and applied status of one cleanup. Nothing is removed
/// until [apply] runs with a reviewed preview.
class const RunCleanupDraft({
  final Map<String, bool> selected = const <String, bool>{},
  final RunCleanupPreview? preview,
  final RunCleanupStatus? status,
  final bool busy = false,
}) {
  /// Workspace ids chosen, each mapped to whether its branch goes too.
  bool isSelected(String workspaceId) => selected.containsKey(workspaceId);

  bool removesBranch(String workspaceId) => selected[workspaceId] ?? false;
}

@riverpod
class MobileRunCleanup extends _$MobileRunCleanup {
  static const Uuid _uuid = Uuid();

  @override
  RunCleanupDraft build(String hostId, String runId) => const RunCleanupDraft();

  void toggle(String workspaceId, {required bool selected}) {
    final next = <String, bool>{...state.selected};
    if (selected) {
      next[workspaceId] = false;
    } else {
      next.remove(workspaceId);
    }
    state = RunCleanupDraft(selected: next);
  }

  void setRemoveBranch(String workspaceId, {required bool remove}) {
    if (!state.isSelected(workspaceId)) return;
    state = RunCleanupDraft(
      selected: <String, bool>{...state.selected, workspaceId: remove},
    );
  }

  void selectAll(Iterable<RunResource> resources) => state = RunCleanupDraft(
    selected: <String, bool>{
      for (final resource in resources)
        if (resource.selectable)
          resource.workspaceId: state.removesBranch(resource.workspaceId),
    },
  );

  void clearSelection() => state = const RunCleanupDraft();

  /// Inspects the selection. Removes nothing.
  Future<void> preview() async {
    if (state.selected.isEmpty || state.busy) return;
    final selected = state.selected;
    state = RunCleanupDraft(selected: selected, busy: true);
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      final preview = await repository.previewCleanup(
        id: _uuid.v4(),
        runId: runId,
        resources: <RunCleanupSelection>[
          for (final entry in selected.entries)
            RunCleanupSelection(
              workspaceId: entry.key,
              removeBranch: entry.value,
            ),
        ],
      );
      if (ref.mounted) {
        state = RunCleanupDraft(selected: selected, preview: preview);
      }
    } finally {
      if (ref.mounted && state.busy) {
        state = RunCleanupDraft(selected: selected, preview: state.preview);
      }
    }
  }

  void backToResources() => state = RunCleanupDraft(selected: state.selected);

  /// Applies the reviewed preview. [confirmed] is the user's answer to the
  /// confirmation dialog; without it nothing is sent.
  Future<void> apply({required bool confirmed}) async {
    final preview = state.preview;
    if (!confirmed || preview == null || state.busy) return;
    final selected = state.selected;
    state = RunCleanupDraft(selected: selected, preview: preview, busy: true);
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      await repository.applyCleanup(preview);
      final status = await repository.cleanup(preview.id);
      if (ref.mounted) {
        state = RunCleanupDraft(preview: preview, status: status);
      }
    } finally {
      if (ref.mounted && state.busy) {
        state = RunCleanupDraft(selected: selected, preview: preview);
      }
    }
  }

  /// Retries a cleanup in attention, by the preview it was applied with.
  Future<void> retry(String cleanupId) => _resume(cleanupId, abandon: false);

  /// Gives up on a cleanup in attention and releases its resources.
  Future<void> abandon(String cleanupId) => _resume(cleanupId, abandon: true);

  Future<void> _resume(String cleanupId, {required bool abandon}) async {
    if (state.busy) return;
    final previous = state;
    state = RunCleanupDraft(
      selected: previous.selected,
      preview: previous.preview,
      status: previous.status,
      busy: true,
    );
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      final current = await repository.cleanup(cleanupId);
      if (abandon) {
        await repository.abandonCleanup(current.preview);
      } else {
        await repository.retryCleanup(current.preview);
      }
      final status = await repository.cleanup(cleanupId);
      if (ref.mounted) {
        state = RunCleanupDraft(preview: status.preview, status: status);
      }
    } finally {
      if (ref.mounted && state.busy) state = previous;
    }
  }
}
