part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerNavigationTests() {
  test(
    'records worktree selection and replays back and forward safely',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
      expect(_controller.canGoBack, isFalse);
      expect(_controller.canGoForward, isFalse);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      expect(_controller.canGoBack, isFalse);

      final first = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/navigation-first',
      )).workspace;
      final second = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/navigation-second',
      )).workspace;
      expect(_controller.state.activeWorkspaceId, second.id);

      await _controller.goBack();
      expect(_controller.state.activeWorkspaceId, first.id);
      expect(_controller.canGoForward, isTrue);

      _controller.setSearchQuery('does-not-match');
      await _controller.goBack();
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
      expect(_controller.canGoForward, isTrue);

      await _controller.goForward();
      expect(_controller.state.activeWorkspaceId, first.id);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      expect(_controller.canGoForward, isFalse);
    },
  );

  test('skips deleted workspaces in navigation history', () async {
    await _controller.bootstrap();
    final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
    final removedWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-removed',
    )).workspace;
    final currentWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-current',
    )).workspace;

    await _harness.workbenchRepository.removeWorkspace(removedWorkspace.id);
    await _flushUntil(
      () => !_controller.state
          .workspacesFor(_harness.project.id)
          .any((workspace) => workspace.id == removedWorkspace.id),
    );

    expect(_controller.state.activeWorkspaceId, currentWorkspace.id);
    expect(_controller.canGoBack, isTrue);
    await _controller.goBack();
    expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
    expect(_controller.state.searchQuery, isEmpty);
  });

  test('prunes navigation entries when their project is removed', () async {
    await _controller.bootstrap();
    await _selectMainWorkspace(_controller, _harness);
    final secondWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-project',
    )).workspace;
    expect(_controller.state.activeWorkspaceId, secondWorkspace.id);

    final otherProject = await _harness.addProject('project-2', 'Other');
    await _flushUntil(
      () => _controller.state.projects.any(
        (project) => project.id == otherProject.id,
      ),
    );
    await _flushUntil(
      () => _controller.state.workspacesFor(otherProject.id).isNotEmpty,
    );
    final otherWorkspace = _controller.state
        .workspacesFor(otherProject.id)
        .single;
    await _controller.selectWorkspace(
      project: otherProject,
      workspace: otherWorkspace,
    );

    await _harness.projectRepository.remove(_harness.project.id);
    await _flushUntil(
      () => !_controller.state.projects.any(
        (project) => project.id == _harness.project.id,
      ),
    );

    expect(_controller.canGoBack, isFalse);
    expect(_controller.state.activeWorkspaceId, otherWorkspace.id);
  });
}
