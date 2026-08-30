import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

part 'claude_runtime_home_service_test_harness.dart';
part 'claude_runtime_home_service_ccs_test_cases.dart';

void main() {
  group('ClaudeRuntimeHomeService', () {
    late Directory root;
    late Directory home;
    late Directory support;
    late ClaudeRuntimeHomeService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('alera-claude-runtime-');
      home = Directory(p.join(root.path, 'home'))..createSync(recursive: true);
      support = Directory(p.join(root.path, 'support'))
        ..createSync(recursive: true);
      service = ClaudeRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
        syncMacOSKeychainCredentials: false,
      );
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    _registerClaudeRuntimeCcsTests(() => home, () => support, () => service);

    test('prepares a runtime config without mutating user settings', () async {
      final sourceSettingsPath = p.join(home.path, '.claude', 'settings.json');
      _writeJson(sourceSettingsPath, <String, Object?>{
        'apiKeyHelper': 'echo api-key',
        'env': <String, Object?>{'FOO': 'bar'},
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo user-hook')],
        },
      });
      final sourcePluginFile =
          File(p.join(home.path, '.claude', 'plugins', 'demo.md'))
            ..createSync(recursive: true)
            ..writeAsStringSync('plugin contents');
      final legacyConfig = File(p.join(home.path, '.claude.json'))
        ..writeAsStringSync('{"projects":{}}\n');

      final preparation = await service.prepareForTerminalLaunch();

      final expectedRuntimeHome = p.join(
        support.path,
        'agent-runtime-homes',
        'claude',
        'home',
      );
      expect(preparation.runtimeHomePath, expectedRuntimeHome);
      expect(preparation.environment['CLAUDE_CONFIG_DIR'], expectedRuntimeHome);
      expect(
        preparation.environment['ALERA_CLAUDE_CONFIG_DIR'],
        expectedRuntimeHome,
      );
      expect(
        preparation.hookStatus.state,
        ManagedAgentHookInstallState.installed,
      );

      final sourceSettings = _readJson(sourceSettingsPath);
      expect(sourceSettings['apiKeyHelper'], 'echo api-key');
      // User Claude settings are leftover-stripped only. Grok scans this
      // file, so install must not write Alera commands here.
      expect(
        _managedCommandCount(
          _hooks(sourceSettingsPath),
          'alera-claude-hook.sh',
        ),
        0,
      );
      expect(
        _commandsFor(_hooks(sourceSettingsPath), 'UserPromptSubmit'),
        contains('echo user-hook'),
      );

      final runtimeSettingsPath = p.join(
        preparation.runtimeHomePath,
        'settings.json',
      );
      final runtimeSettings = _readJson(runtimeSettingsPath);
      expect(runtimeSettings['apiKeyHelper'], 'echo api-key');
      expect(runtimeSettings['env'], <String, Object?>{'FOO': 'bar'});
      final runtimeHooks = _hooks(runtimeSettingsPath);
      expect(
        _commandsFor(runtimeHooks, 'UserPromptSubmit'),
        contains('echo user-hook'),
      );
      expect(_managedCommandCount(runtimeHooks, 'alera-claude-hook.sh'), 6);
      expect(
        File(p.join(home.path, '.alera', 'agent-hooks', 'alera-claude-hook.sh'))
            .existsSync(),
        isTrue,
      );

      final runtimePluginFile = File(
        p.join(preparation.runtimeHomePath, 'plugins', 'demo.md'),
      );
      expect(
        runtimePluginFile.readAsStringSync(),
        sourcePluginFile.readAsStringSync(),
      );
      final runtimeLegacyConfig = File(
        p.join(preparation.runtimeHomePath, '.claude.json'),
      );
      expect(
        runtimeLegacyConfig.readAsStringSync(),
        legacyConfig.readAsStringSync(),
      );
    });

    test(
      'uses inherited CLAUDE_CONFIG_DIR as the source config directory',
      () async {
        final customConfig = Directory(p.join(root.path, 'custom-claude'))
          ..createSync(recursive: true);
        _writeJson(
          p.join(customConfig.path, 'settings.json'),
          <String, Object?>{'theme': 'dark'},
        );
        File(p.join(home.path, '.claude.json')).writeAsStringSync('{}\n');
        final customService = ClaudeRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{
            'HOME': home.path,
            'CLAUDE_CONFIG_DIR': customConfig.path,
          },
          syncMacOSKeychainCredentials: false,
        );

        final preparation = await customService.prepareForTerminalLaunch();

        final runtimeSettings = _readJson(
          p.join(preparation.runtimeHomePath, 'settings.json'),
        );
        expect(runtimeSettings['theme'], 'dark');
        expect(
          File(p.join(preparation.runtimeHomePath, '.claude.json'))
              .existsSync(),
          isFalse,
        );
      },
    );

    test('reports not installed before runtime hooks exist', () async {
      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(status.managedHooksPresent, isFalse);
      expect(
        status.configPath,
        p.join(
          support.path,
          'agent-runtime-homes',
          'claude',
          'home',
          'settings.json',
        ),
      );
    });

    test('reports invalid runtime settings as an error', () async {
      final runtimeSettingsPath = p.join(
        support.path,
        'agent-runtime-homes',
        'claude',
        'home',
        'settings.json',
      );
      File(runtimeSettingsPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      final status = await service.status();
      final removeStatus = await service.remove();

      expect(status.state, ManagedAgentHookInstallState.error);
      expect(removeStatus.state, ManagedAgentHookInstallState.error);
      expect(status.configPath, runtimeSettingsPath);
      expect(removeStatus.configPath, runtimeSettingsPath);
    });

    test('reports partial status when a managed event is missing', () async {
      final preparation = await service.prepareForTerminalLaunch();
      final runtimeSettingsPath = p.join(
        preparation.runtimeHomePath,
        'settings.json',
      );
      final runtimeConfig = _readJson(runtimeSettingsPath);
      final runtimeHooks = Map<String, Object?>.from(
        runtimeConfig['hooks'] as Map,
      );
      runtimeHooks.remove('Stop');
      runtimeConfig['hooks'] = runtimeHooks;
      _writeJson(runtimeSettingsPath, runtimeConfig);

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.managedHooksPresent, isTrue);
      expect(status.detail, contains('Managed hook missing for events: Stop.'));
    });

    test('uses cmd runtime hooks on Windows', () async {
      final windowsService = ClaudeRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{'USERPROFILE': home.path},
        syncMacOSKeychainCredentials: false,
      );

      final preparation = await windowsService.prepareForTerminalLaunch();

      final runtimeHooks = _hooks(
        p.join(preparation.runtimeHomePath, 'settings.json'),
      );
      expect(_managedCommandCount(runtimeHooks, 'alera-claude-hook.cmd'), 6);
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-claude-hook.cmd'),
        ).readAsStringSync(),
        contains('/hook/claude'),
      );
    });

    test(
      'reuses fallback copied resources while the source is unchanged',
      () async {
        final sourcePluginFile =
            File(p.join(home.path, '.claude', 'plugins', 'demo.md'))
              ..createSync(recursive: true)
              ..writeAsStringSync('plugin contents');
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final runtimeOnlyFile = File(
          p.join(preparation.runtimeHomePath, 'plugins', 'runtime-only.md'),
        )..writeAsStringSync('runtime-side change');
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-plugins.json'),
        );
        final markerBefore = marker.readAsStringSync();

        await fallbackService.prepareForTerminalLaunch();

        expect(
          File(p.join(preparation.runtimeHomePath, 'plugins', 'demo.md'))
              .readAsStringSync(),
          sourcePluginFile.readAsStringSync(),
        );
        expect(runtimeOnlyFile.existsSync(), isTrue);
        expect(runtimeOnlyFile.readAsStringSync(), 'runtime-side change');
        expect(marker.readAsStringSync(), markerBefore);
      },
    );

    test(
      'refreshes fallback copied resources after the source changes',
      () async {
        final sourcePluginsPath = p.join(home.path, '.claude', 'plugins');
        File(p.join(sourcePluginsPath, 'demo.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('plugin contents');
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final runtimeOnlyFile = File(
          p.join(preparation.runtimeHomePath, 'plugins', 'runtime-only.md'),
        )..writeAsStringSync('runtime-side change');
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-plugins.json'),
        );
        final fingerprintBefore = _markerFingerprint(marker);

        File(p.join(sourcePluginsPath, 'new.md'))
            .writeAsStringSync('new source');
        await fallbackService.prepareForTerminalLaunch();

        expect(runtimeOnlyFile.existsSync(), isFalse);
        expect(
          File(p.join(preparation.runtimeHomePath, 'plugins', 'new.md'))
              .existsSync(),
          isTrue,
        );
        expect(_markerFingerprint(marker), isNot(fingerprintBefore));
      },
    );

    test(
      'clears markers for linked resources and removes stale owned entries',
      () async {
        final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
          ..createSync(recursive: true);
        File(p.join(sourcePlugins.path, 'demo.md')).writeAsStringSync('plugin');
        final preparation = await service.prepareForTerminalLaunch();
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-plugins.json'),
        )..writeAsStringSync('{}\n');

        await service.prepareForTerminalLaunch();

        expect(marker.existsSync(), isFalse);

        final sourceCommands = Directory(
          p.join(home.path, '.claude', 'commands'),
        )..createSync(recursive: true);
        File(p.join(sourceCommands.path, 'demo.md')).writeAsStringSync('cmd');
        await service.prepareForTerminalLaunch();
        sourceCommands.deleteSync(recursive: true);
        await service.prepareForTerminalLaunch();

        expect(
          FileSystemEntity.typeSync(
            p.join(preparation.runtimeHomePath, 'commands'),
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
      },
    );

    test(
      'copies linked resources and ignores malformed fallback markers',
      () async {
        final targetPath = p.join(home.path, 'missing-plugin-target.md');
        final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
          ..createSync(recursive: true);
        Link(p.join(sourcePlugins.path, 'linked.md')).createSync(targetPath);
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-plugins.json'),
        )..writeAsStringSync('{bad');
        sourcePlugins.deleteSync(recursive: true);
        await fallbackService.prepareForTerminalLaunch();

        expect(marker.existsSync(), isTrue);
        expect(
          FileSystemEntity.typeSync(
            p.join(preparation.runtimeHomePath, 'plugins'),
            followLinks: false,
          ),
          isNot(FileSystemEntityType.notFound),
        );
      },
    );

    test(
      'removes owned runtime resources when the source disappears',
      () async {
        final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
          ..createSync(recursive: true);
        File(p.join(sourcePlugins.path, 'demo.md')).writeAsStringSync('plugin');

        final preparation = await service.prepareForTerminalLaunch();
        sourcePlugins.deleteSync(recursive: true);
        await service.prepareForTerminalLaunch();

        expect(
          FileSystemEntity.typeSync(
            p.join(preparation.runtimeHomePath, 'plugins'),
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
      },
    );

    test('handles broken source links and stale runtime links', () async {
      final runtimeHome = Directory(
        p.join(support.path, 'agent-runtime-homes', 'claude', 'home'),
      )..createSync(recursive: true);
      final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
        ..createSync(recursive: true);
      File(p.join(sourcePlugins.path, 'demo.md')).writeAsStringSync('plugin');
      final wrongSource = Directory(p.join(root.path, 'wrong-plugins'))
        ..createSync(recursive: true);
      Link(p.join(runtimeHome.path, 'plugins')).createSync(wrongSource.path);
      final brokenSourcePath = p.join(home.path, '.claude', 'broken-link');
      Link(brokenSourcePath).createSync(p.join(root.path, 'missing-source'));
      File(p.join(runtimeHome.path, '.alera-copied-broken-link.json'))
          .writeAsStringSync('{}\n');

      await service.prepareForTerminalLaunch();

      expect(
        FileSystemEntity.typeSync(
          p.join(runtimeHome.path, 'plugins'),
          followLinks: false,
        ),
        FileSystemEntityType.link,
      );
      expect(
        Link(p.join(runtimeHome.path, 'plugins')).targetSync(),
        sourcePlugins.path,
      );
      expect(
        File(p.join(runtimeHome.path, '.alera-copied-broken-link.json'))
            .existsSync(),
        isFalse,
      );
    });

    test(
      'accepts relative runtime links that already point to the source',
      () async {
        final runtimeHome = Directory(
          p.join(support.path, 'agent-runtime-homes', 'claude', 'home'),
        )..createSync(recursive: true);
        final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
          ..createSync(recursive: true);
        File(p.join(sourcePlugins.path, 'demo.md')).writeAsStringSync('plugin');
        final relativeTarget = p.relative(
          sourcePlugins.path,
          from: runtimeHome.path,
        );
        Link(p.join(runtimeHome.path, 'plugins')).createSync(relativeTarget);
        final marker = File(
          p.join(runtimeHome.path, '.alera-copied-plugins.json'),
        )..writeAsStringSync('{}\n');

        await service.prepareForTerminalLaunch();

        expect(marker.existsSync(), isFalse);
        expect(
          Link(p.join(runtimeHome.path, 'plugins')).targetSync(),
          relativeTarget,
        );
      },
    );

    test(
      'fingerprints nested fallback copies and deletes stale owned files',
      () async {
        final sourcePlugins = Directory(p.join(home.path, '.claude', 'plugins'))
          ..createSync(recursive: true);
        final nested = Directory(p.join(sourcePlugins.path, 'nested'))
          ..createSync();
        File(p.join(nested.path, 'demo.md')).writeAsStringSync('plugin');
        final legacyConfig = File(p.join(home.path, '.claude.json'))
          ..writeAsStringSync('{"projects":{}}\n');
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final pluginMarker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-plugins.json'),
        );
        final firstFingerprint = _markerFingerprint(pluginMarker);
        File(p.join(nested.path, 'next.md'))
            .writeAsStringSync('changed nested source');

        await fallbackService.prepareForTerminalLaunch();
        expect(_markerFingerprint(pluginMarker), isNot(firstFingerprint));

        final runtimeLegacyConfig = File(
          p.join(preparation.runtimeHomePath, '.claude.json'),
        );
        expect(runtimeLegacyConfig.existsSync(), isTrue);
        legacyConfig.deleteSync();
        await fallbackService.prepareForTerminalLaunch();

        expect(runtimeLegacyConfig.existsSync(), isFalse);
      },
    );

    test(
      'remove strips leftover managed hooks from user Claude settings',
      () async {
        final sourceSettingsPath = p.join(
          home.path,
          '.claude',
          'settings.json',
        );
        _writeJson(sourceSettingsPath, <String, Object?>{
          'hooks': <String, Object?>{
            'UserPromptSubmit': <Object?>[
              _userHook('echo user-hook'),
              <String, Object?>{
                'hooks': <Object?>[
                  <String, Object?>{
                    'type': 'command',
                    'command': "if [ -x '/tmp/alera-claude-hook.sh' ]; then ALERA_AGENT_HOOK_EVENT='UserPromptSubmit' /bin/sh '/home/user/.alera/agent-hooks/alera-claude-hook.sh'; fi",
                  },
                ],
              },
            ],
          },
        });

        await service.prepareForTerminalLaunch();
        final removed = await service.remove();

        expect(removed.state, ManagedAgentHookInstallState.notInstalled);
        expect(
          _managedCommandCount(
            _hooks(sourceSettingsPath),
            'alera-claude-hook.sh',
          ),
          0,
        );
        expect(
          _commandsFor(_hooks(sourceSettingsPath), 'UserPromptSubmit'),
          <String>['echo user-hook'],
        );
      },
    );

    test('remove deletes only managed runtime hooks', () async {
      final sourceSettingsPath = p.join(home.path, '.claude', 'settings.json');
      _writeJson(sourceSettingsPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[_userHook('echo user-hook')],
        },
      });

      final preparation = await service.prepareForTerminalLaunch();
      final removed = await service.remove();

      expect(removed.state, ManagedAgentHookInstallState.notInstalled);
      expect(
        _commandsFor(_hooks(sourceSettingsPath), 'UserPromptSubmit'),
        <String>['echo user-hook'],
      );
      final runtimeHooks = _hooks(
        p.join(preparation.runtimeHomePath, 'settings.json'),
      );
      expect(_commandsFor(runtimeHooks, 'UserPromptSubmit'), <String>[
        'echo user-hook',
      ]);
      expect(_managedCommandCount(runtimeHooks, 'alera-claude-hook.sh'), 0);
    });

    test(
      'install replaces stale managed hooks copied from source settings',
      () async {
        final staleManagedCommand = p.join(
          home.path,
          '.alera',
          'agent-hooks',
          'alera-claude-hook.sh',
        );
        final sourceSettingsPath = p.join(
          home.path,
          '.claude',
          'settings.json',
        );
        _writeJson(sourceSettingsPath, <String, Object?>{
          'hooks': <String, Object?>{
            'UserPromptSubmit': <Object?>[
              <String, Object?>{'command': staleManagedCommand},
            ],
            'Stop': <Object?>[
              <String, Object?>{
                'hooks': <Object?>[
                  <String, Object?>{'command': staleManagedCommand},
                  <String, Object?>{'command': 'echo user-stop'},
                ],
              },
            ],
          },
        });

        final preparation = await service.prepareForTerminalLaunch();

        final runtimeHooks = _hooks(
          p.join(preparation.runtimeHomePath, 'settings.json'),
        );
        expect(
          _commandsFor(runtimeHooks, 'Stop'),
          allOf(
            contains('echo user-stop'),
            isNot(contains(staleManagedCommand)),
          ),
        );
        expect(_managedCommandCount(runtimeHooks, 'alera-claude-hook.sh'), 6);
      },
    );

    test('reports invalid source settings as an error', () async {
      final sourceSettings = File(p.join(home.path, '.claude', 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      final status = await service.install();

      expect(status.state, ManagedAgentHookInstallState.error);
      expect(status.configPath, sourceSettings.path);
    });

    test(
      'copies legacy keychain credentials into the scoped runtime entry',
      () async {
        final keychain = _FakeClaudeKeychainCredentialsStore(
          legacyCredentials: '{"token":"legacy"}',
        );
        final keychainService = ClaudeRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{'HOME': home.path},
          keychainCredentialsStore: keychain,
        );

        final preparation = await keychainService.prepareForTerminalLaunch();

        expect(
          keychain.scopedCredentials[preparation.runtimeHomePath],
          '{"token":"legacy"}',
        );
        expect(keychain.deletedConfigDirs, isEmpty);
      },
    );

    test(
      'removes scoped runtime keychain credentials when legacy auth is missing',
      () async {
        final keychain = _FakeClaudeKeychainCredentialsStore();
        final keychainService = ClaudeRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{'HOME': home.path},
          keychainCredentialsStore: keychain,
        );

        final preparation = await keychainService.prepareForTerminalLaunch();

        expect(keychain.scopedCredentials, isEmpty);
        expect(keychain.deletedConfigDirs, <String>[
          preparation.runtimeHomePath,
        ]);
      },
    );

    test('ignores keychain sync failures', () async {
      final keychainService = ClaudeRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
        keychainCredentialsStore: _ThrowingClaudeKeychainCredentialsStore(),
      );

      final preparation = await keychainService.prepareForTerminalLaunch();

      expect(
        preparation.hookStatus.state,
        ManagedAgentHookInstallState.installed,
      );
    });

    test('throws when a home directory cannot be resolved', () {
      expect(
        () => ClaudeRuntimeHomeService(
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: const <String, String>{},
          syncMacOSKeychainCredentials: false,
        ),
        throwsStateError,
      );
    });
  });
}

ClaudeRuntimeHomeService _serviceWithFailingResourceLinks({
  required Directory home,
  required Directory support,
}) {
  return ClaudeRuntimeHomeService(
    homeDirectory: home.path,
    applicationSupportDirectory: () async => support,
    platform: ManagedAgentHookPlatform.posix,
    environment: <String, String>{'HOME': home.path},
    syncMacOSKeychainCredentials: false,
    resourceLinkCreator: ({required sourcePath, required targetPath}) =>
        throw const FileSystemException('symlinks disabled'),
  );
}

final class _FakeClaudeKeychainCredentialsStore
    implements ClaudeKeychainCredentialsStore {
  _FakeClaudeKeychainCredentialsStore({this.legacyCredentials});

  final String? legacyCredentials;
  final scopedCredentials = <String, String>{};
  final deletedConfigDirs = <String>[];

  @override
  Future<String?> readLegacyCredentials() async => legacyCredentials;

  @override
  Future<void> writeScopedCredentials({
    required String configDir,
    required String credentials,
  }) async {
    scopedCredentials[configDir] = credentials;
  }

  @override
  Future<void> deleteScopedCredentials(String configDir) async {
    deletedConfigDirs.add(configDir);
    scopedCredentials.remove(configDir);
  }
}

final class _ThrowingClaudeKeychainCredentialsStore
    implements ClaudeKeychainCredentialsStore {
  @override
  Future<String?> readLegacyCredentials() async {
    throw const FileSystemException('keychain unavailable');
  }

  @override
  Future<void> writeScopedCredentials({
    required String configDir,
    required String credentials,
  }) async {}

  @override
  Future<void> deleteScopedCredentials(String configDir) async {}
}
