part of 'codex_runtime_home_service_test.dart';

void _registerCodexRuntimeHomeServiceCoreTests() {
  test('prepares a runtime home without mutating user hooks', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'PreToolUse': <Object?>[_userHook('echo user-hook')],
      },
    });
    File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[features]\ncodex_hooks = true\n');

    final preparation = await service.prepareForTerminalLaunch();

    expect(
      preparation.environment['CODEX_HOME'],
      p.join(support.path, 'agent-runtime-homes', 'codex', 'home'),
    );
    expect(
      preparation.environment['ALERA_CODEX_HOME'],
      preparation.runtimeHomePath,
    );
    expect(
      preparation.hookStatus.state,
      ManagedAgentHookInstallState.installed,
    );

    final systemHooks = _hooks(systemHooksPath);
    expect(_commandsFor(systemHooks, 'PreToolUse'), <String>['echo user-hook']);
    expect(_managedCommandCount(systemHooks, 'alera-codex-hook.sh'), 0);

    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final runtimeHooks = _hooks(runtimeHooksPath);
    expect(
      _commandsFor(runtimeHooks, 'PreToolUse'),
      contains('echo user-hook'),
    );
    expect(_managedCommandCount(runtimeHooks, 'alera-codex-hook.sh'), 6);
    expect(
      File(
        p.join(home.path, '.alera', 'agent-hooks', 'alera-codex-hook.sh'),
      ).existsSync(),
      isTrue,
    );

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('hooks = true'));
    expect(runtimeToml, isNot(contains('codex_hooks')));
    expect(runtimeToml, contains(':session_start:0:0"]'));
    expect(runtimeToml, contains('trusted_hash = "sha256:'));
  });

  test('skips plugin-only hooks when mirroring user Codex hooks', () async {
    const pluginCommands = <String>[
      r'node "${CLAUDE_PLUGIN_ROOT}/scripts/on-stop.mjs"',
      r'node "${CLAUDE_PLUGIN_DATA}/scripts/on-stop.mjs"',
      r'node "${PLUGIN_ROOT}/scripts/on-stop.mjs"',
      r'node "${PLUGIN_DATA}/scripts/on-stop.mjs"',
    ];
    const userCommand = 'echo normal-user-hook';
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'Stop': <Object?>[
          _userHookCommands(<String>[...pluginCommands, userCommand]),
        ],
        'PreCompact': <Object?>[
          for (final command in pluginCommands) _userHook(command),
        ],
      },
    });
    final canonicalSystemHooksPath = File(
      systemHooksPath,
    ).resolveSymbolicLinksSync();
    final pluginTrustedHashes = <String>[
      for (var index = 0; index < pluginCommands.length; index++)
        computeCodexTrustedHashForTesting(
          sourcePath: systemHooksPath,
          eventLabel: 'stop',
          groupIndex: 0,
          handlerIndex: index,
          command: pluginCommands[index],
        ),
    ];
    final systemConfig = File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true);
    systemConfig.writeAsStringSync(
      <String>[
        for (var index = 0; index < pluginCommands.length; index++)
          _trustBlock(
            key: '$canonicalSystemHooksPath:stop:0:$index',
            enabled: true,
            trustedHash: pluginTrustedHashes[index],
          ),
        _trustBlock(
          key: '$canonicalSystemHooksPath:stop:0:${pluginCommands.length}',
          enabled: true,
          trustedHash: computeCodexTrustedHashForTesting(
            sourcePath: systemHooksPath,
            eventLabel: 'stop',
            groupIndex: 0,
            handlerIndex: pluginCommands.length,
            command: userCommand,
          ),
        ),
      ].join('\n'),
    );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final runtimeHooksText = File(runtimeHooksPath).readAsStringSync();
    final runtimeHooks = _hooks(runtimeHooksPath);
    expect(_commandsFor(runtimeHooks, 'Stop'), contains(userCommand));
    expect(_commandsFor(runtimeHooks, 'PreCompact'), isEmpty);
    expect(_managedCommandCount(runtimeHooks, 'alera-codex-hook.sh'), 6);
    for (final command in pluginCommands) {
      expect(runtimeHooksText, isNot(contains(command)));
    }

    final canonicalRuntimeHooksPath = File(
      runtimeHooksPath,
    ).resolveSymbolicLinksSync();
    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(
      runtimeToml,
      contains(
        '[hooks.state."${_escapeTomlString('$canonicalRuntimeHooksPath:stop:0:0')}"]',
      ),
    );
    expect(
      runtimeToml,
      isNot(
        contains(
          '[hooks.state."${_escapeTomlString('$canonicalRuntimeHooksPath:stop:0:1')}"]',
        ),
      ),
    );
    for (final command in pluginCommands) {
      expect(runtimeToml, isNot(contains(command)));
    }
    for (final hash in pluginTrustedHashes) {
      expect(runtimeToml, isNot(contains(hash)));
      expect(systemConfig.readAsStringSync(), contains(hash));
    }

    final systemHooks = _hooks(systemHooksPath);
    for (final command in pluginCommands) {
      expect(_commandsFor(systemHooks, 'Stop'), contains(command));
    }
  });

  test('mirrors trusted user hooks when system trust indices are stale', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'Stop': <Object?>[
          _userHook('first-stop-hook'),
          _userHook('second-stop-hook'),
        ],
      },
    });
    final canonicalSystemHooksPath = File(
      systemHooksPath,
    ).resolveSymbolicLinksSync();
    File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        <String>[
          _trustBlock(
            key: '$canonicalSystemHooksPath:stop:0:0',
            enabled: true,
            trustedHash: computeCodexTrustedHashForTesting(
              sourcePath: systemHooksPath,
              eventLabel: 'stop',
              groupIndex: 1,
              handlerIndex: 0,
              command: 'second-stop-hook',
            ),
          ),
          _trustBlock(
            key: '$canonicalSystemHooksPath:stop:1:0',
            enabled: true,
            trustedHash: computeCodexTrustedHashForTesting(
              sourcePath: systemHooksPath,
              eventLabel: 'stop',
              groupIndex: 0,
              handlerIndex: 0,
              command: 'first-stop-hook',
            ),
          ),
        ].join('\n'),
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final canonicalRuntimeHooksPath = File(
      runtimeHooksPath,
    ).resolveSymbolicLinksSync();
    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(
      runtimeToml,
      contains(
        '[hooks.state."${_escapeTomlString('$canonicalRuntimeHooksPath:stop:0:0')}"]',
      ),
    );
    expect(
      runtimeToml,
      contains(
        '[hooks.state."${_escapeTomlString('$canonicalRuntimeHooksPath:stop:1:0')}"]',
      ),
    );
    expect(runtimeToml, isNot(contains('$canonicalSystemHooksPath:stop:0:0')));
    expect(runtimeToml, isNot(contains('$canonicalSystemHooksPath:stop:1:0')));
  });

  test('enables hooks in a fresh runtime config', () async {
    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('[features]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(
      File(p.join(home.path, '.codex', 'config.toml')).existsSync(),
      isFalse,
    );
  });

  test(
    'inserts hooks into existing feature sections before trailing blanks',
    () async {
      File(p.join(home.path, '.codex', 'config.toml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '[features]\n\n[projects."/repo"]\ntrust_level = "trusted"\n',
        );

      final preparation = await service.prepareForTerminalLaunch();

      final runtimeToml = File(
        p.join(preparation.runtimeHomePath, 'config.toml'),
      ).readAsStringSync();
      expect(runtimeToml, contains('[features]\nhooks = true\n\n[projects.'));
    },
  );

  test('mirrors trust metadata with optional hook fields', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    const userCommand = 'echo rich-user-hook';
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'PreToolUse': <Object?>[
          <String, Object?>{
            'matcher': 'Bash',
            'hooks': <Object?>[
              <String, Object?>{
                'type': 'command',
                'command': userCommand,
                'timeout': 1 << 32,
                'async': true,
                'statusMessage': 'Running Bash hook',
              },
            ],
          },
          <String, Object?>{'hooks': 'not-a-list'},
        ],
        'PreCompact': 'not-a-list',
      },
    });
    final canonicalSystemHooksPath = File(
      systemHooksPath,
    ).resolveSymbolicLinksSync();
    final systemTrustKey = '$canonicalSystemHooksPath:pre_tool_use:0:0';
    final trustedHash = computeCodexTrustedHashForTesting(
      sourcePath: systemHooksPath,
      eventLabel: 'pre_tool_use',
      groupIndex: 0,
      handlerIndex: 0,
      command: userCommand,
      timeoutSec: 1 << 32,
      async: true,
      matcher: 'Bash',
      statusMessage: 'Running Bash hook',
    );
    File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        _trustBlock(
          key: systemTrustKey,
          enabled: true,
          trustedHash: trustedHash,
        ),
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('trusted_hash = "$trustedHash"'));
  });

  test('reports not installed before runtime hooks exist', () async {
    final status = await service.status();

    expect(status.state, ManagedAgentHookInstallState.notInstalled);
    expect(status.managedHooksPresent, isFalse);
    expect(
      status.configPath,
      p.join(
        support.path,
        'agent-runtime-homes',
        'codex',
        'home',
        'hooks.json',
      ),
    );
  });

  test('reports invalid runtime hooks as an error', () async {
    final runtimeHooksPath = p.join(
      support.path,
      'agent-runtime-homes',
      'codex',
      'home',
      'hooks.json',
    );
    File(runtimeHooksPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');

    final status = await service.status();
    final installStatus = await service.install();
    final removeStatus = await service.remove();

    expect(status.state, ManagedAgentHookInstallState.error);
    expect(installStatus.state, ManagedAgentHookInstallState.error);
    expect(removeStatus.state, ManagedAgentHookInstallState.error);
    expect(status.configPath, runtimeHooksPath);
    expect(installStatus.configPath, runtimeHooksPath);
    expect(removeStatus.configPath, runtimeHooksPath);
  });

  test('remove preserves user runtime hooks beside managed commands', () async {
    final preparation = await service.prepareForTerminalLaunch();
    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final config = _readJson(runtimeHooksPath);
    final hooks = Map<String, Object?>.from(config['hooks'] as Map);
    hooks['Stop'] = <Object?>[
      _userHook('echo user stop'),
      ...(hooks['Stop'] as List? ?? const <Object?>[]),
    ];
    config['hooks'] = hooks;
    _writeJson(runtimeHooksPath, config);

    final status = await service.remove();
    final nextHooks = _hooks(runtimeHooksPath);

    expect(status.state, ManagedAgentHookInstallState.notInstalled);
    expect(_commandsFor(nextHooks, 'Stop'), <String>['echo user stop']);
  });

  test('enables hooks in runtime without mutating user config', () async {
    final systemConfig = File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('model = "gpt-5"\n');

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('model = "gpt-5"'));
    expect(runtimeToml, contains('[features]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(systemConfig.readAsStringSync(), 'model = "gpt-5"\n');
  });

  test('overrides disabled hooks only in runtime config', () async {
    final systemConfig = File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[features]\nhooks = false\n');

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('[features]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(runtimeToml, isNot(contains('hooks = false')));
    expect(systemConfig.readAsStringSync(), '[features]\nhooks = false\n');
  });

  test(
    'reports partial status for missing and disabled managed hooks',
    () async {
      final preparation = await service.prepareForTerminalLaunch();
      final runtimeHooksPath = p.join(
        preparation.runtimeHomePath,
        'hooks.json',
      );
      final runtimeConfig = _readJson(runtimeHooksPath);
      final runtimeHooks = Map<String, Object?>.from(
        runtimeConfig['hooks'] as Map,
      );
      runtimeHooks.remove('Stop');
      runtimeConfig['hooks'] = runtimeHooks;
      _writeJson(runtimeHooksPath, runtimeConfig);

      final runtimeToml = File(
        p.join(preparation.runtimeHomePath, 'config.toml'),
      );
      runtimeToml.writeAsStringSync(
        runtimeToml.readAsStringSync().replaceFirst(
          'enabled = true',
          'enabled = false',
        ),
      );

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.managedHooksPresent, isTrue);
      expect(status.detail, contains('Managed hook missing for events: Stop.'));
      expect(status.detail, contains('Managed hook disabled for events:'));
    },
  );

  test(
    'reports partial status when runtime trust entries are missing',
    () async {
      final preparation = await service.prepareForTerminalLaunch();
      File(p.join(preparation.runtimeHomePath, 'config.toml')).deleteSync();

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.detail, contains('Trust entry missing for events:'));
    },
  );

  test('remove deletes managed runtime hooks and trust entries', () async {
    final preparation = await service.prepareForTerminalLaunch();
    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final runtimeTomlPath = p.join(preparation.runtimeHomePath, 'config.toml');
    expect(
      _managedCommandCount(_hooks(runtimeHooksPath), 'alera-codex-hook.sh'),
      6,
    );
    expect(File(runtimeTomlPath).readAsStringSync(), contains('[hooks.state.'));

    final status = await service.remove();

    expect(status.state, ManagedAgentHookInstallState.notInstalled);
    expect(
      _managedCommandCount(_hooks(runtimeHooksPath), 'alera-codex-hook.sh'),
      0,
    );
    expect(
      File(runtimeTomlPath).readAsStringSync(),
      isNot(contains('[hooks.state.')),
    );
  });

  test('uses cmd runtime hooks on Windows', () async {
    final windowsService = CodexRuntimeHomeService(
      homeDirectory: home.path,
      applicationSupportDirectory: () async => support,
      platform: ManagedAgentHookPlatform.windows,
      environment: <String, String>{'USERPROFILE': home.path},
    );

    final preparation = await windowsService.prepareForTerminalLaunch();

    final runtimeHooks = _hooks(
      p.join(preparation.runtimeHomePath, 'hooks.json'),
    );
    expect(_managedCommandCount(runtimeHooks, 'alera-codex-hook.cmd'), 6);
    expect(
      File(
        p.join(home.path, '.alera', 'agent-hooks', 'alera-codex-hook.cmd'),
      ).readAsStringSync(),
      contains('/hook/codex'),
    );
  });

  test('preserves runtime trust entries when enabling fresh hooks', () async {
    final runtimeTomlPath = p.join(
      support.path,
      'agent-runtime-homes',
      'codex',
      'home',
      'config.toml',
    );
    File(runtimeTomlPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '[hooks.state."runtime-hooks:stop:0:0"]\n'
        'enabled = true\n'
        'trusted_hash = "sha256:runtime"\n',
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('[features]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(runtimeToml, contains('[hooks.state."runtime-hooks:stop:0:0"]'));
  });
}
