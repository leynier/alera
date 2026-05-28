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
