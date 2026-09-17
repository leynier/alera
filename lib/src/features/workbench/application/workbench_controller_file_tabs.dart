part of 'workbench_controller.dart';

/// Opening and pinning file-backed tabs, including shared preview replacement.
mixin _WorkbenchControllerFileTabs
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerInternalLayout {
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    return _openReplaceableTab(
      workspace: workspace,
      targetGroupId: targetGroupId,
      sourceKey: sourceKey,
      preview: preview,
      createTab:
          ({required workspaceId, required preview, replacePreviewTabId}) {
            return _workspaceTabService.openOrCreateEditorTab(
              workspaceId: workspaceId,
              relativePath: relativePath,
              preview: preview,
              replacePreviewTabId: replacePreviewTabId,
            );
          },
    );
  }

  Future<WorkspaceTabRecord> openMarkdownViewerTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    return _openReplaceableTab(
      workspace: workspace,
      targetGroupId: targetGroupId,
      sourceKey: sourceKey,
      preview: preview,
      createTab:
          ({required workspaceId, required preview, replacePreviewTabId}) {
            return _workspaceTabService.openOrCreateMarkdownViewerTab(
              workspaceId: workspaceId,
              relativePath: relativePath,
              preview: preview,
              replacePreviewTabId: replacePreviewTabId,
            );
          },
    );
  }

  Future<WorkspaceTabRecord> openPdfTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    return _openReplaceableTab(
      workspace: workspace,
      targetGroupId: targetGroupId,
      sourceKey: sourceKey,
      preview: preview,
      createTab:
          ({required workspaceId, required preview, replacePreviewTabId}) {
            return _workspaceTabService.openOrCreatePdfTab(
              workspaceId: workspaceId,
              relativePath: relativePath,
              preview: preview,
              replacePreviewTabId: replacePreviewTabId,
            );
          },
    );
  }

  Future<WorkspaceTabRecord> openFileTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    if (isWorkspaceMarkdownFilePath(relativePath)) {
      return openMarkdownViewerTab(
        workspace: workspace,
        relativePath: relativePath,
        targetGroupId: targetGroupId,
        sourceKey: sourceKey,
        preview: preview,
      );
    }
    return isWorkspacePdfFilePath(relativePath)
        ? openPdfTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
            sourceKey: sourceKey,
            preview: preview,
          )
        : openEditorTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
            sourceKey: sourceKey,
            preview: preview,
          );
  }

  Future<WorkspaceTabRecord> openGitDiffTab({
    required Workspace workspace,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    return _openReplaceableTab(
      workspace: workspace,
      targetGroupId: targetGroupId,
      sourceKey: sourceKey,
      preview: preview,
      createTab:
          ({required workspaceId, required preview, replacePreviewTabId}) {
            return _workspaceTabService.openOrCreateGitDiffTab(
              workspaceId: workspaceId,
              relativePath: relativePath,
              area: area,
              scope: scope,
              gitDiffRoot: gitDiffRoot,
              preview: preview,
              replacePreviewTabId: replacePreviewTabId,
            );
          },
    );
  }

  Future<WorkspaceTabRecord> openGitCommitDiffTab({
    required Workspace workspace,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
    String? targetGroupId,
    String? sourceKey,
    bool preview = false,
  }) {
    return _openReplaceableTab(
      workspace: workspace,
      targetGroupId: targetGroupId,
      sourceKey: sourceKey,
      preview: preview,
      createTab:
          ({required workspaceId, required preview, replacePreviewTabId}) {
            return _workspaceTabService.openOrCreateGitCommitDiffTab(
              workspaceId: workspaceId,
              relativePath: relativePath,
              oldPath: oldPath,
              scope: scope,
              gitDiffRoot: gitDiffRoot,
              commitOid: commitOid,
              parentOid: parentOid,
              compareRef: compareRef,
              subject: subject,
              message: message,
              preview: preview,
              replacePreviewTabId: replacePreviewTabId,
            );
          },
    );
  }

  Future<WorkspaceTabRecord> keepPreviewTab(String tabId) {
    final tab = state.tabsByWorkspace.values
        .expand((tabs) => tabs)
        .where((candidate) => candidate.id == tabId)
        .firstOrNull;
    final sleepGeneration = tab == null
        ? 0
        : (_workspaceSleepGeneration[tab.workspaceId] ?? 0);
    return _serializedFileTabMutation(
      () => _keepPreviewTabUnlocked(tabId, sleepGeneration: sleepGeneration),
    );
  }

  Future<WorkspaceTabRecord> _openReplaceableTab({
    required Workspace workspace,
    String? targetGroupId,
    String? sourceKey,
    required bool preview,
    required Future<WorkspaceTabRecord> Function({
      required String workspaceId,
      required bool preview,
      String? replacePreviewTabId,
    })
    createTab,
  }) {
    final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
    final openingGroupId =
        targetGroupId ?? _groupForOpening(workspace.id, sourceKey);
    return _serializedFileTabMutation(
      () => _openReplaceableTabUnlocked(
        workspace: workspace,
        targetGroupId: openingGroupId,
        preview: preview,
        createTab: createTab,
        sleepGeneration: sleepGeneration,
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

  Future<WorkspaceTabRecord> _keepPreviewTabUnlocked(
    String tabId, {
    required int sleepGeneration,
  }) async {
    try {
      final tab = await _workspaceTabService.keepPreviewTab(tabId);
      if (_isStaleWorkspaceOpen(tab.workspaceId, sleepGeneration) ||
          _closedTabIds.contains(tab.id)) {
        await _discardStaleOpenedTab(tab);
        throw StateError('Workspace is no longer available for an editor tab');
      }
      final live = state.tabsFor(tab.workspaceId);
      if (live.every((candidate) => candidate.id != tab.id) ||
          _closedTabIds.contains(tab.id)) {
        await _discardStaleOpenedTab(tab);
        throw StateError('Workspace is no longer available for an editor tab');
      }
      final tabs = <WorkspaceTabRecord>[
        for (final candidate in live)
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

  Future<WorkspaceTabRecord> _openReplaceableTabUnlocked({
    required Workspace workspace,
    String? targetGroupId,
    required bool preview,
    required Future<WorkspaceTabRecord> Function({
      required String workspaceId,
      required bool preview,
      String? replacePreviewTabId,
    })
    createTab,
    required int sleepGeneration,
  }) async {
    try {
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration)) {
        throw StateError('Workspace is no longer available for an editor tab');
      }
      var previousTabs = state.tabsFor(workspace.id);
      var replacePreviewTabId = preview
          ? _previewTabIdInGroup(
              workspaceId: workspace.id,
              tabs: previousTabs,
              targetGroupId: targetGroupId,
            )
          : null;
      if (replacePreviewTabId != null &&
          ref
              .read(editorSessionRegistryProvider)
              .isDirty(replacePreviewTabId)) {
        await _keepPreviewTabUnlocked(
          replacePreviewTabId,
          sleepGeneration: sleepGeneration,
        );
        if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration)) {
          throw StateError(
            'Workspace is no longer available for an editor tab',
          );
        }
        replacePreviewTabId = null;
        previousTabs = state.tabsFor(workspace.id);
      }
      final previousById = <String, WorkspaceTabRecord>{
        for (final candidate in previousTabs) candidate.id: candidate,
      };
      final tab = await createTab(
        workspaceId: workspace.id,
        preview: preview,
        replacePreviewTabId: replacePreviewTabId,
      );
      final existedBeforeRequest = previousById.containsKey(tab.id);
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          _closedTabIds.contains(tab.id)) {
        await _discardStaleOpenedTab(
          tab,
          existedBeforeRequest:
              existedBeforeRequest && !_closedTabIds.contains(tab.id),
        );
        throw StateError('Workspace is no longer available for an editor tab');
      }
      final live = state.tabsFor(workspace.id);
      final previousTab = previousById[tab.id];
      if (previousTab != null &&
          (previousTab.filePath != tab.filePath ||
              previousTab.kind != tab.kind)) {
        final registry = ref.read(editorSessionRegistryProvider);
        final attachedPath = registry.documentIfPresent(tab.id)?.relativePath;
        final alreadyRetargeted = attachedPath == tab.filePath;
        if (!alreadyRetargeted) {
          registry.forget(tab.id);
        }
      }
      final tabs =
          existedBeforeRequest ||
              live.any((candidate) => candidate.id == tab.id)
          ? live
                .map((candidate) => candidate.id == tab.id ? tab : candidate)
                .toList(growable: false)
          : <WorkspaceTabRecord>[...live, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      _selectOpenedWorkspaceTab(
        workspaceId: workspace.id,
        tab: tab,
        existedBeforeRequest: existedBeforeRequest,
        targetGroupId: targetGroupId,
      );
      final persisted = _layoutForMutation(workspace.id, tabs);
      state = state.copyWith(
        layoutByWorkspace: <String, WorkbenchLayout>{
          ...state.layoutByWorkspace,
          workspace.id: persisted,
        },
        error: null,
      );
      _persistLayoutInBackground(persisted);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  String? _previewTabIdInGroup({
    required String workspaceId,
    required List<WorkspaceTabRecord> tabs,
    String? targetGroupId,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    if (targetGroupId != null) {
      final group =
          panel.ensuredMainLayout(workspaceId).groups[targetGroupId] ??
          panel.ensuredLayout(workspaceId).groups[targetGroupId];
      final keys = group?.tabIds ?? const <String>[];
      final previews = tabs.where(
        (tab) =>
            tab.isFilePreviewSlot &&
            keys.contains(WorkspacePanel.tabKey(tab.id)),
      );
      return previews
              .where(
                (tab) => WorkspacePanel.tabKey(tab.id) == group?.activeTabId,
              )
              .firstOrNull
              ?.id ??
          previews.firstOrNull?.id;
    }
    final active = WorkspacePanel.tabId(panel.activeKey);

    return tabs
            .where((tab) => tab.id == active && tab.isFilePreviewSlot)
            .firstOrNull
            ?.id ??
        tabs.where((tab) => tab.isFilePreviewSlot).firstOrNull?.id;
  }
}
