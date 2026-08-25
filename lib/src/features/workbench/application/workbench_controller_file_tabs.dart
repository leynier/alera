part of 'workbench_controller.dart';

/// Opening and pinning file-backed tabs, including explorer preview replacement.
mixin _WorkbenchControllerFileTabs
    on _$WorkbenchController, _WorkbenchControllerInternals {
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      preview: preview,
      createTab: _workspaceTabService.openOrCreateEditorTab,
    );
  }

  Future<WorkspaceTabRecord> openMarkdownViewerTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      preview: preview,
      createTab: _workspaceTabService.openOrCreateMarkdownViewerTab,
    );
  }

  Future<WorkspaceTabRecord> openPdfTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      preview: preview,
      createTab: _workspaceTabService.openOrCreatePdfTab,
    );
  }

  Future<WorkspaceTabRecord> openFileTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) {
    if (isWorkspaceMarkdownFilePath(relativePath)) {
      return openMarkdownViewerTab(
        workspace: workspace,
        relativePath: relativePath,
        targetGroupId: targetGroupId,
        preview: preview,
      );
    }
    return isWorkspacePdfFilePath(relativePath)
        ? openPdfTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
            preview: preview,
          )
        : openEditorTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
            preview: preview,
          );
  }

  Future<WorkspaceTabRecord> keepPreviewTab(String tabId) {
    return _serializedFileTabMutation(() => _keepPreviewTabUnlocked(tabId));
  }

  Future<WorkspaceTabRecord> _openFileBackedTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    required bool preview,
    required Future<WorkspaceTabRecord> Function({
      required String workspaceId,
      required String relativePath,
      bool preview,
      String? replacePreviewTabId,
    })
    createTab,
  }) {
    return _serializedFileTabMutation(
      () => _openFileBackedTabUnlocked(
        workspace: workspace,
        relativePath: relativePath,
        targetGroupId: targetGroupId,
        preview: preview,
        createTab: createTab,
      ),
    );
  }

  Future<T> _serializedFileTabMutation<T>(Future<T> Function() action) async {
    final previous = _fileOpenQueue;
    final gate = Completer<void>();
    _fileOpenQueue = gate.future;
    if (previous != null) {
      await previous;
    }
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_fileOpenQueue, gate.future)) {
        _fileOpenQueue = null;
      }
    }
  }

  Future<WorkspaceTabRecord> _keepPreviewTabUnlocked(String tabId) async {
    try {
      final tab = await _workspaceTabService.keepPreviewTab(tabId);
      final tabs = <WorkspaceTabRecord>[
        for (final candidate in state.tabsFor(tab.workspaceId))
          if (candidate.id == tab.id) tab else candidate,
      ];
      _setTabsForWorkspace(tab.workspaceId, tabs);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<WorkspaceTabRecord> _openFileBackedTabUnlocked({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    required bool preview,
    required Future<WorkspaceTabRecord> Function({
      required String workspaceId,
      required String relativePath,
      bool preview,
      String? replacePreviewTabId,
    })
    createTab,
  }) async {
    try {
      var previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      var replacePreviewTabId = preview
          ? _filePreviewTabIdInGroup(
              layout: layout,
              tabs: previousTabs,
              groupId: groupId,
            )
          : null;
      if (replacePreviewTabId != null &&
          ref
              .read(editorSessionRegistryProvider)
              .isDirty(replacePreviewTabId)) {
        await _keepPreviewTabUnlocked(replacePreviewTabId);
        replacePreviewTabId = null;
        previousTabs = state.tabsFor(workspace.id);
      }
      final tab = await createTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
        preview: preview,
        replacePreviewTabId: replacePreviewTabId,
      );
      WorkspaceTabRecord? previousTab;
      for (final candidate in previousTabs) {
        if (candidate.id == tab.id) {
          previousTab = candidate;
          break;
        }
      }
      final alreadyOpen = previousTab != null;
      if (previousTab != null &&
          (previousTab.filePath != tab.filePath ||
              previousTab.kind != tab.kind)) {
        ref.read(editorSessionRegistryProvider).forget(tab.id);
      }
      final tabs = alreadyOpen
          ? previousTabs
                .map((candidate) => candidate.id == tab.id ? tab : candidate)
                .toList(growable: false)
          : <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final nextLayout = alreadyOpen
          ? layout.setActiveTab(
              groupId: layout.groupIdForTab(tab.id) ?? groupId,
              tabId: tab.id,
            )
          : layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  String? _filePreviewTabIdInGroup({
    required WorkbenchLayout layout,
    required List<WorkspaceTabRecord> tabs,
    required String groupId,
  }) {
    final group = layout.groups[groupId];
    if (group == null) {
      return null;
    }
    final tabsById = <String, WorkspaceTabRecord>{
      for (final tab in tabs) tab.id: tab,
    };
    final active = tabsById[group.activeTabId];
    if (active != null && active.isFilePreviewSlot) {
      return active.id;
    }
    for (final tabId in group.tabIds) {
      final tab = tabsById[tabId];
      if (tab != null && tab.isFilePreviewSlot) {
        return tab.id;
      }
    }
    return null;
  }
}
