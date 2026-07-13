part of 'managed_agent_hook_installer_test.dart';

void _registerAmpHookInstallerTests(
  Directory Function() readHome,
  ManagedAgentHookInstallService Function() readService,
) {
  test('installs and removes the managed Amp system plugin', () {
    final home = readHome();
    final service = readService();
    final pluginPath = p.join(
      home.path,
      '.config',
      'amp',
      'plugins',
      'alera-agent-status.ts',
    );

    expect(
      service.status(AgentType.amp).state,
      ManagedAgentHookInstallState.notInstalled,
    );
    expect(
      service.install(AgentType.amp).state,
      ManagedAgentHookInstallState.installed,
    );

    final source = File(pluginPath).readAsStringSync();
    expect(source, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
    expect(source, contains("amp.on('agent.start'"));
    expect(source, contains("amp.on('tool.call'"));
    expect(source, contains("return { action: 'allow' }"));
    expect(source, contains('const MAX_PENDING_POSTS = 50'));
    expect(source, contains('function enqueuePost'));
    expect(source, contains("enqueuePost('agent.start'"));
    expect(source, contains('threadId: event?.thread?.id'));
    expect(source, isNot(contains("await post('agent.start'")));
    expect(source, contains('/hook/amp'));
    expect(source, contains('ALERA_AGENT_HOOK_ENDPOINT'));

    File(pluginPath).writeAsStringSync(
      '// ALERA_AGENT_STATUS_MANAGED_FILE\n'
      'export default function staleAmpPlugin() {}\n',
    );
    expect(
      service.status(AgentType.amp).state,
      ManagedAgentHookInstallState.partial,
    );
    expect(
      service.install(AgentType.amp).state,
      ManagedAgentHookInstallState.installed,
    );

    final removed = service.remove(AgentType.amp);
    expect(removed.state, ManagedAgentHookInstallState.notInstalled);
    expect(File(pluginPath).existsSync(), isFalse);
  });
}
