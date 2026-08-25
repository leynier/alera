part of 'claude_runtime_home_service_test.dart';

void _registerClaudeRuntimeCcsTests(
  Directory Function() readHome,
  Directory Function() readSupport,
  ClaudeRuntimeHomeService Function() readService,
) {
  test(
    'installs status hooks into CCS instance local settings, not user Claude settings',
    () async {
      final home = readHome();
      final service = readService();
      final userClaudeSettingsPath = p.join(
        home.path,
        '.claude',
        'settings.json',
      );
      _writeJson(userClaudeSettingsPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo orca-hook')],
          'Stop': <Object?>[_userHook('echo orca-stop')],
        },
      });
      final sharedSettingsPath = p.join(
        home.path,
        '.ccs',
        'shared',
        'settings.json',
      );
      File(sharedSettingsPath).parent.createSync(recursive: true);
      Link(sharedSettingsPath).createSync(userClaudeSettingsPath);
      final instanceDir = Directory(
        p.join(home.path, '.ccs', 'instances', 'profile-a'),
      )..createSync(recursive: true);
      Link(
        p.join(instanceDir.path, 'settings.json'),
      ).createSync(sharedSettingsPath);
      final credentials = File(p.join(instanceDir.path, '.credentials.json'))
        ..writeAsStringSync('{"secret":"keep"}\n');
      final localSettingsPath = p.join(instanceDir.path, 'settings.local.json');

      final preparation = await service.prepareForTerminalLaunch();

      expect(
        preparation.hookStatus.state,
        ManagedAgentHookInstallState.installed,
      );
      final userHooks = _hooks(userClaudeSettingsPath);
      expect(
        _commandsFor(userHooks, 'UserPromptSubmit'),
        contains('echo orca-hook'),
      );
      expect(_managedCommandCount(userHooks, 'alera-claude-hook.sh'), 0);
      expect(
        FileSystemEntity.typeSync(sharedSettingsPath, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(
        FileSystemEntity.typeSync(
          p.join(instanceDir.path, 'settings.json'),
          followLinks: false,
        ),
        FileSystemEntityType.link,
      );
      expect(credentials.readAsStringSync(), '{"secret":"keep"}\n');
      final localHooks = _hooks(localSettingsPath);
      expect(_managedCommandCount(localHooks, 'alera-claude-hook.sh'), 6);
      expect(
        preparation.environment['CLAUDE_CONFIG_DIR'],
        preparation.runtimeHomePath,
      );
      expect(
        _managedCommandCount(
          _hooks(p.join(preparation.runtimeHomePath, 'settings.json')),
          'alera-claude-hook.sh',
        ),
        6,
      );

      final removed = await service.remove();
      expect(removed.state, ManagedAgentHookInstallState.notInstalled);
      final userAfter = _hooks(userClaudeSettingsPath);
      expect(_commandsFor(userAfter, 'UserPromptSubmit'), <String>[
        'echo orca-hook',
      ]);
      expect(_managedCommandCount(userAfter, 'alera-claude-hook.sh'), 0);
      expect(
        _managedCommandCount(_hooks(localSettingsPath), 'alera-claude-hook.sh'),
        0,
      );
    },
  );

  test(
    'reports partial when runtime is ready but CCS instance local hooks are missing',
    () async {
      final home = readHome();
      final service = readService();
      final preparation = await service.prepareForTerminalLaunch();
      final instanceDir = Directory(
        p.join(home.path, '.ccs', 'instances', 'profile-a'),
      )..createSync(recursive: true);
      final localSettingsPath = p.join(instanceDir.path, 'settings.local.json');
      _writeJson(localSettingsPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo only-orca')],
        },
      });

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.managedHooksPresent, isTrue);
      expect(status.detail, contains(localSettingsPath));
      expect(
        status.configPath,
        p.join(preparation.runtimeHomePath, 'settings.json'),
      );
    },
  );
}
