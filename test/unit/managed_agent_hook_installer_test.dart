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
        for (final hook in definition['hooks'] as List? ?? const <Object?>[])
          if (hook is Map && hook['command'] is String)
            hook['command'] as String,
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
