part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerPinningTests() {
  test('updates workspace pin state immediately', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    await _controller.setWorkspacePinned(
      workspaceId: workspace.id,
      isPinned: true,
    );

    expect(_controller.state.activeWorkspace?.isPinned, isTrue);
    expect(_controller.state.error, isNull);
  });

  test('surfaces workspace pin failures without changing state', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _harness.workbenchRepository.upsertWorkspaceError = StateError(
      'pin failed',
    );

    await expectLater(
      _controller.setWorkspacePinned(workspaceId: workspace.id, isPinned: true),
      throwsStateError,
    );

    expect(_controller.state.activeWorkspace?.isPinned, isFalse);
    expect(_controller.state.error, contains('pin failed'));
  });
}
