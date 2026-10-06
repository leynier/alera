part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerWorkspaceFocusTests() {
  test(
    'a focus request selects an existing workspace and keeps its tabs',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
      final other = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/focus-target',
      )).workspace;
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: other,
      );
      final otherTabIds = _controller.state
          .tabsFor(other.id)
          .map((tab) => tab.id)
          .toList();
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      final workbench = _ContainerWorkspaceFocusWorkbench(_harness.container);
      addTearDown(workbench.dispose);
      final window = _CountingWindowActivator();

      final selected = await WorkspaceFocusRequestHandler(
        windowActivator: window,
        workbench: workbench,
      ).focus(other.id);

      expect(selected, isTrue);
      expect(window.calls, 1);
      expect(_controller.state.activeWorkspaceId, other.id);
      expect(_controller.state.activeProjectId, _harness.project.id);
      expect(
        _controller.state.tabsFor(other.id).map((tab) => tab.id),
        otherTabIds,
        reason: 'focusing reuses the open terminals instead of adding one',
      );
      expect(
        _controller.state.workspacePanelFor(other.id).focusedKey,
        isNotNull,
      );
    },
  );

  test(
    'a focus request waits for a workspace the sidebar has not loaded yet',
    () async {
      await _controller.bootstrap();
      await _selectMainWorkspace(_controller, _harness);
      final workbench = _ContainerWorkspaceFocusWorkbench(_harness.container);
      addTearDown(workbench.dispose);
      final late = Workspace(
        id: 'registered-from-cli',
        projectId: _harness.project.id,
        name: 'Registered From CLI',
        branch: 'main',
        path: _harness.project.repoPath,
        createdAt: _harness.project.createdAt,
        updatedAt: _harness.project.updatedAt,
        kind: .linked,
        status: .active,
      );

      final pending = WorkspaceFocusRequestHandler(
        windowActivator: _CountingWindowActivator(),
        workbench: workbench,
      ).focus(late.id);
      await _flush();
      expect(_controller.state.activeWorkspaceId, isNot(late.id));
      await _harness.workbenchRepository.upsertWorkspace(late);

      expect(await pending, isTrue);
      expect(_controller.state.activeWorkspaceId, late.id);
    },
  );
}

class _ContainerWorkspaceFocusWorkbench implements WorkspaceFocusWorkbench {
  _ContainerWorkspaceFocusWorkbench(this._container) {
    _subscription = _container.listen<WorkbenchState>(
      workbenchControllerProvider,
      (_, next) => _changes.add(next),
    );
  }

  final ProviderContainer _container;
  final StreamController<WorkbenchState> _changes =
      StreamController<WorkbenchState>.broadcast();
  late final ProviderSubscription<WorkbenchState> _subscription;
  int overlayCloses = 0;

  @override
  WorkbenchState get state => _container.read(workbenchControllerProvider);

  @override
  Stream<WorkbenchState> get stateChanges => _changes.stream;

  @override
  void closeOverlays() => overlayCloses++;

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) => _container
      .read(workbenchControllerProvider.notifier)
      .selectWorkspace(project: project, workspace: workspace);

  Future<void> dispose() async {
    _subscription.close();
    await _changes.close();
  }
}

class _CountingWindowActivator implements AgentNotificationWindowActivator {
  int calls = 0;

  @override
  Future<void> showAndFocus() async => calls++;
}
