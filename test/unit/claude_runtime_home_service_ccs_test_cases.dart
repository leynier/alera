part of 'claude_runtime_home_service_test.dart';

void _registerClaudeRuntimeCcsTests(
  Directory Function() readHome,
  Directory Function() readSupport,
  ClaudeRuntimeHomeService Function() readService,
) {
  test(
    'installs status hooks into user Claude and CCS shared settings',
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
      _writeJson(sharedSettingsPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo orca-hook')],
          'Stop': <Object?>[_userHook('echo orca-stop')],
        },
      });
      // CCS instance settings.json is a symlink to the shared file.
      final instanceDir = Directory(
        p.join(home.path, '.ccs', 'instances', 'profile-a'),
      )..createSync(recursive: true);
      Link(
        p.join(instanceDir.path, 'settings.json'),
      ).createSync(sharedSettingsPath);
      // Private credentials file must not be touched.
      final credentials = File(p.join(instanceDir.path, '.credentials.json'))
        ..writeAsStringSync('{"secret":"keep"}\n');

      final preparation = await service.prepareForTerminalLaunch();

      expect(
        preparation.hookStatus.state,
        ManagedAgentHookInstallState.installed,
      );
      // Durable user Claude settings get Alera hooks (CCS re-syncs from here).
      final userHooks = _hooks(userClaudeSettingsPath);
      expect(
        _commandsFor(userHooks, 'UserPromptSubmit'),
        contains('echo orca-hook'),
      );
      expect(_managedCommandCount(userHooks, 'alera-claude-hook.sh'), 6);
      // Shared file also gets Alera hooks and keeps foreign hooks.
      final sharedHooks = _hooks(sharedSettingsPath);
      expect(
        _commandsFor(sharedHooks, 'UserPromptSubmit'),
        contains('echo orca-hook'),
      );
      expect(_managedCommandCount(sharedHooks, 'alera-claude-hook.sh'), 6);
      // Symlink still points at shared settings (not replaced by a regular file).
      expect(
        FileSystemEntity.typeSync(
          p.join(instanceDir.path, 'settings.json'),
          followLinks: false,
        ),
        FileSystemEntityType.link,
      );
      expect(credentials.readAsStringSync(), '{"secret":"keep"}\n');
      // Bare-claude runtime home still has hooks and env injection.
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
      final sharedAfter = _hooks(sharedSettingsPath);
      expect(_commandsFor(sharedAfter, 'UserPromptSubmit'), <String>[
        'echo orca-hook',
      ]);
      expect(_managedCommandCount(sharedAfter, 'alera-claude-hook.sh'), 0);
      expect(_commandsFor(sharedAfter, 'Stop'), <String>['echo orca-stop']);
    },
  );

  test(
    'reports partial when runtime is ready but CCS shared hooks are missing',
    () async {
      final home = readHome();
      final service = readService();
      final preparation = await service.prepareForTerminalLaunch();
      final sharedSettingsPath = p.join(
        home.path,
        '.ccs',
        'shared',
        'settings.json',
      );
      // Create CCS shared settings without Alera hooks after install.
      _writeJson(sharedSettingsPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo only-orca')],
        },
      });

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.managedHooksPresent, isTrue);
      expect(status.detail, contains(sharedSettingsPath));
      expect(
        status.configPath,
        p.join(preparation.runtimeHomePath, 'settings.json'),
      );
    },
  );
}
