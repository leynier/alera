part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceSleep
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  StreamSubscription<Map<String, List<String>>>? _sleptTabsSub;

  /// Sleeps from elsewhere this client already settled. The host ends a
  /// sleep's sessions one at a time, and only the first removal may close the
  /// workspace: the user can reopen it before the last one arrives. A host
  /// that names each sleep is tracked by that id; an older one by workspace
  /// until its snapshot stops listing the workspace.
  final Set<String> _settledSleepIds = <String>{};
  final Set<String> _settledRemoteSleeps = <String>{};
  final Map<String, int> _remoteSleepSettlements = <String, int>{};

  /// Exited handles kept because their workspace was on screen, released once
  /// it is not so the next open starts them again.
  final Map<String, Set<String>> _retainedExitedHandles =
      <String, Set<String>>{};

  /// Follows the host's slept terminals so a sleep or wake from any client,
  /// including a paired phone, reaches the sidebar.
  void _startSleptTabs() {
    final repository = _repository;
    if (repository is! WorkspaceSleepRepository) {
      state = state.copyWith(sleepSnapshotReady: true);
      return;
    }
    _sleptTabsSub = (repository as WorkspaceSleepRepository)
        .watchSleptWorkspaceTabs()
        .listen((slept) {
          if (_disposed) return;
          // A workspace the host no longer lists has woken.
          _settledRemoteSleeps.removeWhere((id) => !slept.containsKey(id));
          state = state.copyWith(
            sleepSnapshotReady: true,
            sleptTabIdsByWorkspaceId: slept,
          );
        });
  }

  /// Sleeps a workspace: live terminal sessions stop, but tab records, layout,
  /// branch, and files are preserved so agent sessions resume on wake through
  /// their stored native session ids.
  Future<void> sleepWorkspace(Workspace workspace) async {
    try {
      final settlementsBefore = _remoteSleepSettlements[workspace.id] ?? 0;
      await _repository.sleepWorkspace(workspace.id);
      // The host's removals, which arrive before its answer, already settled
      // this sleep, and the user may have reopened the workspace since.
      if ((_remoteSleepSettlements[workspace.id] ?? 0) != settlementsBefore) {
        return;
      }
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      _settleSleptWorkspace(workspace.id, <String>[
        for (final tab in state.tabsFor(workspace.id))
          if (tab.kind == WorkspaceTabKind.terminal) tab.id,
      ], clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  /// The terminals of [workspaceId] the host stopped by sleeping it.
  Future<List<String>> sleptTerminalIds(String workspaceId) async {
    final repository = _repository;
    if (repository is! WorkspaceSleepRepository) {
      return const <String>[];
    }
    final slept = await (repository as WorkspaceSleepRepository)
        .listSleptWorkspaceTabs();
    return slept[workspaceId] ?? const <String>[];
  }

  /// Applies a sleep that the host already carried out for [tabId], possibly
  /// for another client or the CLI: the session is gone, so its handle is
  /// released rather than terminated, and the tab record stays for the wake.
  /// [sleptTabIds] is the host's list, which leaves out terminals opened after
  /// the sleep.
  void settleSleptTerminal(
    String workspaceId,
    String tabId,
    List<String> sleptTabIds, {
    String? sleepId,
  }) {
    if (_disposed) return;
    _remoteSleepSettlements.update(
      workspaceId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _settleSleptWorkspace(
      workspaceId,
      sleptTabIds,
      clearError: false,
      deselect: sleepId != null
          ? _settledSleepIds.add(sleepId)
          : _settledRemoteSleeps.add(workspaceId),
    );
    // A workspace still on screen keeps the exited handle: releasing it would
    // leave its mounted surface on disposed objects.
    if (state.activeWorkspaceId == workspaceId) {
      retainExitedHandle(workspaceId, tabId);
    } else {
      ref.read(terminalRuntimeProvider).releaseTab(tabId);
    }
  }

  void retainExitedHandle(String workspaceId, String tabId) {
    (_retainedExitedHandles[workspaceId] ??= <String>{}).add(tabId);
  }

  /// Called once [workspaceId] is no longer on screen.
  void releaseRetainedExitedHandles(String workspaceId) {
    final tabIds = _retainedExitedHandles.remove(workspaceId);
    if (tabIds == null || _disposed) return;
    final runtime = ref.read(terminalRuntimeProvider);
    for (final tabId in tabIds) {
      final handle = runtime.peekSession(tabId);
      // A terminal the user restarted meanwhile is live again.
      if (handle != null && !handle.isRunning && !handle.isStarting) {
        runtime.releaseTab(tabId);
      }
    }
  }

  void _settleSleptWorkspace(
    String workspaceId,
    List<String> sleptTabIds, {
    required bool clearError,
    bool deselect = true,
  }) {
    // Showing a slept workspace would start its terminals again and wake it.
    final wasActive = deselect && state.activeWorkspaceId == workspaceId;
    final prefs = state.viewPrefs;
    var nextPrefs = prefs;
    if (prefs.rightSidebarWidthByWorkspaceId.containsKey(workspaceId)) {
      nextPrefs = prefs.copyWith(
        rightSidebarWidthByWorkspaceId: Map<String, double>.from(
          prefs.rightSidebarWidthByWorkspaceId,
        )..remove(workspaceId),
      );
    }
    state = state.copyWith(
      activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
      viewPrefs: nextPrefs,
      // The host records the same list; setting it here keeps the row from
      // showing running terminals until that snapshot arrives.
      sleptTabIdsByWorkspaceId: sleptTabIds.isEmpty
          ? state.sleptTabIdsByWorkspaceId
          : <String, List<String>>{
              ...state.sleptTabIdsByWorkspaceId,
              workspaceId: sleptTabIds,
            },
      error: clearError ? null : state.error,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    _pruneExplorerSessions();
  }
}
