part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerExplorerRevealTests() {
  test('revealInExplorer switches to explorer and queues the path', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setContextPanelTab(.gitDiff);
    await _flush();

    _controller.revealInExplorer(
      workspace: workspace,
      relativePath: 'lib/src/dirty.dart',
    );
    await _flush();

    expect(
      _controller.state.viewPrefs.activeContextPanelTab,
      WorkbenchContextPanelTab.explorer,
    );
    expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);
    final request = _harness.container.read(
      workspaceExplorerRevealControllerProvider,
    );
    expect(request?.workspaceId, workspace.id);
    expect(request?.relativePath, 'lib/src/dirty.dart');
  });
}
