part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSleepTests() {
  test(
    'sleep removes every tab and layout then deselects the workspace',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'notes.txt',
      );
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.kind),
        <WorkspaceTabKind>[WorkspaceTabKind.terminal, WorkspaceTabKind.editor],
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);

      await _controller.sleepWorkspace(workspace);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(_controller.state.activeTabIdByWorkspace[workspace.id], isNull);
      expect(_controller.state.activeWorkspace, isNull);
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
    },
  );
}
