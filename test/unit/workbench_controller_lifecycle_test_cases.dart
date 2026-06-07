part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerLifecycleTests() {
  test('bootstrap prepares the main workspace without selecting it', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    expect(_controller.state.activeProjectId, _harness.project.id);
    expect(_controller.state.activeWorkspace, isNull);
    final workspaces = _controller.state.workspacesFor(_harness.project.id);
    expect(workspaces.single.isMain, isTrue);
    expect(_controller.state.tabsFor(workspaces.single.id), isEmpty);
    expect(_controller.state.activeWorkspaceTab, isNull);
  });

  test(
    'selecting a workspace with no tabs seeds the first terminal tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.title),
        <String>['Terminal 1'],
      );
      expect(_controller.state.activeWorkspaceTab?.title, 'Terminal 1');
    },
  );

  test(
    'openFileTab upgrades a legacy PDF editor tab without duplicating it',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final legacyTab = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/guide.pdf',
      );
      await _flush();

      expect(legacyTab.kind, WorkspaceTabKind.editor);

      final openedTab = await _controller.openFileTab(
        workspace: workspace,
        relativePath: './docs/guide.pdf',
      );
      await _flush();

      final tabs = _controller.state.tabsFor(workspace.id);
      final pdfTabs = tabs
          .where((tab) => tab.filePath == 'docs/guide.pdf')
          .toList(growable: false);
      expect(openedTab.id, legacyTab.id);
      expect(openedTab.kind, WorkspaceTabKind.pdf);
      expect(pdfTabs, hasLength(1));
      expect(pdfTabs.single.id, legacyTab.id);
      expect(pdfTabs.single.kind, WorkspaceTabKind.pdf);
      expect(_controller.state.activeWorkspaceTab?.id, legacyTab.id);
      expect(_controller.state.activeWorkspaceTab?.kind, WorkspaceTabKind.pdf);
    },
  );

  test('closing the last active tab deselects the workspace', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);

    expect(_controller.state.activeWorkspaceTab?.id, secondTab.id);

    await _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: secondTab.id,
    );
    await _flush();

    expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);

    await _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: firstTab.id,
    );
    await _flush();

    final tabs = _controller.state.tabsFor(workspace.id);
    expect(tabs, isEmpty);
    expect(_controller.state.activeWorkspace, isNull);
    expect(_controller.state.activeWorkspaceTab, isNull);
    expect(_controller.state.activeTabIdByWorkspace[workspace.id], isNull);
    expect(_controller.state.layoutFor(workspace.id)?.activeTabId, isNull);
  });

  test(
    'closing the last tab of an inactive workspace keeps the active workspace',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);

      final linked = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/inactive-close',
      );
      await _flush();
      final linkedTab = _controller.state.activeWorkspaceTab!;

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      await _flush();
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);

      await _controller.closeWorkspaceTab(
        workspace: linked,
        tabId: linkedTab.id,
      );
      await _flush();

      expect(_controller.state.tabsFor(linked.id), isEmpty);
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
    },
  );

  test('closing several tabs keeps the remaining tab active', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);
    final thirdTab = await _controller.createTerminalTab(workspace);
    await _flush();

    await _controller.closeWorkspaceTabs(
      workspace: workspace,
      tabIds: <String>[secondTab.id, thirdTab.id],
    );
    await _flush();

    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      <String>[firstTab.id],
    );
    expect(_controller.state.activeWorkspaceId, workspace.id);
    expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);
    expect(_controller.state.layoutFor(workspace.id)?.activeTabId, firstTab.id);
  });

  test('renames project, workspace, and terminal tab in state', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    await _controller.renameProject(
      projectId: _harness.project.id,
      name: '  Renamed project  ',
    );
    await _flush();
    expect(_controller.state.projects.single.name, 'Renamed project');

    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.renameWorkspace(
      workspaceId: workspace.id,
      name: '  Primary workspace  ',
    );
    await _flush();
    expect(
      _controller.state.workspacesFor(_harness.project.id).single.name,
      'Primary workspace',
    );

    final tab = _controller.state.activeWorkspaceTab!;
    await _controller.renameWorkspaceTab(
      tabId: tab.id,
      title: '  API server  ',
    );
    await _flush();
    expect(_controller.state.activeWorkspaceTab?.title, 'API server');
    expect(_controller.state.activeWorkspaceTab?.hasManualTitle, isTrue);
  });

  test('opens merman preview as a separate tab from the editor', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final editor = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    final preview = await _controller.openMermanPreviewTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    await _flush();

    expect(editor.id, isNot(preview.id));
    expect(editor.isMermanPreview, isFalse);
    expect(preview.isMermanPreview, isTrue);
    expect(preview.title, 'diagram.mmd preview');
    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      containsAll(<String>[editor.id, preview.id]),
    );
    expect(_controller.state.activeWorkspaceTab?.id, preview.id);

    final reopenedEditor = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    await _flush();

    expect(reopenedEditor.id, editor.id);
    expect(_controller.state.activeWorkspaceTab?.id, editor.id);
    expect(_controller.state.tabsFor(workspace.id), hasLength(3));
  });

  test(
    'opening editor from preview recreates the editor tab if needed',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final editor = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      final preview = await _controller.openMermanPreviewTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: editor.id,
      );
      await _flush();

      final recreated = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      await _flush();

      expect(recreated.id, isNot(editor.id));
      expect(recreated.isMermanPreview, isFalse);
      expect(_controller.state.activeWorkspaceTab?.id, recreated.id);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        containsAll(<String>[preview.id, recreated.id]),
      );
    },
  );

  test(
    'syncing a merman rename to text removes redundant preview tabs from state and layout',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final editor = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      final preview = await _controller.openMermanPreviewTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      await _flush();

      await _controller.syncEditorTabsAfterPathMove(
        workspace: workspace,
        oldRelativePath: 'docs/diagram.mmd',
        newRelativePath: 'docs/diagram.txt',
      );
      await _flush();

      final tabs = _controller.state.tabsFor(workspace.id);
      expect(tabs.map((tab) => tab.id), isNot(contains(preview.id)));
      expect(
        tabs.singleWhere((tab) => tab.id == editor.id).filePath,
        'docs/diagram.txt',
      );
      expect(
        tabs.singleWhere((tab) => tab.id == editor.id).isMermanPreview,
        isFalse,
      );
      final layout = _controller.state.layoutFor(workspace.id);
      expect(
        layout?.groups.values.expand((group) => group.tabIds),
        isNot(contains(preview.id)),
      );
      expect(
        _harness.workbenchRepository
            .peekWorkbenchLayout(workspace.id)
            ?.groups
            .values
            .expand((group) => group.tabIds),
        isNot(contains(preview.id)),
      );
    },
  );

  test(
    'deleting a workspace removes it from state without lingering',
    () async {
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );
      final mainWorkspace = _controller.state
          .workspacesFor(_harness.project.id)
          .single;

      final linked = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/delete-me',
      );
      await _flush();
      expect(
        _controller.state.workspacesFor(_harness.project.id).map((w) => w.id),
        containsAll(<String>[mainWorkspace.id, linked.id]),
      );

      await _controller.deleteWorkspace(
        project: _harness.project,
        workspace: linked,
      );
      await _flush();

      expect(
        _controller.state.workspacesFor(_harness.project.id).map((w) => w.id),
        <String>[mainWorkspace.id],
      );
    },
  );

  test(
    'deleting the active workspace clears the workspace selection',
    () async {
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );

      final linked = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/active',
      );
      await _flush();
      expect(_controller.state.activeWorkspaceId, linked.id);
      expect(_controller.state.activeProjectId, _harness.project.id);

      await _controller.deleteWorkspace(
        project: _harness.project,
        workspace: linked,
      );
      await _flush();

      expect(_controller.state.activeProjectId, _harness.project.id);
      expect(_controller.state.activeWorkspace, isNull);
    },
  );

  test('collapsing a project survives a later projects emission', () async {
    await _controller.bootstrap();
    await _flush();
    expect(_controller.state.expandedProjectIds, contains(_harness.project.id));

    _controller.toggleExpanded(_harness.project.id);
    expect(
      _controller.state.expandedProjectIds,
      isNot(contains(_harness.project.id)),
    );

    final secondProject = await _harness.addProject('project-2', 'Beta');
    await _flush();

    expect(
      _controller.state.expandedProjectIds,
      isNot(contains(_harness.project.id)),
    );
    expect(_controller.state.expandedProjectIds, contains(secondProject.id));
  });

  test('splits a workspace group and preserves terminal tab ids', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstTab = _controller.state.activeWorkspaceTab!;
    final groupId = _controller.state.layoutFor(workspace.id)!.activeGroupId;

    final secondTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: groupId,
      zone: WorkbenchDropZone.right,
    );
    await _flush();

    final layout = _controller.state.layoutFor(workspace.id)!;
    expect(layout.root.axis, WorkbenchSplitAxis.horizontal);
    expect(layout.paneGroupIds, hasLength(2));
    expect(_controller.state.tabsFor(workspace.id).map((tab) => tab.id), [
      firstTab.id,
      secondTab.id,
    ]);
    expect(layout.groupIdForTab(firstTab.id), groupId);
    expect(layout.groupIdForTab(secondTab.id), isNot(groupId));
    expect(_controller.state.activeWorkspaceTab?.id, secondTab.id);
  });

  test(
    'moves a tab into another stack and collapses the empty source pane',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstGroupId = _controller.state
          .layoutFor(workspace.id)!
          .activeGroupId;
      final movedTab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: firstGroupId,
        zone: WorkbenchDropZone.down,
      );
      await _flush();
      final splitLayout = _controller.state.layoutFor(workspace.id)!;
      expect(splitLayout.paneGroupIds, hasLength(2));

      await _controller.moveWorkspaceTab(
        workspaceId: workspace.id,
        tabId: movedTab.id,
        targetGroupId: firstGroupId,
        zone: WorkbenchDropZone.center,
      );
      await _flush();

      final layout = _controller.state.layoutFor(workspace.id)!;
      expect(layout.paneGroupIds, <String>[firstGroupId]);
      expect(layout.groups[firstGroupId]?.tabIds, contains(movedTab.id));
      expect(_controller.state.activeWorkspaceTab?.id, movedTab.id);
    },
  );

  test('updates and persists split ratios', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final groupId = _controller.state.layoutFor(workspace.id)!.activeGroupId;
    await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: groupId,
      zone: WorkbenchDropZone.right,
    );
    await _flush();

    _controller.updateWorkbenchSplitRatio(
      workspaceId: workspace.id,
      nodePath: const <int>[],
      ratio: 0.8,
    );
    await _flush();

    final layout = _controller.state.layoutFor(workspace.id)!;
    expect(layout.root.ratio, 0.8);
    expect(
      await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
      isNotNull,
    );
    expect(
      (await _harness.workbenchRepository.findWorkbenchLayout(
        workspace.id,
      ))!.root.ratio,
      0.8,
    );
  });

  test(
    'setActiveTab falls back to direct workspace selection when the layout has no group for the tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      _controller.setActiveTab(workspaceId: workspace.id, tabId: 'missing-tab');
      await _flush();

      expect(
        _controller.state.activeTabIdByWorkspace[workspace.id],
        'missing-tab',
      );
    },
  );

  test('selecting a workspace preserves the saved active tab', () async {
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: _harness.project.id,
      name: 'Main',
      branch: 'main',
      path: _harness.project.repoPath,
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
      kind: WorkspaceKind.main,
      status: WorkspaceStatus.active,
    );
    final firstTab = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: workspace.id,
      title: 'Terminal 1',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
    );
    final secondTab = WorkspaceTabRecord(
      id: 'tab-2',
      workspaceId: workspace.id,
      title: 'Terminal 2',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
    );
    final savedLayout =
        WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[firstTab.id],
        ).splitWithGroup(
          targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
          zone: WorkbenchDropZone.right,
          newGroup: WorkbenchPaneGroup(
            id: 'group-2',
            tabIds: <String>[secondTab.id],
            activeTabId: secondTab.id,
          ),
        );
    await _harness.workbenchRepository.upsertWorkspace(workspace);
    await _harness.workbenchRepository.upsertWorkspaceTab(firstTab);
    await _harness.workbenchRepository.upsertWorkspaceTab(secondTab);
    await _harness.workbenchRepository.upsertWorkbenchLayout(savedLayout);

    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    await _flush();

    expect(
      _controller.state.layoutFor(workspace.id)?.activeTabId,
      secondTab.id,
    );
    expect(
      _controller.state.activeTabIdByWorkspace[workspace.id],
      secondTab.id,
    );
    expect(
      _harness.workbenchRepository
          .peekWorkbenchLayout(workspace.id)
          ?.activeTabId,
      secondTab.id,
    );
  });
}
