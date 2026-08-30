part of 'managed_agent_hook_installer_test.dart';

void _registerAgyHookInstallerTests(
  Directory Function() readHome,
  ManagedAgentHookInstallService Function() readService,
) {
  String agyConfigPath(Directory home) {
    return p.join(home.path, '.gemini', 'config', 'hooks.json');
  }

  Map<String, Object?> agyBundle(Directory home) {
    return Map<String, Object?>.from(
      _readJson(agyConfigPath(home))['alera-status'] as Map,
    );
  }

  test('installs AGY hooks in the Gemini global hooks bundle', () {
    final home = readHome();
    final service = readService();
    final configPath = agyConfigPath(home);
    _writeJson(configPath, <String, Object?>{
      'user-hook': <String, Object?>{
        'PreInvocation': <Object?>[
          <String, Object?>{'type': 'command', 'command': 'echo user'},
        ],
      },
      'alera-status': <String, Object?>{
        'PreInvocation': <Object?>[
          <String, Object?>{'type': 'command', 'command': 'echo alera-extra'},
        ],
        'PreToolUse': <Object?>[
          <String, Object?>{
            'matcher': '*',
            'hooks': <Object?>[
              <String, Object?>{
                'type': 'command',
                'command': '/tmp/agent-hooks/alera-agy-hook.sh',
              },
            ],
          },
        ],
      },
    });

    final status = service.install(AgentType.agy);
    final config = _readJson(configPath);
    final bundle = agyBundle(home);

    expect(status.state, ManagedAgentHookInstallState.installed);
    expect(config['user-hook'], isNotNull);
    expect(
      bundle.keys,
      containsAll(<String>[
        'PreInvocation',
        'PostInvocation',
        'PostToolUse',
        'Stop',
      ]),
    );
    // AGY requires a permission `decision` from PreToolUse, so Alera stays out
    // of that event.
    expect(bundle['PreToolUse'], isNull);
    expect(
      _commandsFor(bundle, 'PreInvocation'),
      containsAll(<String>['echo alera-extra']),
    );
    expect(
      _commandsFor(bundle, 'PreInvocation').last,
      contains('ALERA_AGY_EVENT'),
    );
    // Lifecycle events must be flat `{ type, command }` (AGY does not run
    // the nested Claude-style `{ hooks: [...] }` shape for PreInvocation).
    final preInvocation = (bundle['PreInvocation'] as List).last as Map;
    expect(preInvocation['type'], 'command');
    expect(preInvocation['command'], contains('ALERA_AGY_EVENT'));
    expect(preInvocation.containsKey('hooks'), isFalse);
    expect(preInvocation['timeout'], 10);
    final postToolUse = (bundle['PostToolUse'] as List).single as Map;
    expect(postToolUse['matcher'], '*');
    expect(postToolUse['hooks'], isA<List>());
    final postToolUseHandler = (postToolUse['hooks'] as List).single as Map;
    expect(postToolUseHandler['type'], 'command');
    // Without this the handler inherits AGY's documented 30s default while its
    // three lifecycle siblings cap at 10.
    expect(postToolUseHandler['timeout'], 10);
    expect(
      _commandsFor(bundle, 'PostToolUse').single,
      contains('alera-agy-hook.sh'),
    );
    final script = File(
      p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-hook.sh'),
    ).readAsStringSync();
    expect(script, contains('/hook/agy'));
    expect(script, contains(r'case "$ALERA_AGY_EVENT" in'));
    expect(script, contains("payload='{}'"));
    expect(script, contains('payload@-'));
    // Empty stdin must still post the lifecycle event name.
    expect(script, isNot(contains('*)\n      exit 0')));
  });

  test('replaces the runtime AGY handler instead of stacking beside it', () {
    final home = readHome();
    final service = readService();
    final configPath = agyConfigPath(home);
    _writeJson(configPath, <String, Object?>{
      'alera-status': <String, Object?>{
        'Stop': <Object?>[
          <String, Object?>{
            'type': 'command',
            'command':
                "ALERA_AGENT_TYPE='agy' ALERA_AGENT_HOOK_EVENT='Stop' "
                "/bin/sh '${home.path}/.alera/agent-hooks/alera-runtime-agent-hook.sh'",
            'timeout': 10,
          },
        ],
      },
    });

    service.install(AgentType.agy);

    // Both installers write this bundle; two handlers would post every event
    // twice.
    expect(_commandsFor(agyBundle(home), 'Stop'), hasLength(1));
    expect(
      _commandsFor(agyBundle(home), 'Stop').single,
      contains('alera-agy-hook.sh'),
    );
  });

  test('reports a disabled AGY bundle as partial', () {
    final home = readHome();
    final service = readService();
    service.install(AgentType.agy);
    final configPath = agyConfigPath(home);
    final config = _readJson(configPath);
    final bundle = agyBundle(home)..['enabled'] = false;
    config['alera-status'] = bundle;
    _writeJson(configPath, config);

    final status = service.status(AgentType.agy);

    expect(status.state, ManagedAgentHookInstallState.partial);
    expect(status.managedHooksPresent, isTrue);
    expect(status.detail, contains('disabled'));
  });

  test('clears a disabled AGY bundle flag on install', () {
    final home = readHome();
    final service = readService();
    final configPath = agyConfigPath(home);
    _writeJson(configPath, <String, Object?>{
      'alera-status': <String, Object?>{
        'enabled': false,
        'note': 'kept by the user',
      },
    });

    final status = service.install(AgentType.agy);
    final bundle = agyBundle(home);

    expect(status.state, ManagedAgentHookInstallState.installed);
    expect(bundle.containsKey('enabled'), isFalse);
    expect(bundle['note'], 'kept by the user');
  });

  test('installs AGY wrapper scripts on Windows', () {
    final home = readHome();
    final windowsService = ManagedAgentHookInstallService(
      homeDirectory: home.path,
      platform: ManagedAgentHookPlatform.windows,
      environment: <String, String>{'USERPROFILE': home.path},
    );

    final status = windowsService.install(AgentType.agy);
    final bundle = agyBundle(home);

    expect(status.state, ManagedAgentHookInstallState.installed);
    final stopCommand = _commandsFor(bundle, 'Stop').single;
    expect(stopCommand, contains('alera-agy-stop.cmd'));
    // Quoted so a profile path containing a space survives cmd's tokenizer.
    expect(stopCommand.startsWith('"'), isTrue);
    expect(stopCommand.endsWith('"'), isTrue);
    expect(
      File(p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-stop.cmd'))
          .readAsStringSync(),
      contains('ALERA_AGY_EVENT=Stop'),
    );
    expect(
      File(p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-hook.cmd'))
          .readAsStringSync(),
      allOf(
        contains('/hook/agy'),
        contains(
          r'if ([string]::IsNullOrWhiteSpace($inputData)) { $payload=@{} }',
        ),
      ),
    );
  });

  test('removes only Alera-managed AGY bundle entries', () {
    final home = readHome();
    final service = readService();
    service.install(AgentType.agy);
    final configPath = agyConfigPath(home);
    final config = _readJson(configPath);
    final bundle = agyBundle(home);
    bundle['PreInvocation'] = <Object?>[
      <String, Object?>{'type': 'command', 'command': 'echo user'},
      ...(bundle['PreInvocation'] as List),
    ];
    config['alera-status'] = bundle;
    _writeJson(configPath, config);

    final status = service.remove(AgentType.agy);
    final next = _readJson(configPath);
    final nextBundle = Map<String, Object?>.from(next['alera-status'] as Map);

    expect(status.state, ManagedAgentHookInstallState.notInstalled);
    expect(_commandsFor(nextBundle, 'PreInvocation'), <String>['echo user']);
    expect(nextBundle['Stop'], isNull);
  });

  test('removes empty AGY bundles after deleting managed commands', () {
    final home = readHome();
    final service = readService();
    service.install(AgentType.agy);

    final status = service.remove(AgentType.agy);
    final config = _readJson(agyConfigPath(home));

    expect(status.state, ManagedAgentHookInstallState.notInstalled);
    expect(config.containsKey('alera-status'), isFalse);
  });

  test('drops an AGY bundle left holding only the enabled flag', () {
    final home = readHome();
    final service = readService();
    service.install(AgentType.agy);
    final configPath = agyConfigPath(home);
    final config = _readJson(configPath);
    config['alera-status'] = agyBundle(home)..['enabled'] = false;
    _writeJson(configPath, config);

    service.remove(AgentType.agy);

    expect(_readJson(configPath).containsKey('alera-status'), isFalse);
  });
}
