part of 'workbench_controller.dart';

/// Tag and parent edits throw rather than store the failure in `state.error`:
/// their dialogs and menus report it with context, and storing it too would
/// toast it twice.
mixin _WorkbenchControllerProjectSelection
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening,
        _WorkbenchControllerProjects,
        _WorkbenchControllerInternalLayout {
  Future<List<WorkspaceTag>> listWorkspaceTags() async {
    final tags = await _workspaceGraphRepository.listTags();
    state = state.copyWith(error: null);
    return tags;
  }

  Future<List<WorkspaceRelation>> listWorkspaceRelations() async {
    final relations = await _workspaceGraphRepository.listRelations();
    state = state.copyWith(error: null);
    return relations;
  }

  Future<WorkspaceTag> createWorkspaceTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw WorkspaceException('Tag name is required.');
    }
    // Tag names are unique case-insensitively in the runtime store, so a
    // duplicate name reuses the existing tag instead of minting a new id.
    final lowered = trimmed.toLowerCase();
    final existing = (await _workspaceGraphRepository.listTags())
        .where((tag) => tag.name.toLowerCase() == lowered)
        .firstOrNull;
    if (existing != null) {
      state = state.copyWith(error: null);
      return existing;
    }
    final tag = await _workspaceGraphRepository.upsertTag(
      .create(name: trimmed),
    );
    state = state.copyWith(error: null);
    return tag;
  }

  Future<void> deleteWorkspaceTag(String tagId) async {
    await _workspaceGraphRepository.removeTag(tagId);
    state = state.copyWith(error: null);
  }

  Future<void> updateWorkspaceTags({
    required Workspace workspace,
    required Set<String> tagIds,
  }) async {
    // Diff against the freshest known membership: the workspace snapshot may
    // predate tag changes applied while the dialog was open.
    final latest = state
        .workspacesFor(workspace.projectId)
        .where((candidate) => candidate.id == workspace.id)
        .firstOrNull;
    final current = (latest ?? workspace).tagIds.toSet();
    final next = tagIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final tagId in current.difference(next)) {
      await _workspaceGraphRepository.unassignTag(
        workspaceId: workspace.id,
        tagId: tagId,
      );
    }
    for (final tagId in next.difference(current)) {
      await _workspaceGraphRepository.assignTag(
        workspaceId: workspace.id,
        tagId: tagId,
      );
    }
    state = state.copyWith(error: null);
  }

  Future<void> setWorkspaceParent({
    required Workspace workspace,
    String? parentWorkspaceId,
  }) async {
    final currentParentId = workspace.parentWorkspaceId?.trim();
    final nextParentId = parentWorkspaceId?.trim();
    if ((currentParentId == null || currentParentId.isEmpty) &&
        (nextParentId == null || nextParentId.isEmpty)) {
      return;
    }
    if (currentParentId == nextParentId) {
      return;
    }
    var removedCurrentParent = false;
    if (nextParentId != null && nextParentId.isNotEmpty) {
      // The dialog disables descendant options, but its relations snapshot
      // can be stale; re-validate against fresh relations before linking.
      if (nextParentId == workspace.id) {
        throw WorkspaceException('A workspace cannot be its own parent');
      }
      final relations = await _workspaceGraphRepository.listRelations();
      if (workspaceDescendantIds(
        workspace.id,
        relations,
      ).contains(nextParentId)) {
        throw WorkspaceException('Cannot set a descendant workspace as parent');
      }
    }
    if (currentParentId != null && currentParentId.isNotEmpty) {
      await _workspaceGraphRepository.unlinkWorkspaces(
        parentWorkspaceId: currentParentId,
        childWorkspaceId: workspace.id,
      );
      removedCurrentParent = true;
    }
    if (nextParentId != null && nextParentId.isNotEmpty) {
      try {
        await _workspaceGraphRepository.linkWorkspaces(
          parentWorkspaceId: nextParentId,
          childWorkspaceId: workspace.id,
        );
      } catch (error) {
        if (removedCurrentParent &&
            currentParentId != null &&
            currentParentId.isNotEmpty) {
          try {
            await _workspaceGraphRepository.linkWorkspaces(
              parentWorkspaceId: currentParentId,
              childWorkspaceId: workspace.id,
            );
          } catch (restoreError) {
            throw WorkspaceException(
              'Workspace parent update failed: '
              '${userFacingErrorMessage(error)} '
              'Previous parent restore failed: '
              '${userFacingErrorMessage(restoreError)}',
            );
          }
        }
        rethrow;
      }
    }
    state = state.copyWith(error: null);
  }

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) {
    return _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
    );
  }

  Future<void> _selectWorkspace({
    required Project project,
    required Workspace workspace,
    required bool ensureInitialTerminal,
    bool recordHistory = true,
  }) async {
    _workspaceSelectionRevision++;
    _workspaceIdsWithClearedLayout.remove(workspace.id);
    final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
    final selectionRevisionBeforeActivation =
        _panelSelectionRevisionByWorkspace[workspace.id] ?? 0;
    final prefs = state.viewPrefs;
    final nextPrefs = prefs;
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: nextPrefs,
      error: null,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    _pruneExplorerSessions();
    if (ensureInitialTerminal) {
      await _ensurePrimaryTerminal(workspace);
    }
    if ((_workspaceSleepGeneration[workspace.id] ?? 0) != sleepGeneration) {
      return;
    }
    final tabs = await _workspaceTabService.listTabs(workspace.id);
    if ((_workspaceSleepGeneration[workspace.id] ?? 0) != sleepGeneration) {
      return;
    }
    _setTabsForWorkspace(workspace.id, tabs);
    final layout = await _ensureWorkbenchLayout(
      workspace.id,
      tabs,
      sleepGeneration: sleepGeneration,
    );
    if ((_workspaceSleepGeneration[workspace.id] ?? 0) != sleepGeneration) {
      return;
    }
    await _applyLayout(layout, persist: false);
    if ((_workspaceSleepGeneration[workspace.id] ?? 0) != sleepGeneration) {
      return;
    }
    final storedPanel = state.viewPrefs.workspacePanels[workspace.id];
    final selectionChangedDuringActivation =
        (_panelSelectionRevisionByWorkspace[workspace.id] ?? 0) >
        selectionRevisionBeforeActivation;
    if (!selectionChangedDuringActivation &&
        state.activeWorkspaceId == workspace.id) {
      final panel = state.workspacePanelFor(workspace.id);
      final savedKey = storedPanel?.focusedKey;
      final savedKeyIsLive =
          savedKey != null &&
          (panel.occupiedKeys.contains(savedKey) ||
              WorkspaceTool.forKey(savedKey) != null);
      if (savedKeyIsLive) {
        selectWorkspacePanelKey(workspace.id, savedKey, recordSelection: false);
      } else {
        final preferredId = layout.activeTabId ?? panel.primaryTabId;
        if (preferredId != null) {
          selectWorkspacePanelKey(
            workspace.id,
            WorkspacePanel.tabKey(preferredId),
            recordSelection: false,
          );
        }
      }
    }
    // A later selection or Home may have replaced this one during the awaits.
    if (recordHistory &&
        state.activeWorkspaceId == workspace.id &&
        _worktreeNavigationHistory.record(
          WorktreeNavigationTarget(
            projectId: project.id,
            workspaceId: workspace.id,
          ),
        )) {
      _notifyNavigationHistoryChanged();
    }
  }

  Future<void> activateProject(Project project) async {
    _workspaceSelectionRevision++;
    final prefs = state.viewPrefs;
    final nextPrefs = prefs;
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: null,
      viewPrefs: nextPrefs,
      error: null,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    _pruneExplorerSessions();
    _leaveWorktreeHistory();
  }

  /// Leaves the active workspace for the welcome dashboard. The workspace and
  /// its tabs stay alive, so selecting it again resumes where it was.
  void showHome() {
    if (state.activeWorkspaceId == null) {
      return;
    }
    _workspaceSelectionRevision++;
    state = state.copyWith(activeWorkspaceId: null, error: null);
    _pruneExplorerSessions();
    _leaveWorktreeHistory();
  }

  void _leaveWorktreeHistory() {
    if (_worktreeNavigationHistory.leaveCurrent()) {
      _notifyNavigationHistoryChanged();
    }
  }
}
