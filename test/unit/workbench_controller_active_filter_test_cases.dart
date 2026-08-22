part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerActiveFilterTests() {
  test('active workspace filter updates state and persists', () async {
    await _controller.bootstrap();

    _controller.setShowActiveWorkspacesOnly(true);
    await _flush();

    expect(_controller.state.viewPrefs.showActiveWorkspacesOnly, isTrue);
    expect(_harness.viewPrefsRepository.prefs.showActiveWorkspacesOnly, isTrue);
  });
}
