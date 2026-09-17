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
}
