import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ManagedAgentHookInstallService', () {
    late Directory home;
    late ManagedAgentHookInstallService service;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('alera-hook-install-');
      service = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
      );
    });

    tearDown(() {
      if (home.existsSync()) {
        home.deleteSync(recursive: true);
      }
    });

    test('installs Codex hooks idempotently and preserves user hooks', () {
      final configPath = p.join(home.path, '.codex', 'hooks.json');
      _writeJson(configPath, <String, Object?>{
        'hooks': <String, Object?>{
          'PreToolUse': <Object?>[
            <String, Object?>{
              'hooks': <Object?>[
                <String, Object?>{
                  'type': 'command',
                  'command': 'echo user-hook',
                },
              ],
            },
          ],
        },
      });

      expect(
        service.install(AgentType.codex).state,
        ManagedAgentHookInstallState.installed,
      );
      expect(
        service.install(AgentType.codex).state,
        ManagedAgentHookInstallState.installed,
      );

      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      expect(
        _commandsFor(hooks, 'PreToolUse'),
        containsAll(<String>['echo user-hook']),
      );
      expect(_managedCommandCount(hooks, 'alera-codex-hook.sh'), 6);
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-codex-hook.sh'),
        ).existsSync(),
        isTrue,
      );
    });

    test('removes only Alera-managed hooks', () {
      final configPath = p.join(home.path, '.claude', 'settings.json');
      _writeJson(configPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[
            <String, Object?>{
              'hooks': <Object?>[
                <String, Object?>{
                  'type': 'command',
                  'command':
                      "if [ -x '/Users/test/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/test/.orca/agent-hooks/claude-hook.sh'; fi",
                },
              ],
            },
          ],
        },
      });

      service.install(AgentType.claude);
      expect(
        _managedCommandCount(_hooks(configPath), 'alera-claude-hook.sh'),
        6,
      );

      final removed = service.remove(AgentType.claude);

      expect(removed.state, ManagedAgentHookInstallState.notInstalled);
      final hooks = _hooks(configPath);
      expect(_managedCommandCount(hooks, 'alera-claude-hook.sh'), 0);
      expect(_commandsFor(hooks, 'UserPromptSubmit').single, contains('.orca'));
    });

    test('reports corrupt config as an error', () {
      final configPath = p.join(home.path, '.claude', 'settings.json');
      File(configPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      expect(
        service.status(AgentType.claude).state,
        ManagedAgentHookInstallState.error,
      );
      expect(
        service.install(AgentType.claude).state,
        ManagedAgentHookInstallState.error,
      );
    });

    test('installs Copilot hooks in the dedicated hook file', () {
      final status = service.install(AgentType.copilot);
      final configPath = p.join(home.path, '.copilot', 'hooks', 'alera.json');
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(config['version'], 1);
      expect(
        hooks.keys,
        containsAll(<String>[
          'SessionStart',
          'UserPromptSubmit',
          'Notification',
          'Stop',
        ]),
      );
      expect(
        _directCommandsFor(hooks, 'UserPromptSubmit').single,
        contains('ALERA_COPILOT_HOOK_EVENT'),
      );
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-copilot-hook.sh'),
        ).readAsStringSync(),
        contains('/hook/copilot'),
      );
    });

    test('removes only Alera-managed Copilot hooks', () {
      service.install(AgentType.copilot);
      final configPath = p.join(home.path, '.copilot', 'hooks', 'alera.json');
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      hooks['UserPromptSubmit'] = <Object?>[
        <String, Object?>{'type': 'command', 'bash': 'echo user prompt'},
        ...(hooks['UserPromptSubmit'] as List),
      ];
      config['hooks'] = hooks;
      _writeJson(configPath, config);

      final status = service.remove(AgentType.copilot);
      final nextHooks = _hooks(configPath);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(_directCommandsFor(nextHooks, 'UserPromptSubmit'), <String>[
        'echo user prompt',
      ]);
      expect(nextHooks['SessionStart'], isNull);
    });

    test('installs AGY hooks in the Gemini global hooks bundle', () {
      final configPath = p.join(home.path, '.gemini', 'config', 'hooks.json');
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
      final bundle = Map<String, Object?>.from(config['alera-status'] as Map);

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
      expect(bundle['PreToolUse'], isNull);
      expect(
        _commandsFor(bundle, 'PreInvocation'),
        containsAll(<String>['echo alera-extra']),
      );
      expect(
        _commandsFor(bundle, 'PreInvocation').last,
        contains('ALERA_AGY_EVENT'),
      );
      expect(
        _commandsFor(bundle, 'PostToolUse').single,
        contains('alera-agy-hook.sh'),
      );
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-hook.sh'),
        ).readAsStringSync(),
        contains('/hook/agy'),
      );
    });

    test('removes only Alera-managed AGY bundle entries', () {
      service.install(AgentType.agy);
      final configPath = p.join(home.path, '.gemini', 'config', 'hooks.json');
      final config = _readJson(configPath);
      final bundle = Map<String, Object?>.from(config['alera-status'] as Map);
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
  });
}

void _writeJson(String path, Map<String, Object?> data) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
}

Map<String, Object?> _readJson(String path) {
  return Map<String, Object?>.from(
    jsonDecode(File(path).readAsStringSync()) as Map,
  );
}

Map<String, Object?> _hooks(String path) {
  return Map<String, Object?>.from(_readJson(path)['hooks'] as Map);
}

List<String> _commandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        if (definition['command'] is String) definition['command'] as String,
    for (final definition in definitions)
      if (definition is Map)
        for (final hook in definition['hooks'] as List? ?? const <Object?>[])
          if (hook is Map && hook['command'] is String)
            hook['command'] as String,
  ];
}

List<String> _directCommandsFor(Map<String, Object?> hooks, String eventName) {
  final definitions = hooks[eventName] as List? ?? const <Object?>[];
  return <String>[
    for (final definition in definitions)
      if (definition is Map)
        for (final key in const <String>['bash', 'powershell', 'command'])
          if (definition[key] is String) definition[key] as String,
  ];
}

int _managedCommandCount(Map<String, Object?> hooks, String scriptFileName) {
  return hooks.values.fold<int>(0, (count, value) {
    final definitions = value as List? ?? const <Object?>[];
    return count +
        definitions.fold<int>(0, (innerCount, definition) {
          if (definition is! Map) {
            return innerCount;
          }
          final hooks = definition['hooks'] as List? ?? const <Object?>[];
          return innerCount +
              hooks.where((hook) {
                return hook is Map &&
                    (hook['command'] as String?)
                            ?.replaceAll(r'\', '/')
                            .contains('agent-hooks/$scriptFileName') ==
                        true;
              }).length;
        });
  });
}
