import 'dart:async';

import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_source_control_controller.g.dart';

class WorkspaceSourceControlState {
  const WorkspaceSourceControlState({
    required this.status,
    required this.repositoryState,
    required this.stashes,
    this.action,
  });

  final GitStatusResult status;
  final GitRepositoryState repositoryState;
  final List<GitStashEntry> stashes;
  final WorkspaceSourceControlAction? action;

  bool get isBusy => action != null;

  List<GitChangeEntry> get stagedEntries => status.entries
      .where((entry) => entry.area == GitChangeArea.staged)
      .toList(growable: false);

  bool get hasStagedChanges => stagedEntries.isNotEmpty;

  bool get hasStageableChanges =>
      status.entries.any((entry) => entry.canStageFromParent);

  bool get hasDiscardableChanges =>
      status.entries.any((entry) => entry.canDiscardFromParent);

  bool get hasChanges => status.entries.isNotEmpty;

  bool get hasUnstagedOrUntrackedChanges => status.entries.any(
    (entry) =>
        entry.area == GitChangeArea.unstaged ||
        entry.area == GitChangeArea.untracked,
  );

  bool get hasStashableChanges => status.entries.any(
    (entry) =>
        entry.area == GitChangeArea.staged ||
        (entry.area == GitChangeArea.unstaged &&
            !entry.isSubmoduleWorktreeOnly),
  );
}

enum WorkspaceSourceControlAction {
  refresh,
  stage,
  unstage,
  discard,
  commit,
  commitPush,
  commitSync,
  amend,
  fetch,
  pull,
  push,
  sync,
  stash,
  stashPop,
}

@riverpod
class WorkspaceSourceControlController
    extends _$WorkspaceSourceControlController {
  static const Duration _watcherReloadDebounce = Duration(milliseconds: 250);

  SourceControlWatcher? _watcher;
  StreamSubscription<native.SourceControlWatchSignal>? _watchSubscription;
  native.SourceControlWatcherHandle? _watcherHandle;
  Timer? _watcherReloadDebounceTimer;
  bool _watcherReloadInFlight = false;
  bool _watcherReloadQueued = false;
  bool _disposed = false;

  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) {
    // Capture the watcher now: `onDispose` runs in a lifecycle where reading
    // providers via `ref` is disallowed.
    _watcher = ref.read(sourceControlWatcherProvider);
    ref.onDispose(_stopWatching);
    // Best-effort: file watching keeps the panel live without blocking the
    // initial load; manual refresh remains available if it fails to start.
    unawaited(_startWatching());
    return _load();
  }

  Future<void> refresh() =>
      _run(WorkspaceSourceControlAction.refresh, (_) async {});

  Future<void> stage(String? filePath) => _run(
    WorkspaceSourceControlAction.stage,
    (backend) => backend.stage(path: workspacePath, filePath: filePath),
  );

  Future<void> stageArea(GitChangeArea area, {String? filePath}) => _run(
    WorkspaceSourceControlAction.stage,
    (backend) =>
        backend.stageArea(path: workspacePath, area: area, filePath: filePath),
  );

  Future<void> stageEntry(GitChangeEntry entry) {
    if (!entry.canStageFromParent) {
      return Future<void>.value();
    }
    return _run(WorkspaceSourceControlAction.stage, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.stage(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> unstage(String? filePath) => _run(
    WorkspaceSourceControlAction.unstage,
    (backend) => backend.unstage(path: workspacePath, filePath: filePath),
  );

  Future<void> unstageArea(GitChangeArea area, {String? filePath}) => _run(
    WorkspaceSourceControlAction.unstage,
    (backend) => backend.unstageArea(
      path: workspacePath,
      area: area,
      filePath: filePath,
    ),
  );

  Future<void> unstageEntry(GitChangeEntry entry) {
    if (!entry.canUnstageFromParent) {
      return Future<void>.value();
    }
    return _run(WorkspaceSourceControlAction.unstage, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.unstage(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> discard(String? filePath) => _run(
    WorkspaceSourceControlAction.discard,
    (backend) => backend.discard(path: workspacePath, filePath: filePath),
  );

  Future<void> discardArea(GitChangeArea area, {String? filePath}) => _run(
    WorkspaceSourceControlAction.discard,
    (backend) => backend.discardArea(
      path: workspacePath,
      area: area,
      filePath: filePath,
    ),
  );

  Future<void> discardEntry(GitChangeEntry entry) {
    if (!entry.canDiscardFromParent) {
      return Future<void>.value();
    }
    return _run(WorkspaceSourceControlAction.discard, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.discard(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> commit(String message) => _run(
    WorkspaceSourceControlAction.commit,
    (backend) => backend.commit(path: workspacePath, message: message.trim()),
  );

  Future<void> commitAndPush(String message) =>
      _run(WorkspaceSourceControlAction.commitPush, (backend) async {
        await backend.commit(path: workspacePath, message: message.trim());
        await backend.push(workspacePath);
      });

  Future<void> commitAndSync(String message) =>
      _run(WorkspaceSourceControlAction.commitSync, (backend) async {
        await backend.commit(path: workspacePath, message: message.trim());
        if (!(state.asData?.value.repositoryState.hasUpstream ?? false)) {
          throw const NoUpstreamException('set an upstream before syncing');
        }
        await backend.pull(workspacePath);
        await backend.push(workspacePath);
      });

  Future<void> amendCommit(String message) => _run(
    WorkspaceSourceControlAction.amend,
    (backend) =>
        backend.amendCommit(path: workspacePath, message: message.trim()),
  );

  Future<void> fetch() => _run(
    WorkspaceSourceControlAction.fetch,
    (backend) => backend.fetch(workspacePath),
  );

  Future<void> pull() => _run(
    WorkspaceSourceControlAction.pull,
    (backend) => backend.pull(workspacePath),
  );

  Future<void> push() => _run(
    WorkspaceSourceControlAction.push,
    (backend) => backend.push(workspacePath),
  );

  Future<void> sync() =>
      _run(WorkspaceSourceControlAction.sync, (backend) async {
        if (!(state.asData?.value.repositoryState.hasUpstream ?? false)) {
          throw const NoUpstreamException('set an upstream before syncing');
        }
        await backend.pull(workspacePath);
        await backend.push(workspacePath);
      });

  Future<void> stash() => _run(
    WorkspaceSourceControlAction.stash,
    (backend) => backend.stash(workspacePath),
  );

  Future<void> stashPop(int stashIndex) => _run(
    WorkspaceSourceControlAction.stashPop,
    (backend) => backend.stashPop(path: workspacePath, stashIndex: stashIndex),
  );

  Future<WorkspaceSourceControlState> _load() async {
    final backend = ref.read(gitBackendProvider);
    final results = await Future.wait<Object>([
      backend.status(workspacePath),
      backend.repositoryState(workspacePath),
      backend.listStashes(workspacePath),
    ]);
    return WorkspaceSourceControlState(
      status: results[0] as GitStatusResult,
      repositoryState: results[1] as GitRepositoryState,
      stashes: results[2] as List<GitStashEntry>,
    );
  }

  Future<void> _run(
    WorkspaceSourceControlAction action,
    Future<void> Function(GitBackend backend) operation,
  ) async {
    final previous = state.asData?.value;
    if (previous?.isBusy ?? false) {
      return;
    }
    if (previous != null) {
      state = AsyncData(
        WorkspaceSourceControlState(
          status: previous.status,
          repositoryState: previous.repositoryState,
          stashes: previous.stashes,
          action: action,
        ),
      );
    }
    try {
      await operation(ref.read(gitBackendProvider));
      state = AsyncData(await _load());
    } catch (error, stackTrace) {
      final recovered = await _recoverAfterFailure(previous);
      if (recovered != null) {
        state = AsyncData(recovered);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    } finally {
      _scheduleQueuedWatcherReload();
    }
  }

  Future<void> _startWatching() async {
    final watcher = _watcher;
    if (watcher == null) {
      return;
    }
    try {
      final handle = await watcher.start(workspacePath: workspacePath);
      if (_disposed) {
        await watcher.stop(handle: handle);
        return;
      }
      _watcherHandle = handle;
      _watchSubscription = watcher
          .events(handle: handle)
          .listen((_) => _scheduleWatcherReload(), onError: (_) {});
    } catch (_) {
      // File watching is best-effort; explicit refresh still works.
    }
  }

  void _stopWatching() {
    _disposed = true;
    _watcherReloadQueued = false;
    _watcherReloadDebounceTimer?.cancel();
    _watcherReloadDebounceTimer = null;
    final subscription = _watchSubscription;
    _watchSubscription = null;
    unawaited(subscription?.cancel());
    final handle = _watcherHandle;
    _watcherHandle = null;
    final watcher = _watcher;
    if (handle != null && watcher != null) {
      unawaited(watcher.stop(handle: handle));
    }
  }

  void _scheduleWatcherReload() {
    _watcherReloadDebounceTimer?.cancel();
    _watcherReloadDebounceTimer = Timer(
      _watcherReloadDebounce,
      () => unawaited(_reloadFromWatcher()),
    );
  }

  Future<void> _reloadFromWatcher() async {
    if (_disposed) {
      return;
    }
    if (_watcherReloadInFlight) {
      _watcherReloadQueued = true;
      return;
    }
    // Defer while an action runs: `_run` reloads when it finishes, and skipping
    // here avoids clobbering its optimistic busy state.
    if (state.asData?.value.isBusy ?? false) {
      _watcherReloadQueued = true;
      return;
    }
    _watcherReloadInFlight = true;
    try {
      final next = await _load();
      if (_disposed || (state.asData?.value.isBusy ?? false)) {
        return;
      }
      state = AsyncData(next);
    } catch (_) {
      // Best-effort background refresh: keep the current state on failure.
    } finally {
      _watcherReloadInFlight = false;
      _scheduleQueuedWatcherReload();
    }
  }

  void _scheduleQueuedWatcherReload() {
    if (_disposed || !_watcherReloadQueued) {
      return;
    }
    _watcherReloadQueued = false;
    _scheduleWatcherReload();
  }

  Future<WorkspaceSourceControlState?> _recoverAfterFailure(
    WorkspaceSourceControlState? previous,
  ) async {
    try {
      return await _load();
    } catch (_) {
      return previous;
    }
  }

  List<String> _actionPaths(GitChangeEntry entry) {
    final paths = <String>[];
    final oldPath = entry.oldPath;
    if (entry.status == GitChangeStatus.renamed &&
        oldPath != null &&
        oldPath != entry.path) {
      paths.add(oldPath);
    }
    paths.add(entry.path);
    return paths;
  }
}
