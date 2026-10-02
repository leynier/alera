part of 'codex_runtime_home_service_test.dart';

void _registerCodexRuntimeHomeServiceRetryTests() {
  test('uses cmd runtime hooks on Windows', () async {
    final windowsService = CodexRuntimeHomeService(
      homeDirectory: home.path,
      applicationSupportDirectory: () async => support,
      platform: .windows,
      environment: <String, String>{'USERPROFILE': home.path},
    );

    final preparation = await windowsService.prepareForTerminalLaunch();

    final runtimeHooks = _hooks(
      p.join(preparation.runtimeHomePath, 'hooks.json'),
    );
    expect(_managedCommandCount(runtimeHooks, 'alera-codex-hook.cmd'), 6);
    final hookScript = File(
      p.join(home.path, '.alera', 'agent-hooks', 'alera-codex-hook.cmd'),
    );
    final hookSource = hookScript.readAsStringSync();
    expect(hookSource, contains('/hook/codex'));
    _expectWindowsHookRetryScript(hookScript);
  });
}
