part of 'agent_runtime_overlay_service_test.dart';

void _registerAmpRuntimeOverlayTests(
  Directory Function() readHome,
  AgentRuntimeOverlayService Function() readService,
) {
  test('creates an Amp overlay and wrapper', () async {
    final home = readHome();
    final ampConfig = Directory(p.join(home.path, '.config', 'amp'))
      ..createSync(recursive: true);
    File(
      p.join(ampConfig.path, 'settings.json'),
    ).writeAsStringSync('{"theme":"dark"}\n');
    final plugins = Directory(p.join(ampConfig.path, 'plugins'))..createSync();
    File(
      p.join(plugins.path, 'user-plugin.ts'),
    ).writeAsStringSync('export default function userPlugin() {}\n');
    File(
      p.join(plugins.path, 'alera-agent-status.ts'),
    ).writeAsStringSync('USER OWNED PLUGIN\n');

    final preparation = await readService().prepareAmpForTerminalLaunch(
      terminalSessionId: 'session-amp',
    );

    final ampOverlay = preparation.environment['ALERA_AMP_CONFIG_DIR']!;
    final wrapperPath = preparation.environment['ALERA_AGENT_WRAPPER_PATH']!;
    expect(preparation.sourcePath, ampConfig.path);
    expect(
      File(p.join(ampOverlay, 'settings.json')).readAsStringSync(),
      '{"theme":"dark"}\n',
    );
    expect(
      File(p.join(ampOverlay, 'plugins', 'user-plugin.ts')).readAsStringSync(),
      'export default function userPlugin() {}\n',
    );
    final statusPlugin = File(
      p.join(ampOverlay, 'plugins', 'alera-agent-status.ts'),
    ).readAsStringSync();
    expect(statusPlugin, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
    expect(statusPlugin, contains('/hook/amp'));
    expect(statusPlugin, contains('const MAX_PENDING_POSTS = 50'));
    expect(statusPlugin, contains("enqueuePost('agent.start'"));
    expect(
      File(p.join(plugins.path, 'alera-agent-status.ts')).readAsStringSync(),
      'USER OWNED PLUGIN\n',
    );
    final wrapper = File(p.join(wrapperPath, 'amp')).readAsStringSync();
    expect(wrapper, startsWith('#!/bin/sh'));
    expect(wrapper, contains('XDG_CONFIG_HOME'));
    expect(wrapper, contains('AMP_SETTINGS_FILE'));
    expect(wrapper, contains('command -v amp'));
  });
}
