part of 'managed_agent_hook_installer_test.dart';

void _registerGrokHookInstallerTests(
  Directory Function() readHome,
  ManagedAgentHookInstallService Function() readService,
) {
  test('installs and removes dedicated Grok Build hooks', () {
    final home = readHome();
    final service = readService();
    final configPath = p.join(home.path, '.grok', 'hooks', 'alera-status.json');
    _writeJson(configPath, <String, Object?>{
      'hooks': <String, Object?>{
        'UserPromptSubmit': <Object?>[
          <String, Object?>{
            'hooks': <Object?>[
              <String, Object?>{'type': 'command', 'command': 'echo user-hook'},
            ],
          },
        ],
      },
    });

    final installed = service.install(AgentType.grok);
    final hooks = _hooks(configPath);

    expect(installed.state, ManagedAgentHookInstallState.installed);
    expect(
      hooks.keys,
      containsAll(<String>[
        'SessionStart',
        'UserPromptSubmit',
        'PreToolUse',
        'PostToolUse',
        'PostToolUseFailure',
        'Notification',
        'Stop',
        'StopFailure',
        'SessionEnd',
      ]),
    );
    expect(_commandsFor(hooks, 'UserPromptSubmit'), contains('echo user-hook'));
    expect(_managedCommandCount(hooks, 'alera-grok-hook.sh'), 9);
    expect(
      File(p.join(home.path, '.alera', 'agent-hooks', 'alera-grok-hook.sh'))
          .readAsStringSync(),
      contains('/hook/grok'),
    );

    final removed = service.remove(AgentType.grok);
    expect(removed.state, ManagedAgentHookInstallState.notInstalled);
    expect(_commandsFor(_hooks(configPath), 'UserPromptSubmit'), <String>[
      'echo user-hook',
    ]);
  });

  test('uses a Windows-safe command for Grok Build hooks', () {
    final home = readHome();
    final windowsService = ManagedAgentHookInstallService(
      homeDirectory: p.join(home.path, 'Home With Spaces'),
      platform: ManagedAgentHookPlatform.windows,
      environment: <String, String>{'USERPROFILE': home.path},
    );

    final installed = windowsService.install(AgentType.grok);
    final hooks = _hooks(installed.configPath);

    expect(installed.state, ManagedAgentHookInstallState.installed);
    expect(
      _commandsFor(hooks, 'SessionStart').single,
      allOf(contains('cmd /d /s /c'), contains('ALERA_GROK_EVENT')),
    );
  });

  test('installs Grok Build hooks under GROK_HOME', () {
    final home = readHome();
    final grokHome = p.join(home.path, 'custom-grok-home');
    final customService = ManagedAgentHookInstallService(
      homeDirectory: home.path,
      platform: ManagedAgentHookPlatform.posix,
      environment: <String, String>{'HOME': home.path, 'GROK_HOME': grokHome},
    );

    final installed = customService.install(AgentType.grok);

    expect(
      installed.configPath,
      p.join(grokHome, 'hooks', 'alera-status.json'),
    );
    expect(installed.state, ManagedAgentHookInstallState.installed);
  });
}
