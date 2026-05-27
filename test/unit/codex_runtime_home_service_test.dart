import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CodexRuntimeHomeService', () {
    late Directory root;
    late Directory home;
    late Directory support;
    late CodexRuntimeHomeService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('alera-codex-runtime-');
      home = Directory(p.join(root.path, 'home'))..createSync(recursive: true);
      support = Directory(p.join(root.path, 'support'))
        ..createSync(recursive: true);
      service = CodexRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
      );
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

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
      expect(_commandsFor(systemHooks, 'PreToolUse'), <String>[
        'echo user-hook',
      ]);
      expect(_managedCommandCount(systemHooks, 'alera-codex-hook.sh'), 0);

      final runtimeHooksPath = p.join(
        preparation.runtimeHomePath,
        'hooks.json',
      );
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

      final runtimeHooksPath = p.join(
        preparation.runtimeHomePath,
        'hooks.json',
      );
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

    test('removes mirrored auth when system auth disappears', () async {
      final systemAuth = File(p.join(home.path, '.codex', 'auth.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"token":"system"}\n');

      final preparation = await service.prepareForTerminalLaunch();
      final runtimeAuth = File(
        p.join(preparation.runtimeHomePath, 'auth.json'),
      );

      expect(runtimeAuth.existsSync(), isTrue);
      expect(runtimeAuth.readAsStringSync(), systemAuth.readAsStringSync());

      systemAuth.deleteSync();
      await service.prepareForTerminalLaunch();

      expect(
        FileSystemEntity.typeSync(runtimeAuth.path, followLinks: false),
        FileSystemEntityType.notFound,
      );
    });

    test('mirrors trusted user hook state into the runtime config', () async {
      final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
      const userCommand = 'echo trusted-user-hook';
      _writeJson(systemHooksPath, <String, Object?>{
        'hooks': <String, Object?>{
          'PreToolUse': <Object?>[_userHook(userCommand)],
        },
      });
      final canonicalSystemHooksPath = File(
        systemHooksPath,
      ).resolveSymbolicLinksSync();
      final systemTrustKey = '$canonicalSystemHooksPath:pre_tool_use:0:0';
      final systemTrustedHash = computeCodexTrustedHashForTesting(
        sourcePath: systemHooksPath,
        eventLabel: 'pre_tool_use',
        groupIndex: 0,
        handlerIndex: 0,
        command: userCommand,
      );
      File(p.join(home.path, '.codex', 'config.toml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '[hooks.state."${_escapeTomlString(systemTrustKey)}"]\n'
          'enabled = false\n'
          'trusted_hash = "$systemTrustedHash"\n',
        );

      final preparation = await service.prepareForTerminalLaunch();

      final runtimeHooksPath = p.join(
        preparation.runtimeHomePath,
        'hooks.json',
      );
      final canonicalRuntimeHooksPath = File(
        runtimeHooksPath,
      ).resolveSymbolicLinksSync();
      final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
      final runtimeToml = File(
        p.join(preparation.runtimeHomePath, 'config.toml'),
      ).readAsStringSync();
      expect(
        runtimeToml,
        contains('[hooks.state."${_escapeTomlString(runtimeTrustKey)}"]'),
      );
      expect(runtimeToml, contains('enabled = false'));
      expect(runtimeToml, contains('trusted_hash = "$systemTrustedHash"'));
    });

    test('preserves hook-like text inside multiline TOML strings', () async {
      final systemConfig = File(p.join(home.path, '.codex', 'config.toml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'note = """\n'
          '[hooks.state."fake-system"]\n'
          'trusted_hash = "not-a-section"\n'
          '"""\n'
          '\n'
          '[features]\n'
          'codex_hooks = true\n',
        );
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
      expect(runtimeToml, contains('[hooks.state."fake-system"]'));
      expect(runtimeToml, contains('trusted_hash = "not-a-section"'));
      expect(runtimeToml, contains('[hooks.state."runtime-hooks:stop:0:0"]'));
      expect(runtimeToml, contains('hooks = true'));
      expect(runtimeToml, isNot(contains('codex_hooks')));
      expect(systemConfig.readAsStringSync(), contains('codex_hooks = true'));
    });

    test('ignores fake trust blocks inside multiline TOML strings', () async {
      final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
      const userCommand = 'echo fake-trusted-user-hook';
      _writeJson(systemHooksPath, <String, Object?>{
        'hooks': <String, Object?>{
          'PreToolUse': <Object?>[_userHook(userCommand)],
        },
      });
      final canonicalSystemHooksPath = File(
        systemHooksPath,
      ).resolveSymbolicLinksSync();
      final systemTrustKey = '$canonicalSystemHooksPath:pre_tool_use:0:0';
      final systemTrustedHash = computeCodexTrustedHashForTesting(
        sourcePath: systemHooksPath,
        eventLabel: 'pre_tool_use',
        groupIndex: 0,
        handlerIndex: 0,
        command: userCommand,
      );
      File(p.join(home.path, '.codex', 'config.toml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'note = """\n'
          '[hooks.state."${_escapeTomlString(systemTrustKey)}"]\n'
          'enabled = false\n'
          'trusted_hash = "$systemTrustedHash"\n'
          '"""\n',
        );

      final preparation = await service.prepareForTerminalLaunch();

      final runtimeHooksPath = p.join(
        preparation.runtimeHomePath,
        'hooks.json',
      );
      final canonicalRuntimeHooksPath = File(
        runtimeHooksPath,
      ).resolveSymbolicLinksSync();
      final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
      final runtimeToml = File(
        p.join(preparation.runtimeHomePath, 'config.toml'),
      ).readAsStringSync();
      expect(
        runtimeToml,
        isNot(
          contains('[hooks.state."${_escapeTomlString(runtimeTrustKey)}"]'),
        ),
      );
    });

    test('links or copies Codex resources into the runtime home', () async {
      final skillFile = File(p.join(home.path, '.codex', 'skills', 'demo.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('skill contents');

      final preparation = await service.prepareForTerminalLaunch();

      final runtimeSkillFile = File(
        p.join(preparation.runtimeHomePath, 'skills', 'demo.md'),
      );
      expect(runtimeSkillFile.existsSync(), isTrue);
      expect(runtimeSkillFile.readAsStringSync(), skillFile.readAsStringSync());
    });

    test(
      'reuses fallback copied resources while the source is unchanged',
      () async {
        final skillFile = File(p.join(home.path, '.codex', 'skills', 'demo.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('skill contents');
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final runtimeSkillFile = File(
          p.join(preparation.runtimeHomePath, 'skills', 'demo.md'),
        );
        final runtimeOnlyFile = File(
          p.join(preparation.runtimeHomePath, 'skills', 'runtime-only.md'),
        )..writeAsStringSync('runtime-side change');
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-skills.json'),
        );
        final markerBefore = marker.readAsStringSync();

        await fallbackService.prepareForTerminalLaunch();

        expect(
          runtimeSkillFile.readAsStringSync(),
          skillFile.readAsStringSync(),
        );
        expect(runtimeOnlyFile.existsSync(), isTrue);
        expect(runtimeOnlyFile.readAsStringSync(), 'runtime-side change');
        expect(marker.readAsStringSync(), markerBefore);
      },
    );

    test(
      'refreshes fallback copied resources after the source changes',
      () async {
        final sourceSkillsPath = p.join(home.path, '.codex', 'skills');
        File(p.join(sourceSkillsPath, 'demo.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('skill contents');
        final fallbackService = _serviceWithFailingResourceLinks(
          home: home,
          support: support,
        );

        final preparation = await fallbackService.prepareForTerminalLaunch();
        final runtimeOnlyFile = File(
          p.join(preparation.runtimeHomePath, 'skills', 'runtime-only.md'),
        )..writeAsStringSync('runtime-side change');
        final marker = File(
          p.join(preparation.runtimeHomePath, '.alera-copied-skills.json'),
        );
        final fingerprintBefore = _markerFingerprint(marker);

        File(
          p.join(sourceSkillsPath, 'new.md'),
        ).writeAsStringSync('new source');
        await fallbackService.prepareForTerminalLaunch();

        expect(runtimeOnlyFile.existsSync(), isFalse);
        expect(
          File(
            p.join(preparation.runtimeHomePath, 'skills', 'new.md'),
          ).existsSync(),
          isTrue,
        );
        expect(_markerFingerprint(marker), isNot(fingerprintBefore));
      },
    );
  });
}

CodexRuntimeHomeService _serviceWithFailingResourceLinks({
  required Directory home,
  required Directory support,
}) {
  return CodexRuntimeHomeService(
    homeDirectory: home.path,
    applicationSupportDirectory: () async => support,
    platform: ManagedAgentHookPlatform.posix,
    environment: <String, String>{'HOME': home.path},
    resourceLinkCreator: ({required sourcePath, required targetPath}) =>
        throw const FileSystemException('symlinks disabled'),
  );
}

String _markerFingerprint(File marker) {
  final decoded = jsonDecode(marker.readAsStringSync()) as Map;
  return decoded['sourceFingerprint'] as String;
}

Map<String, Object?> _userHook(String command) {
  return _userHookCommands(<String>[command]);
}

Map<String, Object?> _userHookCommands(List<String> commands) {
  return <String, Object?>{
    'hooks': <Object?>[
      for (final command in commands)
        <String, Object?>{'type': 'command', 'command': command},
    ],
  };
}

String _trustBlock({
  required String key,
  required bool enabled,
  required String trustedHash,
}) {
  return '[hooks.state."${_escapeTomlString(key)}"]\n'
      'enabled = $enabled\n'
      'trusted_hash = "$trustedHash"\n';
}

void _writeJson(String path, Map<String, Object?> value) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

Map<String, Object?> _hooks(String configPath) {
  final decoded = jsonDecode(File(configPath).readAsStringSync()) as Map;
  return Map<String, Object?>.from(decoded['hooks'] as Map);
}

List<String> _commandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        for (final hook in (definition['hooks'] as List? ?? const <Object?>[]))
          if (hook is Map && hook['command'] is String)
            hook['command'] as String,
  ];
}

int _managedCommandCount(Map<String, Object?> hooks, String fileName) {
  var count = 0;
  for (final event in hooks.values) {
    if (event is! List) {
      continue;
    }
    for (final definition in event) {
      if (definition is! Map) {
        continue;
      }
      final hookEntries = definition['hooks'];
      if (hookEntries is! List) {
        continue;
      }
      for (final hook in hookEntries) {
        if (hook is Map &&
            hook['command'] is String &&
            (hook['command'] as String).contains(fileName)) {
          count += 1;
        }
      }
    }
  }
  return count;
}

String _escapeTomlString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
