part of 'workspace_explorer.dart';

extension _WorkspaceExplorerRefresh on _WorkspaceExplorerState {
  Future<void> _bootstrapExplorer() async {
    await _startNativeWatcher();
    if (!mounted) {
      return;
    }
    await _reloadRoot();
  }

  Future<void> _restartExplorer() async {
    unawaited(_stopNativeWatcher());
    if (!mounted) {
      return;
    }
    await _bootstrapExplorer();
  }

  Future<void> _replaceDirectoryChildren(
    String relativePath,
    List<native.WorkspaceFileEntry> children,
  ) async {
    final projection = await _workspaceFiles.projectExplorerTree(
      workspaceName: widget.workspace.name,
      workspacePath: widget.workspace.path,
      directories: _directorySnapshots(),
      replacement: native.WorkspaceExplorerDirectoryChildren(
        relativePath: relativePath,
        children: children,
      ),
    );
    if (!mounted) {
      return;
    }
    _applyProjection(projection);
    await _syncWatchedDirectories();
  }

  void _resetExplorerProjection() {
    _projection = null;
    _childrenByDirectory.clear();
    _entryByPath.clear();
    _entryByNodeId.clear();
  }

  void _applyProjection(native.WorkspaceExplorerTreeProjection projection) {
    _projection = projection;
    _childrenByDirectory
      ..clear()
      ..addEntries(
        projection.directories.map(
          (directory) => MapEntry(directory.relativePath, directory.children),
        ),
      );
    _entryByPath
      ..clear()
      ..addEntries(
        projection.directories.expand(
          (directory) => directory.children.map(
            (entry) => MapEntry(entry.relativePath, entry),
          ),
        ),
      );
    _entryByNodeId.clear();
    for (final binding in projection.entryBindings) {
      final entry = _entryByPath[binding.relativePath];
      if (entry != null) {
        _entryByNodeId[binding.nodeId] = entry;
      }
    }
  }

  List<native.WorkspaceExplorerDirectoryChildren> _directorySnapshots() {
    return _childrenByDirectory.entries
        .map(
          (entry) => native.WorkspaceExplorerDirectoryChildren(
            relativePath: entry.key,
            children: entry.value,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _startNativeWatcher() async {
    try {
      final handle = await _workspaceFiles.startExplorerWatcher(
        workspacePath: widget.workspace.path,
      );
      if (!mounted) {
        await _workspaceFiles.stopExplorerWatcher(handle: handle);
        return;
      }
      _watcherHandle = handle;
      _watchSubscription = _workspaceFiles
          .watchExplorerEvents(handle: handle)
          .listen(_scheduleWatchedRefresh, onError: (_) {});
      await _syncWatchedDirectories();
    } catch (_) {
      // File watching is best-effort; manual refresh remains available.
    }
  }

  Future<void> _stopNativeWatcher() async {
    final subscription = _watchSubscription;
    final handle = _watcherHandle;
    _watchSubscription = null;
    _watcherHandle = null;
    await subscription?.cancel();
    if (handle != null) {
      await _workspaceFiles.stopExplorerWatcher(handle: handle);
    }
  }

  Future<void> _syncWatchedDirectories() async {
    final handle = _watcherHandle;
    if (handle == null) {
      return;
    }
    try {
      await _workspaceFiles.updateExplorerWatcher(
        handle: handle,
        watchedRelativePaths: _childrenByDirectory.keys.toList(growable: false),
      );
    } catch (_) {
      // File watching is best-effort; explicit refresh still works.
    }
  }

  void _scheduleWatchedRefresh(native.WorkspaceExplorerWatchBatch batch) {
    _watchRefreshQueue = _watchRefreshQueue
        .then((_) => _refreshWatchedDirectories(batch.directoryRelativePaths))
        .catchError((_) {});
  }

  Future<void> _refreshWatchedDirectories(List<String> relativePaths) async {
    await _refreshGitStatusSnapshot();
    for (final relativePath in relativePaths.toSet()) {
      if (!mounted || !_childrenByDirectory.containsKey(relativePath)) {
        continue;
      }
      await _refreshDirectory(relativePath, refreshGitStatus: false);
    }
  }
}
