part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSourceControlContextTests() {
  test('selecting a folder workspace preserves source control and pull request tabs', () async {
    await _controller.bootstrap();
    final gitWorkspace = await _selectMainWorkspace(_controller, _harness);
    final folderPath = p.join(_harness.tempDir.path, 'notes');
    Directory(folderPath).createSync(recursive: true);
    final now = DateTime.utc(2026, 5, 22);
    final folderProject = Project(
      id: 'project-folder',
      name: 'Notes',
      repoPath: folderPath,
      createdAt: now,
      updatedAt: now,
      kind: .folder,
    );

    await _harness.seedInitialWorkspace(folderProject);
    await _harness.projectRepository.add(folderProject);
    await _flushUntil(
      () => _controller.state.workspacesFor(folderProject.id).isNotEmpty,
    );
    final folderWorkspace = _controller.state
        .workspacesFor(folderProject.id)
        .single;
    for (final tab in <WorkbenchContextPanelTab>[
      WorkbenchContextPanelTab.gitDiff,
      WorkbenchContextPanelTab.pullRequests,
    ]) {
      _controller.setContextPanelTab(tab);
      await _flush();

      await _controller.selectWorkspace(
        project: folderProject,
        workspace: folderWorkspace,
      );
      await _flush();

      expect(_controller.state.viewPrefs.activeContextPanelTab, tab);
      expect(_harness.viewPrefsRepository.prefs.activeContextPanelTab, tab);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: gitWorkspace,
      );
      await _flush();

      expect(_controller.state.viewPrefs.activeContextPanelTab, tab);
    }
  });

  test('selecting a git workspace keeps source control active', () async {
    await _controller.bootstrap();
    _controller.setContextPanelTab(.gitDiff);
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
        kind: .folder,
      );
      await _harness.seedInitialWorkspace(folderProject);
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
        WorkbenchContextPanelTab.gitDiff,
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
        kind: .folder,
      );
      await _harness.seedInitialWorkspace(folderProject);
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
        kind: .folder,
      );
      await _harness.seedInitialWorkspace(folderProject);
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
        kind: .folder,
      );
      await _harness.seedInitialWorkspace(folderProject);
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
}
