part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerWatcherRecoveryTests() {
  test(
    're-subscribes tabs after a watcher dies on a connection error',
    () async {
      // Regression for the permanent freeze reported under orchestration load:
      // a dead tab watcher used to stay in the subscription map forever, so new
      // terminals spawned into the workspace were never detected again.
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );
      final workspace = _controller.state
          .workspacesFor(_harness.project.id)
          .single;
      expect(_harness.workbenchRepository.hasTabWatcher(workspace.id), isTrue);

      _harness.workbenchRepository.killTabWatcher(workspace.id);
      await _flush();

      // Any workspace change re-runs the subscription pass; without the onDone
      // cleanup the `containsKey` guard would skip this workspace for good.
      await _harness.workbenchRepository.upsertWorkspace(workspace);
      await _flushUntil(
        () => _harness.workbenchRepository.hasTabWatcher(workspace.id),
      );

      await _harness.workbenchRepository.upsertWorkspaceTab(
        WorkspaceTabRecord(
          id: 'tab-after-recovery',
          workspaceId: workspace.id,
          title: 'Terminal 1',
          createdAt: .utc(2026, 5, 22),
          updatedAt: .utc(2026, 5, 22),
        ),
      );
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == 'tab-after-recovery'),
      );

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        contains('tab-after-recovery'),
      );
    },
  );
}
