part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerViewPrefsTests() {
  test(
    'tab watcher does not overwrite a saved split before layout load finishes',
    () async {
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
      final layoutRead = Completer<WorkbenchLayout?>();
      _harness.workbenchRepository.blockFindWorkbenchLayoutWith(
        layoutRead.future,
      );
      await _harness.workbenchRepository.upsertWorkspace(workspace);
      await _harness.workbenchRepository.upsertWorkspaceTab(firstTab);
      await _harness.workbenchRepository.upsertWorkspaceTab(secondTab);
      await _harness.workbenchRepository.upsertWorkbenchLayout(savedLayout);

      await _controller.bootstrap();
      await _flushUntil(
        () => _harness.workbenchRepository.hasTabWatcher(workspace.id),
      );

      _harness.workbenchRepository.emitTabs(workspace.id);
      await _flush();

      expect(
        _harness.workbenchRepository
            .peekWorkbenchLayout(workspace.id)
            ?.root
            .axis,
        WorkbenchSplitAxis.horizontal,
      );
      expect(_controller.state.layoutFor(workspace.id), isNull);

      layoutRead.complete(savedLayout);
      await _flushUntil(
        () => _controller.state.layoutFor(workspace.id) != null,
      );

      final persisted = _harness.workbenchRepository.peekWorkbenchLayout(
        workspace.id,
      );
      expect(persisted?.root.axis, WorkbenchSplitAxis.horizontal);
      expect(persisted?.paneGroupIds, hasLength(2));
      expect(
        _controller.state.layoutFor(workspace.id)?.paneGroupIds,
        hasLength(2),
      );
    },
  );

  test('bootstrap ignores persisted view-prefs load failures', () async {
    _harness.viewPrefsRepository.loadError = Exception('bad prefs');

    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    expect(_controller.state.bootstrapped, isTrue);
    expect(_controller.state.viewPrefs, WorkbenchViewPrefs.defaults);
    expect(_controller.state.error, isNull);
  });

  test('selecting a workspace preserves agent expansion prefs', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );
    final workspace = _controller.state
        .workspacesFor(_harness.project.id)
        .single;

    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    await _flush();
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(workspace.id)),
    );

    _controller.setWorkspaceExpanded(workspace.id, true);
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    await _flush();
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      contains(workspace.id),
    );
  });

  test('view-pref mutators update state and persist changes', () async {
    await _controller.bootstrap();
    final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
    final linkedWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/view-prefs',
    )).workspace;
    await _flush();

    _controller.setWorkspaceExpanded(mainWorkspace.id, true);
    _controller.setWorkspaceExpanded(linkedWorkspace.id, true);
    _controller.toggleCollapseAll();
    expect(
      _controller.state.viewPrefs.collapsedProjectIds,
      contains(_harness.project.id),
    );
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(mainWorkspace.id)),
    );
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(linkedWorkspace.id)),
    );

    _controller.toggleCollapseAll();
    expect(
      _controller.state.viewPrefs.collapsedProjectIds,
      isNot(contains(_harness.project.id)),
    );
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      containsAll(<String>[mainWorkspace.id, linkedWorkspace.id]),
    );

    _controller.setGroupBy(WorkbenchGroupBy.none);
    _controller.setWorkspaceExpanded(mainWorkspace.id, false);
    _controller.setWorkspaceExpanded(linkedWorkspace.id, false);
    _controller.setProjectSort(WorkbenchSortBy.recent);
    _controller.setWorkspaceSort(WorkbenchSortBy.recent);
    _controller.toggleCollapseAll();
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      containsAll(<String>[mainWorkspace.id, linkedWorkspace.id]),
    );

    _controller.toggleCollapseAll();
    _controller.toggleWorkspaceExpanded(mainWorkspace.id);
    _controller.setWorkspaceExpanded(mainWorkspace.id, false);
    _controller.addProjectFilter(_harness.project.id);
    _controller.toggleProjectFilter(_harness.project.id);
    _controller.clearProjectFilters();
    _controller.setSearchQuery('terminal');
    _controller.setCollapsed(true);
    _controller.setSidebarWidth(AleraTokens.sidebarMaxWidth + 400);
    await _flush();

    expect(_controller.state.viewPrefs.groupBy, WorkbenchGroupBy.none);
    expect(_controller.state.viewPrefs.projectSort, WorkbenchSortBy.recent);
    expect(_controller.state.viewPrefs.workspaceSort, WorkbenchSortBy.recent);
    expect(_controller.state.viewPrefs.selectedProjectIds, isEmpty);
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(mainWorkspace.id)),
    );
    expect(_controller.state.searchQuery, 'terminal');
    expect(_controller.state.collapsed, isTrue);
    expect(
      _controller.state.viewPrefs.sidebarWidth,
      AleraTokens.sidebarMaxWidth,
    );
    expect(
      _harness.viewPrefsRepository.prefs.workspaceSort,
      WorkbenchSortBy.recent,
    );
    expect(_harness.viewPrefsRepository.saveCount, greaterThan(0));
  });

  test(
    'selecting a folder workspace replaces source control with explorer',
    () async {
      await _controller.bootstrap();
      _controller.setContextPanelTab(WorkbenchContextPanelTab.gitDiff);
      await _flush();
      final saveCountBeforeFolderSelection =
          _harness.viewPrefsRepository.saveCount;
      final folderPath = p.join(_harness.tempDir.path, 'notes');
      Directory(folderPath).createSync(recursive: true);
      final now = DateTime.utc(2026, 5, 22);
      final folderProject = Project(
        id: 'project-folder',
        name: 'Notes',
        repoPath: folderPath,
        createdAt: now,
        updatedAt: now,
        kind: ProjectKind.folder,
      );

      await _harness.projectRepository.add(folderProject);
      await _flushUntil(
        () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
      );
      final folderWorkspace = _controller.state
          .workspacesFor(folderProject.id)
          .single;
      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();

      expect(
        _controller.state.viewPrefs.activeContextPanelTab,
        WorkbenchContextPanelTab.explorer,
      );
      expect(
        _harness.viewPrefsRepository.prefs.activeContextPanelTab,
        WorkbenchContextPanelTab.explorer,
      );
      expect(
        _harness.viewPrefsRepository.saveCount,
        greaterThan(saveCountBeforeFolderSelection),
      );
    },
  );

  test('selecting a git workspace keeps source control active', () async {
    await _controller.bootstrap();
    _controller.setContextPanelTab(WorkbenchContextPanelTab.gitDiff);
    await _flush();

    final workspace = await _selectMainWorkspace(_controller, _harness);

    expect(workspace.projectId, _harness.project.id);
    expect(_harness.project.isGitRepository, isTrue);
    expect(
      _controller.state.viewPrefs.activeContextPanelTab,
      WorkbenchContextPanelTab.gitDiff,
    );
  });

  test(
    'folder workspace can focus and clear a nested git source control root',
    () async {
      await _controller.bootstrap();
      final folderPath = p.join(_harness.tempDir.path, 'notes');
      Directory(folderPath).createSync(recursive: true);
      final nestedRepoPath = p.join(folderPath, 'packages', 'app');
      Directory(nestedRepoPath).createSync(recursive: true);
      Directory(p.join(nestedRepoPath, '.git')).createSync();
      final now = DateTime.utc(2026, 5, 22);
      final folderProject = Project(
        id: 'project-folder',
        name: 'Notes',
        repoPath: folderPath,
        createdAt: now,
        updatedAt: now,
        kind: ProjectKind.folder,
      );
      await _harness.projectRepository.add(folderProject);
      await _flushUntil(
        () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
      );
      final folderWorkspace = _controller.state
          .workspacesFor(folderProject.id)
          .single;
      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();

      final focused = await _controller.focusSourceControlFolder(
        workspace: folderWorkspace,
        relativePath: './packages\\app',
      );
      await _flush();

      expect(focused, isTrue);
      expect(
        _harness.gitBackend.calls
            .where((call) => call.method == 'isGitRepository')
            .last
            .args,
        <String, Object?>{'path': nestedRepoPath},
      );
      expect(
        _controller
            .state
            .viewPrefs
            .sourceControlRootByWorkspaceId[folderWorkspace.id],
        'packages/app',
      );
      expect(
        _controller.state.viewPrefs.activeContextPanelTab,
        WorkbenchContextPanelTab.gitDiff,
      );
      expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);

      _controller.clearFocusedSourceControlFolder(workspace: folderWorkspace);
      await _flush();

      expect(
        _controller.state.viewPrefs.sourceControlRootByWorkspaceId,
        isNot(contains(folderWorkspace.id)),
      );
      expect(
        _controller.state.viewPrefs.activeContextPanelTab,
        WorkbenchContextPanelTab.explorer,
      );
    },
  );

  test(
    'folder workspace does not focus a git-discoverable subdirectory',
    () async {
      await _controller.bootstrap();
      final folderPath = p.join(_harness.tempDir.path, 'notes');
      final repoPath = p.join(folderPath, 'repo');
      final nestedPath = p.join(repoPath, 'packages', 'app');
      Directory(p.join(repoPath, '.git')).createSync(recursive: true);
      Directory(nestedPath).createSync(recursive: true);
      final now = DateTime.utc(2026, 5, 22);
      final folderProject = Project(
        id: 'project-folder',
        name: 'Notes',
        repoPath: folderPath,
        createdAt: now,
        updatedAt: now,
        kind: ProjectKind.folder,
      );
      await _harness.projectRepository.add(folderProject);
      await _flushUntil(
        () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
      );
      final folderWorkspace = _controller.state
          .workspacesFor(folderProject.id)
          .single;
      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();
      final repositoryChecksBefore = _harness.gitBackend.calls
          .where((call) => call.method == 'isGitRepository')
          .length;

      final focused = await _controller.focusSourceControlFolder(
        workspace: folderWorkspace,
        relativePath: 'repo/packages/app',
      );
      await _flush();

      expect(focused, isFalse);
      expect(
        _harness.gitBackend.calls
            .where((call) => call.method == 'isGitRepository')
            .length,
        repositoryChecksBefore,
      );
      expect(
        _controller.state.viewPrefs.sourceControlRootByWorkspaceId,
        isEmpty,
      );
    },
  );

  test(
    'folder workspace ignores stale source control focus completions',
    () async {
      await _controller.bootstrap();
      final folderPath = p.join(_harness.tempDir.path, 'notes');
      final nestedRepoPath = p.join(folderPath, 'packages', 'app');
      Directory(p.join(nestedRepoPath, '.git')).createSync(recursive: true);
      final now = DateTime.utc(2026, 5, 22);
      final folderProject = Project(
        id: 'project-folder',
        name: 'Notes',
        repoPath: folderPath,
        createdAt: now,
        updatedAt: now,
        kind: ProjectKind.folder,
      );
      await _harness.projectRepository.add(folderProject);
      await _flushUntil(
        () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
      );
      final folderWorkspace = _controller.state
          .workspacesFor(folderProject.id)
          .single;
      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();

      final gate = Completer<void>();
      _harness.gitBackend.beforeIsGitRepository = (_) => gate.future;
      final focusFuture = _controller.focusSourceControlFolder(
        workspace: folderWorkspace,
        relativePath: 'packages/app',
      );
      await _flushUntil(
        () => _harness.gitBackend.calls.any(
          (call) => call.method == 'isGitRepository',
        ),
      );

      final mainWorkspace = _controller.state
          .workspacesFor(_harness.project.id)
          .single;
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      await _flush();
      gate.complete();

      expect(await focusFuture, isFalse);
      expect(_controller.state.activeProjectId, _harness.project.id);
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
      expect(
        _controller.state.viewPrefs.sourceControlRootByWorkspaceId,
        isEmpty,
      );
    },
  );

  test(
    'folder workspace does not focus a non-git source control root',
    () async {
      await _controller.bootstrap();
      final folderPath = p.join(_harness.tempDir.path, 'notes');
      Directory(folderPath).createSync(recursive: true);
      final now = DateTime.utc(2026, 5, 22);
      final folderProject = Project(
        id: 'project-folder',
        name: 'Notes',
        repoPath: folderPath,
        createdAt: now,
        updatedAt: now,
        kind: ProjectKind.folder,
      );
      await _harness.projectRepository.add(folderProject);
      await _flushUntil(
        () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
      );
      final folderWorkspace = _controller.state
          .workspacesFor(folderProject.id)
          .single;
      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();
      _harness.gitBackend.isRepository = false;

      final focused = await _controller.focusSourceControlFolder(
        workspace: folderWorkspace,
        relativePath: 'packages/app',
      );
      await _flush();

      expect(focused, isFalse);
      expect(
        _controller.state.viewPrefs.sourceControlRootByWorkspaceId,
        isEmpty,
      );
      expect(
        _controller.state.viewPrefs.activeContextPanelTab,
        WorkbenchContextPanelTab.explorer,
      );
    },
  );

  test('bootstrap prunes stale persisted project filters', () async {
    _harness.viewPrefsRepository.prefs = WorkbenchViewPrefs.defaults.copyWith(
      collapsedProjectIds: <String>{'stale-project', _harness.project.id},
      selectedProjectIds: <String>{'stale-project', _harness.project.id},
    );

    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    expect(_controller.state.viewPrefs.collapsedProjectIds, <String>{
      _harness.project.id,
    });
    expect(_controller.state.viewPrefs.selectedProjectIds, <String>{
      _harness.project.id,
    });
  });

  test('bootstrap surfaces project repository failures', () async {
    _harness.projectRepository.listAllError = StateError(
      'cannot list projects',
    );

    await _controller.bootstrap();
    await _flush();

    expect(_controller.state.bootstrapped, isTrue);
    expect(
      _controller.state.error,
      contains(
        'Failed to bootstrap workbench: Bad state: cannot list projects',
      ),
    );
  });

  test(
    'workspace updates prune expansion ids for removed workspaces',
    () async {
      await _controller.bootstrap();
      await _selectMainWorkspace(_controller, _harness);
      final linkedWorkspace = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/remove-expanded',
      )).workspace;
      await _flush();

      _controller.setWorkspaceExpanded(linkedWorkspace.id, true);
      await _flush();

      expect(
        _controller.state.viewPrefs.expandedWorkspaceIds,
        contains(linkedWorkspace.id),
      );

      await _harness.workbenchRepository.removeWorkspace(linkedWorkspace.id);
      await _flush();

      expect(
        _controller.state.viewPrefs.expandedWorkspaceIds,
        isNot(contains(linkedWorkspace.id)),
      );
    },
  );

  test('surfaces project and workspace action failures in state', () async {
    await expectLater(_controller.addLocalProject(path: ''), throwsStateError);
    expect(_controller.state.error, contains('Project path must not be empty'));

    await expectLater(
      _controller.cloneProject(
        gitUrl: 'https://example.com/repo.git',
        destinationPath: '',
      ),
      throwsStateError,
    );
    expect(
      _controller.state.error,
      contains('Destination path must not be empty'),
    );

    await expectLater(
      _controller.renameProject(projectId: 'missing', name: 'Renamed'),
      throwsStateError,
    );
    expect(_controller.state.error, contains('project not found'));

    _harness.projectRepository.removeError = StateError('cannot remove');
    await expectLater(
      _controller.removeProject(_harness.project.id),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot remove'));

    await expectLater(
      _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: '',
        newBranchName: 'feature/failure',
      ),
      throwsA(isA<WorkspaceException>()),
    );
    expect(_controller.state.error, contains('Source Branch Is Required'));

    await expectLater(
      _controller.renameWorkspace(workspaceId: 'missing', name: 'Renamed'),
      throwsA(isA<WorkspaceException>()),
    );
    expect(_controller.state.error, contains('Workspace not found'));

    await _controller.bootstrap();
    final mainWorkspace = await _selectMainWorkspace(_controller, _harness);

    await expectLater(
      _controller.deleteWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      ),
      throwsA(isA<WorkspaceException>()),
    );
    expect(
      _controller.state.error,
      contains('The main workspace cannot be removed'),
    );
  });

  test('surfaces tab and layout failures in state', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final activeTab = _controller.state.activeWorkspaceTab!;

    _harness.workbenchRepository.upsertWorkspaceTabError = StateError(
      'cannot create tab',
    );
    await expectLater(
      _controller.createTerminalTab(workspace),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot create tab'));
    _harness.workbenchRepository.upsertWorkspaceTabError = null;

    _harness.workbenchRepository.removeWorkspaceTabError = StateError(
      'cannot close tab',
    );
    await expectLater(
      _controller.closeWorkspaceTabs(
        workspace: workspace,
        tabIds: <String>[activeTab.id],
      ),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot close tab'));
    _harness.workbenchRepository.removeWorkspaceTabError = null;

    await expectLater(
      _controller.renameWorkspaceTab(tabId: activeTab.id, title: '   '),
      throwsStateError,
    );
    expect(
      _controller.state.error,
      contains('Terminal title must not be empty'),
    );

    final firstGroupId = _controller.state
        .layoutFor(workspace.id)!
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: WorkbenchDropZone.right,
    );
    await _flush();

    final splitLayout = _controller.state.layoutFor(workspace.id)!;
    final splitGroupId = splitLayout.groupIdForTab(splitTab.id)!;
    final targetGroupId = splitLayout.paneGroupIds.firstWhere(
      (groupId) => groupId != splitGroupId,
    );

    _harness.workbenchRepository.upsertWorkbenchLayoutError = StateError(
      'cannot persist layout',
    );
    await expectLater(
      _controller.moveWorkspaceTab(
        workspaceId: workspace.id,
        tabId: splitTab.id,
        targetGroupId: targetGroupId,
        zone: WorkbenchDropZone.center,
      ),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot persist layout'));

    await expectLater(
      _controller.mergeWorkbenchGroupIntoSibling(
        workspaceId: workspace.id,
        groupId: splitGroupId,
      ),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot persist layout'));
    _harness.workbenchRepository.upsertWorkbenchLayoutError = null;

    await _controller.mergeWorkbenchGroupIntoSibling(
      workspaceId: workspace.id,
      groupId: splitGroupId,
    );
    await _flush();
    expect(_controller.state.error, isNull);

    _harness.workbenchRepository.upsertWorkspaceTabError = StateError(
      'cannot split tab',
    );
    await expectLater(
      _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: targetGroupId,
        zone: WorkbenchDropZone.down,
      ),
      throwsStateError,
    );
    expect(_controller.state.error, contains('cannot split tab'));
  });
}
