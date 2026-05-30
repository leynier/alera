part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerFailureTests() {
  test(
    'activates projects and tabs without unnecessary state changes',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      await _flush();

      final beforeNoOpClose = _controller.state;
      await _controller.closeWorkspaceTabs(
        workspace: workspace,
        tabIds: const [],
      );
      expect(_controller.state, same(beforeNoOpClose));

      await _controller.activateProject(_harness.project);
      expect(_controller.state.activeProjectId, _harness.project.id);
      expect(_controller.state.activeWorkspace, isNull);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      await _flush();

      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.activeTabIdByWorkspace[workspace.id],
        firstTab.id,
      );
      expect(
        _controller.state.layoutFor(workspace.id)?.activeTabId,
        firstTab.id,
      );

      final groupId = _controller.state
          .layoutFor(workspace.id)!
          .groupIdForTab(secondTab.id)!;
      _controller.setActiveWorkspaceTab(
        workspaceId: workspace.id,
        groupId: groupId,
        tabId: secondTab.id,
      );
      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.activeTabIdByWorkspace[workspace.id],
        secondTab.id,
      );
      expect(
        _controller.state.layoutFor(workspace.id)?.activeTabId,
        secondTab.id,
      );
      expect(_controller.state.layoutFor(workspace.id)?.activeGroupId, groupId);

      await _controller.moveWorkspaceTab(
        workspaceId: workspace.id,
        tabId: secondTab.id,
        targetGroupId: groupId,
        zone: WorkbenchDropZone.right,
      );
      final splitLayout = _controller.state.layoutFor(workspace.id)!;
      final firstGroupId = splitLayout.groupIdForTab(firstTab.id)!;
      _controller.focusWorkbenchGroup(
        workspaceId: workspace.id,
        groupId: firstGroupId,
      );
      await _flush();
      expect(
        _controller.state.layoutFor(workspace.id)?.activeGroupId,
        firstGroupId,
      );
      _controller.focusWorkbenchGroup(
        workspaceId: 'missing-workspace',
        groupId: firstGroupId,
      );
    },
  );

  test('view-pref no-op mutators avoid redundant persistence', () async {
    await _controller.bootstrap();

    final initialSaveCount = _harness.viewPrefsRepository.saveCount;
    _controller.setGroupBy(_controller.state.viewPrefs.groupBy);
    _controller.setProjectSort(_controller.state.viewPrefs.projectSort);
    _controller.setWorkspaceSort(_controller.state.viewPrefs.workspaceSort);
    _controller.removeProjectFilter('missing-project');
    _controller.clearProjectFilters();
    await _flush();
    expect(_harness.viewPrefsRepository.saveCount, initialSaveCount);

    _controller.addProjectFilter(_harness.project.id);
    await _flush();
    final afterAddFilter = _harness.viewPrefsRepository.saveCount;

    _controller.addProjectFilter(_harness.project.id);
    await _flush();
    expect(_harness.viewPrefsRepository.saveCount, afterAddFilter);

    _controller.clearProjectFilters();
    await _flush();
    final afterClear = _harness.viewPrefsRepository.saveCount;

    _controller.clearProjectFilters();
    await _flush();
    expect(_harness.viewPrefsRepository.saveCount, afterClear);
  });

  test('addProject and cloneProject activate newly added projects', () async {
    await _controller.bootstrap();

    final localRepoPath = p.join(_harness.tempDir.path, 'repo-added');
    Directory(localRepoPath).createSync(recursive: true);
    Directory(p.join(localRepoPath, '.git')).createSync();

    final localProject = await _controller.addProject(
      repoPath: localRepoPath,
      name: 'Added repo',
    );
    await _flushUntil(
      () => _controller.state.projects.any(
        (project) => project.id == localProject.id,
      ),
    );
    await _flushUntil(
      () => _controller.state.workspacesFor(localProject.id).isNotEmpty,
    );

    expect(_controller.state.activeProjectId, localProject.id);
    expect(
      _controller.state.workspacesFor(localProject.id).single.isMain,
      isTrue,
    );

    _harness.gitBackend.onClone = (_, destination) =>
        Directory(p.join(destination, '.git')).createSync(recursive: true);
    final cloneDestination = p.join(_harness.tempDir.path, 'repo-cloned');
    final clonedProject = await _controller.cloneProject(
      gitUrl: 'https://example.com/acme/alera.git',
      destinationPath: cloneDestination,
      name: 'Cloned repo',
    );
    await _flushUntil(
      () => _controller.state.projects.any(
        (project) => project.id == clonedProject.id,
      ),
    );
    await _flushUntil(
      () => _controller.state.workspacesFor(clonedProject.id).isNotEmpty,
    );

    expect(_controller.state.activeProjectId, clonedProject.id);
    expect(
      _controller.state.workspacesFor(clonedProject.id).single.isMain,
      isTrue,
    );
  });

  test('project and workspace toggle helpers cover removal branches', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    _controller.toggleProjectCollapsed(_harness.project.id);
    expect(
      _controller.state.viewPrefs.collapsedProjectIds,
      contains(_harness.project.id),
    );
    _controller.toggleProjectCollapsed(_harness.project.id);
    expect(
      _controller.state.viewPrefs.collapsedProjectIds,
      isNot(contains(_harness.project.id)),
    );

    _controller.toggleProjectFilter(_harness.project.id);
    expect(
      _controller.state.viewPrefs.selectedProjectIds,
      contains(_harness.project.id),
    );
    _controller.removeProjectFilter(_harness.project.id);
    expect(_controller.state.viewPrefs.selectedProjectIds, isEmpty);

    _controller.setWorkspaceExpanded(workspace.id, false);
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(workspace.id)),
    );
    _controller.setWorkspaceExpanded(workspace.id, true);
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      contains(workspace.id),
    );
    _controller.toggleWorkspaceExpanded(workspace.id);
    expect(
      _controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(workspace.id)),
    );
  });

  test(
    'removing a project prunes its workspaces, tabs, and selections',
    () async {
      await _controller.bootstrap();
      final secondProject = await _harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => _controller.state.workspacesFor(secondProject.id).isNotEmpty,
      );

      final secondWorkspace = _controller.state
          .workspacesFor(secondProject.id)
          .single;
      await _controller.selectWorkspace(
        project: secondProject,
        workspace: secondWorkspace,
      );
      await _flush();

      expect(_controller.state.tabsFor(secondWorkspace.id), isNotEmpty);
      expect(
        _controller.state.activeTabIdByWorkspace.containsKey(
          secondWorkspace.id,
        ),
        isTrue,
      );

      await _controller.removeProject(secondProject.id);
      await _flush();

      expect(
        _controller.state.projects.map((project) => project.id),
        isNot(contains(secondProject.id)),
      );
      expect(
        _controller.state.workspacesByProject.containsKey(secondProject.id),
        isFalse,
      );
      expect(
        _controller.state.tabsByWorkspace.containsKey(secondWorkspace.id),
        isFalse,
      );
      expect(
        _controller.state.activeTabIdByWorkspace.containsKey(
          secondWorkspace.id,
        ),
        isFalse,
      );
      expect(_controller.state.error, isNull);
    },
  );

  test('bootstrap surfaces workspace preparation failures', () async {
    _harness.workbenchRepository.upsertWorkspaceError = StateError(
      'cannot prepare workspace',
    );

    await _controller.bootstrap();
    await _flush();

    expect(
      _controller.state.error,
      contains('Failed to prepare workspace for "Alera"'),
    );
  });

  test(
    'reactivating an existing project clears stale collapsed prefs',
    () async {
      await _controller.bootstrap();
      final secondProject = await _harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => _controller.state.projects.any(
          (project) => project.id == secondProject.id,
        ),
      );

      _controller.state = _controller.state.copyWith(
        viewPrefs: _controller.state.viewPrefs.copyWith(
          collapsedProjectIds: <String>{secondProject.id},
        ),
      );

      final project = await _controller.addProject(
        repoPath: secondProject.repoPath,
      );
      await _flush();

      expect(project.id, secondProject.id);
      expect(
        _controller.state.viewPrefs.collapsedProjectIds,
        isNot(contains(secondProject.id)),
      );
      expect(
        _harness.viewPrefsRepository.prefs.collapsedProjectIds,
        isNot(contains(secondProject.id)),
      );
    },
  );

  test(
    'workspace watchers recover invalid selections and surface layout load failures',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final secondProject = await _harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => _controller.state.workspacesFor(secondProject.id).isNotEmpty,
      );
      final secondWorkspace = _controller.state
          .workspacesFor(secondProject.id)
          .single;

      _controller.state = _controller.state.copyWith(
        activeProjectId: 'missing-project',
        activeWorkspaceId: secondWorkspace.id,
      );
      await _harness.workbenchRepository.upsertWorkspace(
        secondWorkspace.copyWith(updatedAt: DateTime.utc(2026, 5, 23)),
      );
      await _flush();

      expect(_controller.state.activeProjectId, secondProject.id);

      _controller.state = _controller.state.copyWith(
        activeProjectId: null,
        activeWorkspaceId: secondWorkspace.id,
      );
      await _harness.workbenchRepository.upsertWorkspace(
        secondWorkspace.copyWith(updatedAt: DateTime.utc(2026, 5, 24)),
      );
      await _flush();

      expect(_controller.state.activeWorkspaceId, secondWorkspace.id);

      _controller.state = _controller.state.copyWith(
        activeProjectId: workspace.projectId,
        activeWorkspaceId: workspace.id,
        layoutByWorkspace: <String, WorkbenchLayout>{},
      );
      _harness.workbenchRepository.upsertWorkbenchLayoutError = StateError(
        'bad layout',
      );
      _harness.workbenchRepository.emitTabs(workspace.id);
      await _flushUntil(() => _controller.state.error != null);
      _harness.workbenchRepository.upsertWorkbenchLayoutError = null;

      expect(_controller.state.error, contains('bad layout'));
      expect(_controller.state.activeWorkspaceId, workspace.id);
    },
  );

  test('tab operations fall back when no layout exists', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final existingTab = _controller.state.activeWorkspaceTab!;

    _controller.state = _controller.state.copyWith(
      layoutByWorkspace: <String, WorkbenchLayout>{},
      activeTabIdByWorkspace: <String, String>{},
    );

    _controller.setActiveTab(workspaceId: workspace.id, tabId: existingTab.id);
    await _flush();

    expect(
      _controller.state.activeTabIdByWorkspace[workspace.id],
      existingTab.id,
    );

    final newTab = await _controller.createTerminalTab(workspace);
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), contains(newTab));
    expect(_controller.state.layoutFor(workspace.id), isNotNull);
  });
}
