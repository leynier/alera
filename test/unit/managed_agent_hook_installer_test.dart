import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

part 'managed_agent_hook_installer_test_harness.dart';
part 'managed_agent_hook_installer_grok_test_cases.dart';
part 'managed_agent_hook_installer_amp_test_cases.dart';

void main() {
  group('ManagedAgentHookInstallService', () {
    late Directory home;
    late ManagedAgentHookInstallService service;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('alera-hook-install-');
      service = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
      );
    });

    tearDown(() {
      if (home.existsSync()) {
        home.deleteSync(recursive: true);
      }
    });
    _registerGrokHookInstallerTests(() => home, () => service);
    _registerAmpHookInstallerTests(() => home, () => service);
    test('does not install Codex hooks into the user config', () {
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

      final status = service.install(AgentType.codex);
      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      expect(_commandsFor(hooks, 'PreToolUse'), <String>['echo user-hook']);
      expect(_managedCommandCount(hooks, 'alera-codex-hook.sh'), 0);
      expect(
        File(p.join(home.path, '.alera', 'agent-hooks')).existsSync(),
        isFalse,
      );
    });

    test('reports Codex hooks as runtime-only status', () {
      final status = service.status(AgentType.codex);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(status.detail, contains('runtime homes'));
    });

    test('does not install Claude hooks into the user config', () {
      final configPath = p.join(home.path, '.claude', 'settings.json');
      _writeJson(configPath, <String, Object?>{
        'hooks': <String, Object?>{
          'UserPromptSubmit': <Object?>[
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

      final status = service.install(AgentType.claude);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      final hooks = _hooks(configPath);
      expect(_managedCommandCount(hooks, 'alera-claude-hook.sh'), 0);
      expect(_commandsFor(hooks, 'UserPromptSubmit'), <String>[
        'echo user-hook',
      ]);
      expect(
        File(p.join(home.path, '.alera', 'agent-hooks')).existsSync(),
        isFalse,
      );
    });

    test('does not parse Claude settings because hooks are runtime-only', () {
      final configPath = p.join(home.path, '.claude', 'settings.json');
      File(configPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      expect(
        service.status(AgentType.claude).state,
        ManagedAgentHookInstallState.notInstalled,
      );
      expect(
        service.install(AgentType.claude).state,
        ManagedAgentHookInstallState.notInstalled,
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

    test('reports malformed JSON configs as errors', () {
      final configPath = p.join(home.path, '.cursor', 'hooks.json');
      File(configPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');

      final status = service.status(AgentType.cursor);
      final install = service.install(AgentType.cursor);
      final remove = service.remove(AgentType.cursor);

      expect(status.state, ManagedAgentHookInstallState.error);
      expect(install.state, ManagedAgentHookInstallState.error);
      expect(remove.state, ManagedAgentHookInstallState.error);
      expect(status.detail, contains('Could not parse Cursor hooks.json.'));
      expect(install.detail, contains('Could not parse Cursor hooks.json.'));
      expect(remove.detail, contains('Could not parse Cursor hooks.json.'));
    });

    test('reports partial Copilot configs when disabled or missing events', () {
      service.install(AgentType.copilot);
      final configPath = p.join(home.path, '.copilot', 'hooks', 'alera.json');
      final config = _readJson(configPath);
      config['disableAllHooks'] = true;
      _writeJson(configPath, config);

      final disabledStatus = service.status(AgentType.copilot);

      expect(disabledStatus.state, ManagedAgentHookInstallState.partial);
      expect(disabledStatus.detail, contains('disabled'));

      config.remove('disableAllHooks');
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      hooks.remove('Stop');
      config['hooks'] = hooks;
      _writeJson(configPath, config);

      final missingStatus = service.status(AgentType.copilot);

      expect(missingStatus.state, ManagedAgentHookInstallState.partial);
      expect(missingStatus.detail, contains('Stop'));
    });

    test('keeps existing managed scripts executable on reinstall', () {
      service.install(AgentType.copilot);
      final scriptPath = p.join(
        home.path,
        '.alera',
        'agent-hooks',
        'alera-copilot-hook.sh',
      );
      final before = File(scriptPath).readAsStringSync();

      final status = service.install(AgentType.copilot);

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(File(scriptPath).readAsStringSync(), before);
    });

    test('cleans stale managed commands from unmanaged Copilot events', () {
      final configPath = p.join(home.path, '.copilot', 'hooks', 'alera.json');
      final staleCommand = p.join(
        home.path,
        '.alera',
        'agent-hooks',
        'alera-copilot-hook.sh',
      );
      _writeJson(configPath, <String, Object?>{
        'hooks': <String, Object?>{
          'customEvent': <Object?>[
            <String, Object?>{'bash': staleCommand},
            <String, Object?>{'bash': 'echo keep'},
          ],
        },
      });

      service.install(AgentType.copilot);
      final hooks = _hooks(configPath);

      expect(_directCommandsFor(hooks, 'customEvent'), <String>['echo keep']);
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

    test('remove preserves user hooks nested beside managed commands', () {
      service.install(AgentType.copilot);
      final configPath = p.join(home.path, '.copilot', 'hooks', 'alera.json');
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      final managedCommand = p.join(
        home.path,
        '.alera',
        'agent-hooks',
        'alera-copilot-hook.sh',
      );
      hooks['Stop'] = <Object?>[
        <String, Object?>{
          'hooks': <Object?>[
            <String, Object?>{'type': 'command', 'command': managedCommand},
            <String, Object?>{'type': 'command', 'command': 'echo user stop'},
          ],
        },
      ];
      config['hooks'] = hooks;
      _writeJson(configPath, config);

      final status = service.remove(AgentType.copilot);
      final nextHooks = _hooks(configPath);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(_commandsFor(nextHooks, 'Stop'), <String>['echo user stop']);
    });

    test('installs Cursor hooks with top-level commands', () {
      final status = service.install(AgentType.cursor);
      final configPath = p.join(home.path, '.cursor', 'hooks.json');
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(config['version'], 1);
      expect(
        hooks.keys,
        containsAll(<String>[
          'beforeSubmitPrompt',
          'preToolUse',
          'postToolUse',
          'postToolUseFailure',
          'beforeShellExecution',
          'beforeMCPExecution',
          'afterAgentResponse',
          'stop',
        ]),
      );
      final promptDefinitions =
          hooks['beforeSubmitPrompt'] as List? ?? const <Object?>[];
      expect(promptDefinitions.single, isA<Map>());
      expect((promptDefinitions.single as Map)['bash'], isNull);
      expect((promptDefinitions.single as Map)['powershell'], isNull);
      expect(
        _directCommandsFor(hooks, 'beforeSubmitPrompt').single,
        contains('ALERA_CURSOR_HOOK_EVENT'),
      );
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-cursor-hook.sh'),
        ).readAsStringSync(),
        allOf(contains('/hook/cursor'), contains(r'payload=$(cat)')),
      );
    });

    test('installs Cursor hooks with cmd scripts on Windows', () {
      final windowsService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{'USERPROFILE': home.path},
      );

      final status = windowsService.install(AgentType.cursor);
      final configPath = p.join(home.path, '.cursor', 'hooks.json');
      final hooks = _hooks(configPath);
      final command = _directCommandsFor(hooks, 'beforeSubmitPrompt').single;

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(command, contains('ALERA_CURSOR_HOOK_EVENT'));
      expect(command, contains('alera-cursor-hook.cmd'));
      expect(command, isNot(contains('bash')));
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-cursor-hook.cmd'),
        ).readAsStringSync(),
        allOf(contains('/hook/cursor'), contains('ALERA_AGENT_HOOK_ENDPOINT')),
      );
    });

    test('installs Copilot PowerShell hooks on Windows with quoted paths', () {
      final quotedHome = Directory(p.join(home.path, "quoted'home"))
        ..createSync(recursive: true);
      final windowsService = ManagedAgentHookInstallService(
        homeDirectory: quotedHome.path,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{'USERPROFILE': quotedHome.path},
      );

      final status = windowsService.install(AgentType.copilot);
      final configPath = p.join(
        quotedHome.path,
        '.copilot',
        'hooks',
        'alera.json',
      );
      final hooks = _hooks(configPath);
      final command = _directCommandsFor(hooks, 'UserPromptSubmit').single;

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(command, contains(r'$env:ALERA_COPILOT_HOOK_EVENT'));
      expect(command, contains("quoted''home"));
      expect(command, contains('alera-copilot-hook.ps1'));
    });

    test('removes only Alera-managed Cursor hooks', () {
      service.install(AgentType.cursor);
      final configPath = p.join(home.path, '.cursor', 'hooks.json');
      final config = _readJson(configPath);
      final hooks = Map<String, Object?>.from(config['hooks'] as Map);
      hooks['preToolUse'] = <Object?>[
        <String, Object?>{'command': 'echo user cursor hook'},
        ...(hooks['preToolUse'] as List),
      ];
      config['hooks'] = hooks;
      _writeJson(configPath, config);

      final status = service.remove(AgentType.cursor);
      final nextHooks = _hooks(configPath);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(_directCommandsFor(nextHooks, 'preToolUse'), <String>[
        'echo user cursor hook',
      ]);
      expect(nextHooks['beforeSubmitPrompt'], isNull);
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

    test('installs AGY wrapper scripts on Windows', () {
      final windowsService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{'USERPROFILE': home.path},
      );

      final status = windowsService.install(AgentType.agy);
      final configPath = p.join(home.path, '.gemini', 'config', 'hooks.json');
      final bundle = Map<String, Object?>.from(
        _readJson(configPath)['alera-status'] as Map,
      );

      expect(status.state, ManagedAgentHookInstallState.installed);
      expect(
        _commandsFor(bundle, 'Stop').single,
        contains('alera-agy-stop.cmd'),
      );
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-stop.cmd'),
        ).readAsStringSync(),
        contains('ALERA_AGY_EVENT=Stop'),
      );
      expect(
        File(
          p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-hook.cmd'),
        ).readAsStringSync(),
        allOf(
          contains('/hook/agy'),
          contains(r'if ([string]::IsNullOrWhiteSpace($inputData)) { $payload=@{} }'),
        ),
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

    test('removes empty AGY bundles after deleting managed commands', () {
      service.install(AgentType.agy);

      final status = service.remove(AgentType.agy);
      final configPath = p.join(home.path, '.gemini', 'config', 'hooks.json');
      final config = _readJson(configPath);

      expect(status.state, ManagedAgentHookInstallState.notInstalled);
      expect(config.containsKey('alera-status'), isFalse);
    });

    test('installs and removes the managed OpenCode status plugin', () {
      final pluginPath = p.join(
        home.path,
        '.config',
        'opencode',
        'plugins',
        'alera-agent-status.js',
      );

      expect(
        service.status(AgentType.opencode).state,
        ManagedAgentHookInstallState.notInstalled,
      );
      expect(
        service.install(AgentType.opencode).state,
        ManagedAgentHookInstallState.installed,
      );
      expect(
        service.install(AgentType.opencode).state,
        ManagedAgentHookInstallState.installed,
      );

      final source = File(pluginPath).readAsStringSync();
      expect(source, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
      expect(source, contains('AleraOpenCodeStatusPlugin'));
      expect(source, contains('/hook/opencode'));
      expect(source, contains('ALERA_AGENT_HOOK_ENDPOINT'));

      final removed = service.remove(AgentType.opencode);
      expect(removed.state, ManagedAgentHookInstallState.notInstalled);
      expect(File(pluginPath).existsSync(), isFalse);
    });

    test('resolves OpenCode artifact paths from env and Windows defaults', () {
      final envPath = p.join(home.path, 'custom-opencode');
      final envService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{
          'HOME': home.path,
          'OPENCODE_CONFIG_DIR': envPath,
        },
      );
      expect(
        envService.install(AgentType.opencode).configPath,
        p.join(envPath, 'plugins', 'alera-agent-status.js'),
      );

      final appData = p.join(home.path, 'AppData', 'Roaming');
      final windowsService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{
          'USERPROFILE': home.path,
          'APPDATA': appData,
        },
      );
      expect(
        windowsService.install(AgentType.opencode).configPath,
        p.join(appData, 'opencode', 'plugins', 'alera-agent-status.js'),
      );
    });

    test('reports managed artifacts that need updating as partial', () {
      final pluginPath = p.join(
        home.path,
        '.config',
        'opencode',
        'plugins',
        'alera-agent-status.js',
      );
      File(pluginPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '// ALERA_AGENT_STATUS_MANAGED_FILE\n'
          'export default function stalePlugin() {}\n',
        );

      final status = service.status(AgentType.opencode);

      expect(status.state, ManagedAgentHookInstallState.partial);
      expect(status.managedHooksPresent, isTrue);
      expect(status.detail, contains('needs to be updated'));
    });

    test('installs the managed Pi extension under PI_CODING_AGENT_DIR', () {
      final piRoot = p.join(home.path, 'custom-pi');
      final piService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{
          'HOME': home.path,
          'PI_CODING_AGENT_DIR': piRoot,
        },
      );
      final extensionPath = p.join(
        piRoot,
        'extensions',
        'alera-agent-status.ts',
      );

      final status = piService.install(AgentType.pi);

      expect(status.state, ManagedAgentHookInstallState.installed);
      final source = File(extensionPath).readAsStringSync();
      expect(source, contains('ALERA_AGENT_STATUS_MANAGED_FILE'));
      expect(source, contains("pi.on('before_agent_start'"));
      expect(source, contains('/hook/pi'));
      expect(source, contains('ALERA_AGENT_HOOK_ENDPOINT'));
    });

    test('resolves Amp artifact paths from env and Windows defaults', () {
      final envPath = p.join(home.path, 'custom-amp');
      final envService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{
          'HOME': home.path,
          'AMP_CONFIG_DIR': envPath,
        },
      );
      expect(
        envService.install(AgentType.amp).configPath,
        p.join(envPath, 'plugins', 'alera-agent-status.ts'),
      );

      final windowsService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.windows,
        environment: <String, String>{'USERPROFILE': home.path},
      );
      expect(
        windowsService.install(AgentType.amp).configPath,
        p.join(home.path, '.config', 'amp', 'plugins', 'alera-agent-status.ts'),
      );
    });

    test('refuses to overwrite unmanaged OpenCode plugin files', () {
      final pluginPath = p.join(
        home.path,
        '.config',
        'opencode',
        'plugins',
        'alera-agent-status.js',
      );
      File(pluginPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('export const userPlugin = true;\n');

      final install = service.install(AgentType.opencode);
      final remove = service.remove(AgentType.opencode);

      expect(install.state, ManagedAgentHookInstallState.error);
      expect(remove.state, ManagedAgentHookInstallState.error);
      expect(
        File(pluginPath).readAsStringSync(),
        'export const userPlugin = true;\n',
      );
    });

    test('refuses to overwrite unmanaged Amp plugin files', () {
      final pluginPath = p.join(
        home.path,
        '.config',
        'amp',
        'plugins',
        'alera-agent-status.ts',
      );
      File(pluginPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('export default function userPlugin() {}\n');

      final install = service.install(AgentType.amp);
      final remove = service.remove(AgentType.amp);

      expect(install.state, ManagedAgentHookInstallState.error);
      expect(remove.state, ManagedAgentHookInstallState.error);
      expect(
        File(pluginPath).readAsStringSync(),
        'export default function userPlugin() {}\n',
      );
    });

    test(
      'bulk install, remove, and reconcile use every supported agent',
      () async {
        final installStatuses = await service.installAll();

        expect(installStatuses, hasLength(AgentType.values.length));
        expect(
          installStatuses.where(
            (status) => status.state == ManagedAgentHookInstallState.installed,
          ),
          isNotEmpty,
        );

        final reconcileStatuses = await service.reconcile(
          enabledAgentTypes: const <AgentType>{AgentType.copilot},
          agentTypes: const <AgentType>{AgentType.copilot, AgentType.cursor},
        );

        expect(reconcileStatuses.map((status) => status.agentType), <AgentType>[
          AgentType.copilot,
          AgentType.cursor,
        ]);
        expect(
          reconcileStatuses.first.state,
          ManagedAgentHookInstallState.installed,
        );
        expect(
          reconcileStatuses.last.state,
          ManagedAgentHookInstallState.notInstalled,
        );

        final removeStatuses = await service.removeAll();

        expect(removeStatuses, hasLength(AgentType.values.length));
        expect(
          removeStatuses.every(
            (status) =>
                status.state == ManagedAgentHookInstallState.notInstalled,
          ),
          isTrue,
        );
      },
    );

    test('throws when home cannot be resolved from the environment', () {
      expect(
        () => ManagedAgentHookInstallService(
          platform: ManagedAgentHookPlatform.posix,
          environment: const <String, String>{},
        ),
        throwsStateError,
      );
    });
  });
}
