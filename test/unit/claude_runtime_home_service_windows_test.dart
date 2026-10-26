import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _events = <String>[
  'UserPromptSubmit',
  'Stop',
  'PreToolUse',
  'PostToolUse',
  'PostToolUseFailure',
  'PermissionRequest',
];
const _legacyScripts = <String>[
  'alera-claude-hook.sh',
  'alera-claude-hook.cmd',
  'alera-runtime-agent-hook.sh',
  'alera-runtime-agent-hook.cmd',
  'alera-runtime-agent-hook.ps1',
  'alera-claude-hook.ps1',
];

void main() {
  late Directory root;
  late Directory home;
  late Directory support;
  late ClaudeRuntimeHomeService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('alera-claude-windows-');
    home = Directory(p.join(root.path, r"Mira's $HOME (niño) & company"))
      ..createSync();
    support = Directory(p.join(root.path, 'support'))..createSync();
    service = ClaudeRuntimeHomeService(
      homeDirectory: home.path,
      applicationSupportDirectory: () async => support,
      platform: .windows,
      environment: <String, String>{'USERPROFILE': home.path},
      syncMacOSKeychainCredentials: false,
    );
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('generates Bash-quoted native PowerShell commands in the old schema', () async {
    final preparation = await service.prepareForTerminalLaunch();
    final config = _readConfig(
      p.join(preparation.runtimeHomePath, 'settings.json'),
    );
    final hooks = config['hooks'] as Map;
    final scriptPath = p.join(
      home.path,
      '.alera',
      'agent-hooks',
      'alera-claude-hook.ps1',
    );
    final quotedPath = "'${scriptPath.replaceAll("'", "'\\''")}'";

    for (final event in _events) {
      final definition = (hooks[event] as List).single as Map;
      expect(definition, <String, Object?>{
        if (event != 'Stop' && event != 'UserPromptSubmit') 'matcher': '*',
        'hooks': <Object?>[
          <String, Object?>{
            'type': 'command',
            'command':
                'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $quotedPath -HookEventName $event',
          },
        ],
      });
    }
    expect(File(scriptPath).existsSync(), isTrue);
    expect(File(p.setExtension(scriptPath, '.cmd')).existsSync(), isFalse);
    expect(
      preparation.hookStatus.state,
      ManagedAgentHookInstallState.installed,
    );
  });

  test(
    'Windows script treats endpoint content as data and posts UTF-8 JSON',
    () async {
      await service.prepareForTerminalLaunch();
      final script = File(
        p.join(home.path, '.alera', 'agent-hooks', 'alera-claude-hook.ps1'),
      ).readAsStringSync();

      expect(script, contains(r'$env:CLAUDECODE'));
      expect(script, contains(r'$env:GROK_HOOK_EVENT'));
      expect(
        script,
        contains(
          r"Join-Path $env:ALERA_RUNTIME_DIR 'agent-hooks\endpoint.cmd'",
        ),
      );
      expect(
        script,
        contains(r'[System.IO.File]::ReadAllLines($endpointPath, $utf8)'),
      );
      expect(script, contains('(?:PORT|TOKEN|VERSION)'));
      expect(script, isNot(contains('Invoke-Expression')));
      expect(script, isNot(contains('cmd.exe')));
      expect(script, contains(r'[Console]::OpenStandardInput()'));
      expect(script, contains(r'ConvertFrom-Json -InputObject $inputData'));
      expect(script, contains('-TimeoutSec 2'));
      expect(script, contains("'application/json; charset=utf-8'"));
      expect(script, contains(r'-Body ($utf8.GetBytes($body))'));
      expect(script, endsWith('} catch {}\nexit 0\n'));
    },
  );

  test('migrates both PowerShell hook generations in complete runtime and CCS settings while preserving mixed user handlers', () async {
    final sourcePath = p.join(home.path, '.claude', 'settings.json');
    final runtimePath = p.join(
      support.path,
      'agent-runtime-homes',
      'claude',
      'home',
      'settings.json',
    );
    final ccsPath = p.join(
      home.path,
      '.ccs',
      'instances',
      'profile-a',
      'settings.local.json',
    );
    final staleConfig = _completeStaleConfig();
    for (final path in <String>[sourcePath, runtimePath, ccsPath]) {
      _writeConfig(path, staleConfig);
    }
    final sourceBefore = File(sourcePath).readAsBytesSync();

    expect(
      (await service.status()).state,
      ManagedAgentHookInstallState.installed,
    );
    final installed = await service.install();

    expect(installed.state, ManagedAgentHookInstallState.installed);
    expect(File(sourcePath).readAsBytesSync(), sourceBefore);
    for (final path in <String>[runtimePath, ccsPath]) {
      final config = _readConfig(path);
      expect(config['userSetting'], <String, Object?>{'keep': true});
      final hooks = config['hooks'] as Map;
      for (final event in _events) {
        final definitions = hooks[event] as List;
        expect(definitions, hasLength(2));
        expect(definitions.first, _mixedUserDefinition(event));
        final command =
            (((definitions.last as Map)['hooks'] as List).single
                    as Map)['command']
                as String;
        expect(
          command,
          startsWith('powershell.exe -NoProfile -NonInteractive '),
        );
        expect(command, contains('alera-claude-hook.ps1'));
        expect(command, endsWith('-HookEventName $event'));
        for (final legacy in _legacyScripts.where(
          (name) => name != 'alera-claude-hook.ps1',
        )) {
          expect(jsonEncode(definitions), isNot(contains(legacy)));
        }
      }
      expect(hooks['SessionEnd'], <Object?>[
        _mixedUserDefinition('SessionEnd'),
      ]);
    }
  });

  test('repeat install leaves runtime, CCS, and script bytes and modification times unchanged', () async {
    final ccsPath = p.join(
      home.path,
      '.ccs',
      'instances',
      'profile-a',
      'settings.local.json',
    );
    _writeConfig(ccsPath, _completeStaleConfig());
    final preparation = await service.prepareForTerminalLaunch();
    final files = <File>[
      File(p.join(preparation.runtimeHomePath, 'settings.json')),
      File(ccsPath),
      File(p.join(home.path, '.alera', 'agent-hooks', 'alera-claude-hook.ps1')),
    ];
    final unchangedTime = DateTime.utc(2001, 2, 3, 4, 5, 6);
    for (final file in files) {
      file.setLastModifiedSync(unchangedTime);
    }
    final before = <String, List<int>>{
      for (final file in files) file.path: file.readAsBytesSync(),
    };
    final times = <String, DateTime>{
      for (final file in files) file.path: file.lastModifiedSync(),
    };

    await service.prepareForTerminalLaunch();

    for (final file in files) {
      expect(file.readAsBytesSync(), before[file.path], reason: file.path);
      expect(file.lastModifiedSync(), times[file.path], reason: file.path);
    }
  });

  for (final platform in ManagedAgentHookPlatform.values) {
    for (final compact in <bool>[true, false]) {
      test(
        'preserves current ${platform.name} CCS settings bytes and modification time with ${compact ? 'compact' : 'CRLF'} JSON',
        () async {
          final ccsPath = p.join(
            home.path,
            '.ccs',
            'instances',
            'profile-a',
            'settings.local.json',
          );
          _writeConfig(ccsPath, <String, Object?>{
            'userSetting': <String, Object?>{'keep': true, 'nullable': null},
            'hooks': <String, Object?>{
              'Stop': <Object?>[_mixedUserDefinition('Stop')],
            },
          });
          final platformService = ClaudeRuntimeHomeService(
            homeDirectory: home.path,
            applicationSupportDirectory: () async => support,
            platform: platform,
            environment: <String, String>{'HOME': home.path},
            syncMacOSKeychainCredentials: false,
          );
          await platformService.prepareForTerminalLaunch();
          final settings = File(ccsPath);
          final reordered = _reverseObjectKeys(_readConfig(ccsPath));
          final serialized = compact
              ? jsonEncode(reordered)
              : '${const JsonEncoder.withIndent('    ').convert(reordered).replaceAll('\n', '\r\n')}\r\n';
          settings.writeAsStringSync(serialized);
          settings.setLastModifiedSync(DateTime.utc(2001, 2, 3, 4, 5, 6));
          final bytesBefore = settings.readAsBytesSync();
          final modifiedBefore = settings.lastModifiedSync();

          final installed = await platformService.install();

          expect(installed.state, ManagedAgentHookInstallState.installed);
          expect(settings.readAsBytesSync(), bytesBefore);
          expect(settings.lastModifiedSync(), modifiedBefore);
        },
      );
    }
    test(
      'remove recognizes all Claude script generations on ${platform.name}',
      () async {
        final runtimePath = p.join(
          support.path,
          'agent-runtime-homes',
          'claude',
          'home',
          'settings.json',
        );
        final ccsPath = p.join(
          home.path,
          '.ccs',
          'instances',
          'profile-a',
          'settings.local.json',
        );
        for (final path in <String>[runtimePath, ccsPath]) {
          _writeConfig(path, _completeStaleConfig());
        }
        final platformService = ClaudeRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: platform,
          environment: <String, String>{'HOME': home.path},
          syncMacOSKeychainCredentials: false,
        );

        final removed = await platformService.remove();

        expect(removed.state, ManagedAgentHookInstallState.notInstalled);
        for (final path in <String>[runtimePath, ccsPath]) {
          final config = _readConfig(path);
          expect(config['hooks'], <String, Object?>{
            for (final event in <String>[..._events, 'SessionEnd'])
              event: <Object?>[_mixedUserDefinition(event)],
          });
        }
      },
    );
  }
}

Object? _reverseObjectKeys(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final key in value.keys.toList().reversed)
        key as String: _reverseObjectKeys(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _reverseObjectKeys(item)];
  }
  return value;
}

Map<String, Object?> _completeStaleConfig() => <String, Object?>{
  'userSetting': <String, Object?>{'keep': true},
  'hooks': <String, Object?>{
    for (final event in <String>[..._events, 'SessionEnd'])
      event: <Object?>[
        <String, Object?>{
          ..._mixedUserDefinition(event),
          'command': r'cmd /c C:\old\agent-hooks\alera-claude-hook.cmd',
          'bash': '/old/agent-hooks/alera-claude-hook.sh',
          'powershell':
              'powershell -File C:\\old\\agent-hooks\\alera-claude-hook.ps1',
          'hooks': <Object?>[
            ...(_mixedUserDefinition(event)['hooks'] as List),
            for (final script in _legacyScripts)
              <String, Object?>{
                'type': 'command',
                'command': 'old-shell /old/agent-hooks/$script',
              },
          ],
        },
      ],
  },
};

Map<String, Object?> _mixedUserDefinition(String event) => <String, Object?>{
  'matcher': 'user-matcher',
  'userMetadata': <String, Object?>{'event': event},
  'hooks': <Object?>[
    <String, Object?>{
      'type': 'command',
      'command': 'echo user-$event',
      'timeout': 17,
    },
    <String, Object?>{'type': 'prompt', 'prompt': 'Keep this user hook'},
  ],
};

Map<String, Object?> _readConfig(String path) =>
    Map<String, Object?>.from(jsonDecode(File(path).readAsStringSync()) as Map);

void _writeConfig(String path, Map<String, Object?> config) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(config));
}
