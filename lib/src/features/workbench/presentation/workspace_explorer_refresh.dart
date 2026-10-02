part of 'workspace_explorer.dart';

extension _WorkspaceExplorerRefresh on _WorkspaceExplorerState {
  Future<void> _reloadRoot({
    bool restoreSession = false,
    int? generation,
  }) async {
    final operationGeneration = generation ?? _explorerGeneration;
    if (!_isCurrentExplorerGeneration(operationGeneration)) {
      return;
    }
    _setLoading(true);
    try {
      _resetExplorerProjection();
      await _refreshGitStatusSnapshot(generation: operationGeneration);
      await _syncWatchedDirectories(generation: operationGeneration);
      await _loadDirectory('', generation: operationGeneration);
      if (!_isCurrentExplorerGeneration(operationGeneration)) {
        return;
      }
      _rebuildTree();
      if (restoreSession) {
        await _restoreSession(generation: operationGeneration);
      }
    } catch (error) {
      if (_isCurrentExplorerGeneration(operationGeneration)) {
        _rebuildTree(tryPreserveState: false);
        _showError(error);
      }
    } finally {
      if (_isCurrentExplorerGeneration(operationGeneration)) {
        _sessionReady = true;
        _setLoading(false);
      }
    }
  }

  Future<void> _reloadForModeChange({required int generation}) async {
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    final loadedDirectories =
        _childrenByDirectory.keys
            .where((relativePath) => relativePath.isNotEmpty)
            .toList(growable: false)
          ..sort(_compareDirectoryDepth);
    _setLoading(true);
    try {
      _resetExplorerProjection();
      await _refreshGitStatusSnapshot(generation: generation);
      await _syncWatchedDirectories(generation: generation);
      await _loadDirectory('', generation: generation);
      for (final relativePath in loadedDirectories) {
        if (!_isCurrentExplorerGeneration(generation)) {
          return;
        }
        if (!_isDirectoryEntry(_entryByPath[relativePath])) {
          continue;
        }
        await _loadDirectory(relativePath, generation: generation);
      }
      if (!_isCurrentExplorerGeneration(generation)) {
        return;
      }
      _rebuildTree();
    } catch (error) {
      if (_isCurrentExplorerGeneration(generation)) {
        _rebuildTree(tryPreserveState: false);
        _showError(error);
      }
    } finally {
      if (_isCurrentExplorerGeneration(generation)) {
        _setLoading(false);
      }
    }
  }

  void _listenForRevealRequest() {
    ref.listen<WorkspaceExplorerRevealRequest?>(
      workspaceExplorerRevealControllerProvider,
      (previous, next) {
        if (next == null || next.workspaceId != widget.workspace.id) {
          return;
        }
        unawaited(_revealPendingPath(relativePath: next.relativePath));
      },
    );
  }

  Future<void> _bootstrapExplorer({required int generation}) async {
    await _startNativeWatcher(generation: generation);
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    await _reloadRoot(restoreSession: true, generation: generation);
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    await _revealPendingPath(generation: generation);
  }

  Future<void> _restoreSession({required int generation}) async {
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    final session = _sessionStore.peek(widget.workspace.id);
    if (session == null) {
      _sessionReady = true;
      return;
    }
    final paths =
        session.expandedRelativePaths
            .where((relativePath) => relativePath.isNotEmpty)
            .toList(growable: false)
          ..sort(_compareDirectoryDepth);
    for (final relativePath in paths) {
      if (!_isCurrentExplorerGeneration(generation)) {
        return;
      }
      try {
        await _ensureAncestorsLoaded(relativePath, generation: generation);
        if (!_isCurrentExplorerGeneration(generation)) {
          return;
        }
        if (_isDirectoryEntry(_entryByPath[relativePath]) &&
            !_childrenByDirectory.containsKey(relativePath)) {
          await _loadDirectory(relativePath, generation: generation);
        }
      } catch (_) {
        continue;
      }
    }
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    _rebuildTree();
    _controller.expansions.performBatch(() {
      _controller.expansions.setExpanded(_WorkspaceExplorerState._rootId, true);
      for (final relativePath in paths) {
        final nodeId = _nodeIdForRelativePath(relativePath);
        if (nodeId != null) {
          _controller.expansions.setExpanded(nodeId, true);
        }
      }
    });
    _restoreScroll(session.scrollOffset);
    _sessionReady = true;
  }

  Future<void> _restartExplorer({required int generation}) async {
    await _stopNativeWatcher();
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    await _bootstrapExplorer(generation: generation);
  }

  Future<void> _replaceDirectoryChildren(
    String relativePath,
    List<native.WorkspaceFileEntry> children, {
    int? generation,
  }) {
    final operationGeneration = generation ?? _explorerGeneration;
    if (!_isCurrentExplorerGeneration(operationGeneration)) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    final pending = _pendingDirectoryReplacements[relativePath];
    if (pending != null && pending.generation == operationGeneration) {
      pending.children = children;
      pending.waiters.add(waiter);
    } else {
      pending?.complete();
      _pendingDirectoryReplacements[relativePath] =
          _PendingExplorerDirectoryReplacement(
            generation: operationGeneration,
            children: children,
            waiters: <Completer<void>>[waiter],
          );
    }
    if (!_directoryReplacementRunning) {
      _directoryReplacementRunning = true;
      unawaited(_drainDirectoryReplacementQueue());
    }
    return waiter.future;
  }

  Future<void> _drainDirectoryReplacementQueue() async {
    try {
      while (_pendingDirectoryReplacements.isNotEmpty) {
        final relativePath = _pendingDirectoryReplacements.keys.first;
        final pending = _pendingDirectoryReplacements.remove(relativePath)!;
        final projectionRequestId = ++_projectionRequestId;
        try {
          if (!_isCurrentExplorerGeneration(pending.generation)) {
            pending.complete();
            continue;
          }
          final projection = await _workspaceFiles.projectExplorerTree(
            workspaceName: widget.workspace.name,
            workspacePath: widget.workspace.path,
            directories: _directorySnapshots(),
            replacement: native.WorkspaceExplorerDirectoryChildren(
              relativePath: relativePath,
              children: pending.children,
            ),
          );
          if (_isCurrentExplorerGeneration(pending.generation) &&
              projectionRequestId == _projectionRequestId) {
            _applyProjection(projection);
            unawaited(_syncWatchedDirectories(generation: pending.generation));
          }
          pending.complete();
        } catch (error, stackTrace) {
          pending.completeError(error, stackTrace);
        }
      }
    } finally {
      _directoryReplacementRunning = false;
      if (_pendingDirectoryReplacements.isNotEmpty && mounted) {
        _directoryReplacementRunning = true;
        unawaited(_drainDirectoryReplacementQueue());
      }
    }
  }

  void _resetPendingDirectoryReplacements() {
    for (final pending in _pendingDirectoryReplacements.values) {
      pending.complete();
    }
    _pendingDirectoryReplacements.clear();
  }

  void _resetPendingWatcherUpdate() {
    _watcherUpdateRequestId += 1;
    _pendingWatcherUpdate?.complete();
    _pendingWatcherUpdate = null;
  }

  void _resetExplorerProjection() {
    _projectionRequestId += 1;
    _resetPendingDirectoryReplacements();
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

  Future<void> _startNativeWatcher({required int generation}) async {
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    if (widget.workspace.isRemote) {
      return;
    }
    try {
      final handle = await _workspaceFiles.startExplorerWatcher(
        workspacePath: widget.workspace.path,
      );
      if (!_isCurrentExplorerGeneration(generation)) {
        await _workspaceFiles.stopExplorerWatcher(handle: handle);
        return;
      }
      _watcherHandle = handle;
      _watchSubscription = _workspaceFiles
          .watchExplorerEvents(handle: handle)
          .listen(
            (batch) => _scheduleWatchedRefresh(batch, generation: generation),
            onError: (_) {},
          );
      await _syncWatchedDirectories(generation: generation);
    } catch (_) {
      // File watching is best-effort; manual refresh remains available.
    }
  }

  Future<void> _stopNativeWatcher() async {
    _resetPendingWatcherUpdate();
    final subscription = _watchSubscription;
    final handle = _watcherHandle;
    _watchSubscription = null;
    _watcherHandle = null;
    try {
      if (handle != null) {
        await _workspaceFiles.stopExplorerWatcher(handle: handle);
      }
    } finally {
      if (subscription != null) {
        // The FRB stream is released by the native watcher. Do not await Dart
        // cancellation here because it can remain pending until that release.
        unawaited(subscription.cancel().catchError((_) {}));
      }
    }
  }

  Future<void> _syncWatchedDirectories({int? generation}) {
    final operationGeneration = generation ?? _explorerGeneration;
    if (!_isCurrentExplorerGeneration(operationGeneration)) {
      return Future<void>.value();
    }
    final handle = _watcherHandle;
    if (handle == null) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    final watchedRelativePaths = _childrenByDirectory.keys.toList(
      growable: false,
    );
    final pending = _pendingWatcherUpdate;
    if (pending != null &&
        pending.generation == operationGeneration &&
        pending.handle == handle) {
      pending.watchedRelativePaths = watchedRelativePaths;
      pending.waiters.add(waiter);
    } else {
      pending?.complete();
      _pendingWatcherUpdate = _PendingExplorerWatcherUpdate(
        generation: operationGeneration,
        handle: handle,
        watchedRelativePaths: watchedRelativePaths,
        waiters: <Completer<void>>[waiter],
      );
    }
    if (!_watcherUpdateRunning) {
      _watcherUpdateRunning = true;
      unawaited(_drainWatcherUpdateQueue());
    }
    return waiter.future;
  }

  Future<void> _drainWatcherUpdateQueue() async {
    try {
      while (_pendingWatcherUpdate != null) {
        final pending = _pendingWatcherUpdate!;
        _pendingWatcherUpdate = null;
        final requestId = ++_watcherUpdateRequestId;
        try {
          if (_isCurrentExplorerGeneration(pending.generation) &&
              requestId == _watcherUpdateRequestId &&
              pending.handle == _watcherHandle) {
            await _workspaceFiles.updateExplorerWatcher(
              handle: pending.handle,
              watchedRelativePaths: pending.watchedRelativePaths,
            );
          }
        } catch (_) {
          // File watching is best-effort; explicit refresh still works.
        } finally {
          pending.complete();
        }
      }
    } finally {
      _watcherUpdateRunning = false;
      if (_pendingWatcherUpdate != null && mounted) {
        _watcherUpdateRunning = true;
        unawaited(_drainWatcherUpdateQueue());
      }
    }
  }

  void _scheduleWatchedRefresh(
    native.WorkspaceExplorerWatchBatch batch, {
    required int generation,
  }) {
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    final pending = _pendingWatchedRefreshPaths ?? <String>{};
    pending.addAll(batch.directoryRelativePaths);
    _pendingWatchedRefreshPaths = pending;
    if (_watchedRefreshRunning) {
      return;
    }
    _watchedRefreshRunning = true;
    unawaited(_drainWatchedRefreshQueue());
  }

  Future<void> _drainWatchedRefreshQueue() async {
    try {
      while (_isCurrentExplorerGeneration(_explorerGeneration)) {
        final relativePaths = _pendingWatchedRefreshPaths;
        if (relativePaths == null) {
          return;
        }
        _pendingWatchedRefreshPaths = null;
        final generation = _explorerGeneration;
        await _refreshWatchedDirectories(relativePaths, generation: generation);
      }
    } catch (_) {
      // File watching is best-effort; explicit refresh still works.
    } finally {
      _watchedRefreshRunning = false;
      if (_pendingWatchedRefreshPaths != null && mounted) {
        _watchedRefreshRunning = true;
        unawaited(_drainWatchedRefreshQueue());
      }
    }
  }

  Future<void> _refreshWatchedDirectories(
    Set<String> relativePaths, {
    required int generation,
  }) async {
    if (!_isCurrentExplorerGeneration(generation)) {
      return;
    }
    await _refreshGitStatusSnapshot(generation: generation);
    for (final relativePath in relativePaths) {
      if (!_isCurrentExplorerGeneration(generation) ||
          !_childrenByDirectory.containsKey(relativePath)) {
        continue;
      }
      await _refreshDirectory(
        relativePath,
        refreshGitStatus: false,
        generation: generation,
      );
    }
  }

  bool _isCurrentExplorerGeneration(int generation) {
    return mounted && generation == _explorerGeneration;
  }
}
