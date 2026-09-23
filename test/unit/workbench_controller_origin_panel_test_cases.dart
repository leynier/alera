part of 'workbench_controller_test.dart';

void _registerOriginPanelTests() {
  for (final tree in WorkspacePanelTree.values) {
    test('Explorer opens and replaces previews only in $tree', () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.explorer.key,
      );
      var panel = _controller.state.workspacePanelFor(workspace.id);
      final mainGroup = panel.ensuredMainLayout(workspace.id).activeGroupId;
      final rightGroup = panel.ensuredLayout(workspace.id).activeGroupId;
      if (tree == WorkspacePanelTree.main) {
        await _controller.moveWorkspacePaneTab(
          workspaceId: workspace.id,
          tabId: WorkspaceTool.explorer.key,
          targetGroupId: mainGroup,
          zone: WorkbenchDropZone.center,
          source: WorkspacePanelTree.right,
          target: tree,
        );
      }
      final other = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'other.dart',
        targetGroupId: tree == WorkspacePanelTree.main ? rightGroup : mainGroup,
        preview: true,
      );
      // The other panel is focused when Explorer's callback fires.
      final first = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'first.dart',
        sourceKey: WorkspaceTool.explorer.key,
        preview: true,
      );
      final second = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'second.md',
        sourceKey: WorkspaceTool.explorer.key,
        preview: true,
      );
      panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.treeForKey(WorkspacePanel.tabKey(second.id)), tree);
      expect(first.id, second.id);
      expect(second.id, isNot(other.id));
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .singleWhere((tab) => tab.id == other.id)
            .filePath,
        'other.dart',
      );
    });

    test('Markdown opens source in its own $tree panel', () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final initial = _controller.state.workspacePanelFor(workspace.id);
      final group = tree == WorkspacePanelTree.main
          ? initial.ensuredMainLayout(workspace.id).activeGroupId
          : initial.ensuredLayout(workspace.id).activeGroupId;
      final preview = await _controller.openMarkdownViewerTab(
        workspace: workspace,
        relativePath: 'README.md',
        targetGroupId: group,
      );
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.search.key,
      );
      final source = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'README.md',
        sourceKey: WorkspacePanel.tabKey(preview.id),
      );
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.treeForKey(WorkspacePanel.tabKey(source.id)), tree);
      expect(source.id, isNot(preview.id));
      expect(panel.focusedKey, WorkspacePanel.tabKey(source.id));
    });
  }

  test('queued opens retain their origin group when focus changes', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final initial = _controller.state.workspacePanelFor(workspace.id);
    final mainGroup = initial.ensuredMainLayout(workspace.id).activeGroupId;
    final source = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'source.dart',
      targetGroupId: mainGroup,
    );
    final pending = _controller.openFileTab(
      workspace: workspace,
      relativePath: 'next.dart',
      sourceKey: WorkspacePanel.tabKey(source.id),
      preview: true,
    );
    _controller.selectWorkspacePanelKey(workspace.id, WorkspaceTool.search.key);
    final opened = await pending;
    expect(
      _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .groupIdForTab(WorkspacePanel.tabKey(opened.id)),
      mainGroup,
    );
  });
  test(
    'new files stay in the originating split, existing files stay put',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final mainGroup = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId;
      final source = await _controller.splitWorkspacePaneWithTerminal(
        workspace: workspace,
        groupId: mainGroup,
        zone: WorkbenchDropZone.right,
      );
      final splitGroup = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .groupIdForTab(WorkspacePanel.tabKey(source.id));
      final existing = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'existing.dart',
        targetGroupId: mainGroup,
      );
      final next = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'new.dart',
        sourceKey: WorkspacePanel.tabKey(source.id),
      );
      final reopened = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'existing.dart',
        sourceKey: WorkspacePanel.tabKey(source.id),
      );
      final layout = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id);
      expect(layout.groupIdForTab(WorkspacePanel.tabKey(next.id)), splitGroup);
      expect(reopened.id, existing.id);
      expect(
        layout.groupIdForTab(WorkspacePanel.tabKey(existing.id)),
        mainGroup,
      );
    },
  );

  for (final tree in WorkspacePanelTree.values) {
    test('Mod-open from $tree opens a preview in the opposite panel', () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.explorer.key,
      );
      var panel = _controller.state.workspacePanelFor(workspace.id);
      final mainGroup = panel.ensuredMainLayout(workspace.id).activeGroupId;
      final rightGroup = panel.ensuredLayout(workspace.id).activeGroupId;
      if (tree == WorkspacePanelTree.main) {
        await _controller.moveWorkspacePaneTab(
          workspaceId: workspace.id,
          tabId: WorkspaceTool.explorer.key,
          targetGroupId: mainGroup,
          zone: WorkbenchDropZone.center,
          source: WorkspacePanelTree.right,
          target: tree,
        );
        _controller.setRightSidebarVisible(false);
      }
      final existing = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'already.dart',
        targetGroupId: tree == WorkspacePanelTree.main ? mainGroup : rightGroup,
        preview: true,
      );
      final opened = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'already.dart',
        sourceKey: WorkspaceTool.explorer.key,
        preview: true,
        oppositePanel: true,
      );
      panel = _controller.state.workspacePanelFor(workspace.id);
      expect(opened.id, isNot(existing.id));
      expect(opened.isPreview, isTrue);
      expect(panel.treeForKey(WorkspacePanel.tabKey(opened.id)), tree.opposite);
      expect(panel.treeForKey(WorkspacePanel.tabKey(existing.id)), tree);
      expect(panel.focusedKey, WorkspacePanel.tabKey(opened.id));
      if (tree == WorkspacePanelTree.main) {
        expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);
      }
    });

    test(
      'Mod-open from $tree reuses a matching tab already in the opposite panel',
      () async {
        await _controller.bootstrap();
        final workspace = await _selectMainWorkspace(_controller, _harness);
        _controller.selectWorkspacePanelKey(
          workspace.id,
          WorkspaceTool.explorer.key,
        );
        var panel = _controller.state.workspacePanelFor(workspace.id);
        final mainGroup = panel.ensuredMainLayout(workspace.id).activeGroupId;
        final rightGroup = panel.ensuredLayout(workspace.id).activeGroupId;
        if (tree == WorkspacePanelTree.main) {
          await _controller.moveWorkspacePaneTab(
            workspaceId: workspace.id,
            tabId: WorkspaceTool.explorer.key,
            targetGroupId: mainGroup,
            zone: WorkbenchDropZone.center,
            source: WorkspacePanelTree.right,
            target: tree,
          );
        }
        final oppositeGroup = tree == WorkspacePanelTree.main
            ? rightGroup
            : mainGroup;
        final existing = await _controller.openFileTab(
          workspace: workspace,
          relativePath: 'shared.dart',
          targetGroupId: oppositeGroup,
          preview: true,
        );
        final opened = await _controller.openFileTab(
          workspace: workspace,
          relativePath: 'shared.dart',
          sourceKey: WorkspaceTool.explorer.key,
          preview: true,
          oppositePanel: true,
        );
        panel = _controller.state.workspacePanelFor(workspace.id);
        expect(opened.id, existing.id);
        expect(
          panel.treeForKey(WorkspacePanel.tabKey(opened.id)),
          tree.opposite,
        );
      },
    );
  }

  test('Mod-open preview replacement stays in the opposite panel', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final mainGroup = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    await _controller.moveWorkspacePaneTab(
      workspaceId: workspace.id,
      tabId: WorkspaceTool.explorer.key,
      targetGroupId: mainGroup,
      zone: WorkbenchDropZone.center,
      source: WorkspacePanelTree.right,
      target: WorkspacePanelTree.main,
    );
    final originPreview = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'origin.dart',
      sourceKey: WorkspaceTool.explorer.key,
      preview: true,
    );
    final firstOpposite = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'first.dart',
      sourceKey: WorkspaceTool.explorer.key,
      preview: true,
      oppositePanel: true,
    );
    final secondOpposite = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'second.md',
      sourceKey: WorkspaceTool.explorer.key,
      preview: true,
      oppositePanel: true,
    );
    final panel = _controller.state.workspacePanelFor(workspace.id);
    expect(firstOpposite.id, secondOpposite.id);
    expect(secondOpposite.id, isNot(originPreview.id));
    expect(
      panel.treeForKey(WorkspacePanel.tabKey(originPreview.id)),
      WorkspacePanelTree.main,
    );
    expect(
      panel.treeForKey(WorkspacePanel.tabKey(secondOpposite.id)),
      WorkspacePanelTree.right,
    );
    expect(
      _controller.state
          .tabsFor(workspace.id)
          .singleWhere((tab) => tab.id == originPreview.id)
          .filePath,
      'origin.dart',
    );
  });
}
