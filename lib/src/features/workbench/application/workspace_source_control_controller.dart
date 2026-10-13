import 'dart:async';

import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/workbench/domain/source_control_changes.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_source_control_controller.g.dart';
part 'workspace_source_control_actions.dart';

class const WorkspaceSourceControlState({
  required final GitStatusResult status,
  required final GitRepositoryState repositoryState,
  required final List<GitStashEntry> stashes,
  final WorkspaceSourceControlAction? action,
  final int comparisonRevision = 0,
  final int catalogRevision = 0,
}) {
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
  checkout,
  createBranch,
}

@riverpod
class WorkspaceSourceControlController
    extends _$WorkspaceSourceControlController
    with _WorkspaceSourceControlActions {
  static const Duration _watcherReloadDebounce = Duration(milliseconds: 250);
  SourceControlWatcher? _watcher;
  StreamSubscription<native.SourceControlWatchSignal>? _watchSubscription;
  native.SourceControlWatcherHandle? _watcherHandle;
  Timer? _watcherReloadDebounceTimer;
  bool _watcherReloadInFlight = false;
  bool _initialLoadInFlight = false;
  bool _actionInFlight = false;
  Future<WorkspaceSourceControlState>? _initialRead;
  Future<WorkspaceSourceControlState>? _watcherRead;
  SourceControlChanges _pendingChanges = const SourceControlChanges();
  WorkspaceSourceControlState? _lastSnapshot;
  int _comparisonRevision = 0;
  int _catalogRevision = 0;
  int _operationGeneration = 0;
  int _buildGeneration = 0;
  int _viewCount = 0;
  int _watchGeneration = 0;
  bool _observing = false;
  AppForeground? _foreground;
  StreamSubscription<bool>? _foregroundSubscription;
  bool _disposed = false;

  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) {
    final previousRead = _watcherRead ?? _initialRead;
    final buildGeneration = ++_buildGeneration;
    _disposed = false;
    _watcher = ref.read(sourceControlWatcherProvider);
    ref.onDispose(_stopWatching);
    _initialLoadInFlight = true;
    if (_viewCount > 0) {
      _foreground = ref.read(appForegroundProvider);
      _foregroundSubscription = _foreground!.changes.listen(
        (_) => _syncObservation(),
      );
      _syncObservation();
    }
    _initialRead = previousRead == null
        ? _load()
        : previousRead
              .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
              .then((_) => _load());
    return _initialRead!
        .then((snapshot) {
          if (buildGeneration == _buildGeneration) _lastSnapshot = snapshot;
          return snapshot;
        })
        .whenComplete(() {
          if (buildGeneration != _buildGeneration) return;
          _initialLoadInFlight = false;
          _schedulePendingReload();
        });
  }

  Future<WorkspaceSourceControlState> _load({
    SourceControlChanges changes = SourceControlChanges.all,
  }) async {
    final previous = _lastSnapshot;
    final backend = ref.read(gitBackendProvider);
    final metadata = previous == null || changes.repository || changes.catalog;
    final results = await Future.wait<Object>([
      backend.status(workspacePath),
      metadata
          ? backend.repositoryState(workspacePath)
          : Future.value(previous.repositoryState),
      metadata
          ? backend.listStashes(workspacePath)
          : Future.value(previous.stashes),
    ]);
    return WorkspaceSourceControlState(
      status: results[0] as GitStatusResult,
      repositoryState: results[1] as GitRepositoryState,
      stashes: results[2] as List<GitStashEntry>,
      comparisonRevision: ++_comparisonRevision,
      catalogRevision: changes.catalog ? ++_catalogRevision : _catalogRevision,
    );
  }

  @override
  Future<void> _run(
    WorkspaceSourceControlAction action,
    Future<void> Function(GitBackend backend) operation,
  ) async {
    final previous = state.asData?.value;
    if (_actionInFlight || (previous?.isBusy ?? false)) return;
    _actionInFlight = true;
    if (previous != null) {
      state = AsyncData(
        WorkspaceSourceControlState(
          status: previous.status,
          repositoryState: previous.repositoryState,
          stashes: previous.stashes,
          action: action,
          comparisonRevision: previous.comparisonRevision,
          catalogRevision: previous.catalogRevision,
        ),
      );
    }
    _operationGeneration++;
    final keepAlive = ref.keepAlive();
    try {
      await _initialRead?.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      );
      await _watcherRead?.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      );
      await operation(ref.read(gitBackendProvider));
      final changes = switch (action) {
        WorkspaceSourceControlAction.stage ||
        WorkspaceSourceControlAction.unstage ||
        WorkspaceSourceControlAction.discard ||
        WorkspaceSourceControlAction.stash ||
        WorkspaceSourceControlAction.stashPop => SourceControlChanges.index,
        _ => SourceControlChanges.all,
      };
      final snapshot = await _load(changes: changes);
      _lastSnapshot = snapshot;
      state = AsyncData(snapshot);
    } catch (error, stackTrace) {
      final recovered = await _recoverAfterFailure(previous);
      if (recovered != null) {
        _lastSnapshot = recovered;
        state = AsyncData(recovered);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    } finally {
      _actionInFlight = false;
      keepAlive.close();
      _schedulePendingReload();
    }
  }

  /// Observation belongs to visible UI, never to a background Git operation.
  void attachView() {
    if (_disposed) return;
    _viewCount++;
    _foreground ??= ref.read(appForegroundProvider);
    _foregroundSubscription ??= _foreground!.changes.listen(
      (_) => _syncObservation(),
    );
    _syncObservation();
  }

  void detachView() {
    if (_viewCount > 0) _viewCount--;
    _syncObservation();
  }

  void _syncObservation() {
    final visible =
        !_disposed && _viewCount > 0 && (_foreground?.isForeground ?? false);
    if (visible == _observing) return;
    _observing = visible;
    final generation = ++_watchGeneration;
    if (visible) {
      unawaited(_startWatching(generation));
    } else {
      _parkWatcher();
    }
  }

  Future<void> _startWatching(int generation) async {
    final watcher = _watcher;
    if (watcher == null) return;
    try {
      final handle = await watcher.start(workspacePath: workspacePath);
      if (_disposed || !_observing || generation != _watchGeneration) {
        await watcher.stop(handle: handle);
        return;
      }
      _watcherHandle = handle;
      _watchSubscription = watcher.events(handle: handle).listen((signal) {
        if (!_observing || generation != _watchGeneration) return;
        _queueReload(
          SourceControlChanges(
            worktree: signal.worktreeChanged,
            repository: signal.repositoryChanged,
            catalog: signal.catalogChanged,
          ),
        );
      }, onError: (_) {});
      // Watch first, then catch changes made while this UI was parked.
      _queueReload(SourceControlChanges.all);
    } catch (_) {
      if (!_disposed && _observing && generation == _watchGeneration) {
        _queueReload(SourceControlChanges.all);
      }
    }
  }

  void _stopWatching() {
    _disposed = true;
    _observing = false;
    _watchGeneration++;
    unawaited(_foregroundSubscription?.cancel());
    _foregroundSubscription = null;
    _parkWatcher();
  }

  void _parkWatcher() {
    _pendingChanges = const SourceControlChanges();
    _watcherReloadDebounceTimer?.cancel();
    _watcherReloadDebounceTimer = null;
    unawaited(_watchSubscription?.cancel());
    _watchSubscription = null;
    final handle = _watcherHandle;
    _watcherHandle = null;
    if (handle != null && _watcher != null) {
      unawaited(_watcher!.stop(handle: handle));
    }
  }

  void _queueReload(SourceControlChanges changes) {
    if (_disposed || !_observing || !changes.any) return;
    _pendingChanges = _pendingChanges.merge(changes);
    _schedulePendingReload();
  }

  void _schedulePendingReload() {
    if (_disposed || !_observing || !_pendingChanges.any) return;
    _watcherReloadDebounceTimer?.cancel();
    _watcherReloadDebounceTimer = Timer(
      _watcherReloadDebounce,
      () => unawaited(_reloadFromWatcher()),
    );
  }

  Future<void> _reloadFromWatcher() async {
    _watcherReloadDebounceTimer = null;
    if (_disposed ||
        !_observing ||
        !_pendingChanges.any ||
        _initialLoadInFlight ||
        _actionInFlight ||
        _watcherReloadInFlight) {
      return;
    }
    if (state.value?.isBusy ?? false) return;
    final generation = _watchGeneration;
    final operation = _operationGeneration;
    final changes = _pendingChanges;
    _pendingChanges = const SourceControlChanges();
    _watcherReloadInFlight = true;
    try {
      _watcherRead = _load(changes: changes);
      final snapshot = await _watcherRead!;
      if (_disposed ||
          !_observing ||
          generation != _watchGeneration ||
          operation != _operationGeneration ||
          (state.value?.isBusy ?? false)) {
        return;
      }
      _lastSnapshot = snapshot;
      state = AsyncData(snapshot);
    } catch (_) {
      // Keep the last successful snapshot on background refresh failure.
    } finally {
      _watcherRead = null;
      _watcherReloadInFlight = false;
      _schedulePendingReload();
    }
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

  @override
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
