import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:path/path.dart' as p;

enum ManagedAgentHookInstallState { installed, notInstalled, partial, error }

enum ManagedAgentHookPlatform { posix, windows }

class ManagedAgentHookInstallStatus {
  const ManagedAgentHookInstallStatus({
    required this.agentType,
    required this.state,
    required this.configPath,
    required this.managedHooksPresent,
    this.detail,
  });

  final AgentType agentType;
  final ManagedAgentHookInstallState state;
  final String configPath;
  final bool managedHooksPresent;
  final String? detail;
}

class ManagedAgentHookInstallService {
  ManagedAgentHookInstallService({
    String? homeDirectory,
    ManagedAgentHookPlatform? platform,
    Map<String, String>? environment,
  }) : _homeDirectory = homeDirectory ?? _resolveHome(environment),
       _platform =
           platform ??
           (Platform.isWindows
               ? ManagedAgentHookPlatform.windows
               : ManagedAgentHookPlatform.posix);

  final String _homeDirectory;
  final ManagedAgentHookPlatform _platform;

  ManagedAgentHookInstallStatus status(AgentType agentType) {
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }
    final missing = <String>[];
    var presentCount = 0;
    for (final event in descriptor.events) {
      final command = _managedCommand(
        scriptPath: descriptor.scriptPath,
        eventName: event.eventName,
      );
      final definitions = _definitionsFor(config, event.eventName);
      final hasCommand = definitions.any(
        (definition) => _definitionHasCommand(definition, command),
      );
      if (hasCommand) {
        presentCount += 1;
      } else {
        missing.add(event.eventName);
      }
    }
    final managedHooksPresent = presentCount > 0;
    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.installed,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: agentType,
      state: ManagedAgentHookInstallState.partial,
      configPath: descriptor.configPath,
      managedHooksPresent: managedHooksPresent,
      detail: 'Managed hook missing for events: ${missing.join(', ')}.',
    );
  }

  ManagedAgentHookInstallStatus install(AgentType agentType) {
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }

    final hooks = _hooksMap(config);
    for (final event in descriptor.events) {
      final current = _definitionsFor(config, event.eventName);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.scriptFileName,
      );
      final definition = <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{
            'type': 'command',
            'command': _managedCommand(
              scriptPath: descriptor.scriptPath,
              eventName: event.eventName,
            ),
          },
        ],
      };
      hooks[event.eventName] = <Object?>[...cleaned, definition];
    }
    config['hooks'] = hooks;
    _writeManagedScript(
      descriptor.scriptPath,
      _managedScript(agentType: agentType),
    );
    _writeJsonObject(descriptor.configPath, config);
    return status(agentType);
  }

  ManagedAgentHookInstallStatus remove(AgentType agentType) {
    final descriptor = _descriptor(agentType);
    final config = _readJsonObject(descriptor.configPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: descriptor.configPath,
        managedHooksPresent: false,
        detail: 'Could not parse ${descriptor.configLabel}.',
      );
    }
    final hooks = _hooksMap(config);
    var changed = false;
    for (final entry in hooks.entries.toList(growable: false)) {
      final definitions = _definitionsFromValue(entry.value);
      final cleaned = _removeManagedCommands(
        definitions,
        descriptor.scriptFileName,
      );
      if (jsonEncode(cleaned) != jsonEncode(definitions)) {
        changed = true;
      }
      if (cleaned.isEmpty) {
        hooks.remove(entry.key);
      } else {
        hooks[entry.key] = cleaned;
      }
    }
    if (changed) {
      config['hooks'] = hooks;
      _writeJsonObject(descriptor.configPath, config);
    }
    return status(agentType);
  }

  Future<List<ManagedAgentHookInstallStatus>> installAll() async {
    return <ManagedAgentHookInstallStatus>[
      install(AgentType.codex),
      install(AgentType.claude),
    ];
  }

  Future<List<ManagedAgentHookInstallStatus>> removeAll() async {
    return <ManagedAgentHookInstallStatus>[
      remove(AgentType.codex),
      remove(AgentType.claude),
    ];
  }

  _AgentHookDescriptor _descriptor(AgentType agentType) {
    final extension = _platform == ManagedAgentHookPlatform.windows
        ? 'cmd'
        : 'sh';
    final scriptFileName = 'alera-${agentType.key}-hook.$extension';
    final scriptPath = p.join(
      _homeDirectory,
      '.alera',
      'agent-hooks',
      scriptFileName,
    );
    return switch (agentType) {
      AgentType.codex => _AgentHookDescriptor(
        configPath: p.join(_homeDirectory, '.codex', 'hooks.json'),
        configLabel: 'Codex hooks.json',
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
        events: const <_ManagedHookEvent>[
          _ManagedHookEvent('SessionStart'),
          _ManagedHookEvent('UserPromptSubmit'),
          _ManagedHookEvent('PreToolUse'),
          _ManagedHookEvent('PostToolUse'),
          _ManagedHookEvent('PermissionRequest'),
          _ManagedHookEvent('Stop'),
        ],
      ),
      AgentType.claude => _AgentHookDescriptor(
        configPath: p.join(_homeDirectory, '.claude', 'settings.json'),
        configLabel: 'Claude settings.json',
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
        events: const <_ManagedHookEvent>[
          _ManagedHookEvent('UserPromptSubmit'),
          _ManagedHookEvent('Stop'),
          _ManagedHookEvent('PreToolUse', matcher: '*'),
          _ManagedHookEvent('PostToolUse', matcher: '*'),
          _ManagedHookEvent('PostToolUseFailure', matcher: '*'),
          _ManagedHookEvent('PermissionRequest', matcher: '*'),
        ],
      ),
    };
  }

  String _managedCommand({
    required String scriptPath,
    required String eventName,
  }) {
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(scriptPath)} ]; then '
            'ALERA_AGENT_HOOK_EVENT=${_shQuote(eventName)} '
            '/bin/sh ${_shQuote(scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        'cmd /d /s /c "if exist ""$scriptPath"" '
            '(set ALERA_AGENT_HOOK_EVENT=$eventName&& call ""$scriptPath"")"',
    };
  }

  String _managedScript({required AgentType agentType}) {
    final source = agentType.key;
    if (_platform == ManagedAgentHookPlatform.windows) {
      return <String>[
        '@echo off',
        'setlocal',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(source),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
      'if [ -n "\$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -r "\$ALERA_AGENT_HOOK_ENDPOINT" ]; then',
      '  . "\$ALERA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :',
      'fi',
      'if [ -z "\$ALERA_AGENT_HOOK_PORT" ] || [ -z "\$ALERA_AGENT_HOOK_TOKEN" ] || [ -z "\$ALERA_TERMINAL_SESSION_ID" ] || [ -z "\$ALERA_WORKSPACE_ID" ] || [ -z "\$ALERA_TAB_ID" ]; then',
      '  exit 0',
      'fi',
      'payload=\$(cat)',
      'if [ -z "\$payload" ]; then',
      '  exit 0',
      'fi',
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/$source" \\',
      '  -H "Content-Type: application/x-www-form-urlencoded" \\',
      '  -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '  --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '  --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '  --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '  --data-urlencode "hookEventName=\${ALERA_AGENT_HOOK_EVENT}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _windowsPostCommand(String source) {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:ALERA_AGENT_HOOK_EVENT; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/$source\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
  }

  Map<String, Object?>? _readJsonObject(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is Map) {
        return Map<String, Object?>.from(parsed);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _writeJsonObject(String path, Map<String, Object?> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final serialized =
        '${const JsonEncoder.withIndent('  ').convert(config)}\n';
    if (file.existsSync() && file.readAsStringSync() == serialized) {
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath);
    tmp.writeAsStringSync(serialized);
    if (file.existsSync()) {
      file.copySync('$path.bak');
    }
    tmp.renameSync(path);
  }

  void _writeManagedScript(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == content) {
      if (_platform == ManagedAgentHookPlatform.posix) {
        Process.runSync('chmod', <String>['755', path]);
      }
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(content);
    if (_platform == ManagedAgentHookPlatform.posix) {
      Process.runSync('chmod', <String>['755', tmpPath]);
    }
    tmp.renameSync(path);
  }

  Map<String, Object?> _hooksMap(Map<String, Object?> config) {
    final hooks = config['hooks'];
    if (hooks is Map) {
      return Map<String, Object?>.from(hooks);
    }
    return <String, Object?>{};
  }

  List<Map<String, Object?>> _definitionsFor(
    Map<String, Object?> config,
    String eventName,
  ) {
    return _definitionsFromValue(_hooksMap(config)[eventName]);
  }

  List<Map<String, Object?>> _definitionsFromValue(Object? value) {
    if (value is! List) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      for (final item in value)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  bool _definitionHasCommand(Map<String, Object?> definition, String command) {
    if (definition['command'] == command ||
        definition['bash'] == command ||
        definition['powershell'] == command) {
      return true;
    }
    final hooks = definition['hooks'];
    if (hooks is! List) {
      return false;
    }
    return hooks.any((hook) => hook is Map && hook['command'] == command);
  }

  List<Map<String, Object?>> _removeManagedCommands(
    List<Map<String, Object?>> definitions,
    String scriptFileName,
  ) {
    return definitions
        .expand((definition) {
          final next = <String, Object?>{...definition};
          for (final key in const <String>['command', 'bash', 'powershell']) {
            if (_isManagedCommand(next[key], scriptFileName)) {
              next.remove(key);
            }
          }
          final hooks = next['hooks'];
          if (hooks is List) {
            final cleanedHooks = <Object?>[
              for (final hook in hooks)
                if (hook is! Map ||
                    !_isManagedCommand(hook['command'], scriptFileName))
                  hook,
            ];
            if (cleanedHooks.isEmpty) {
              next.remove('hooks');
            } else {
              next['hooks'] = cleanedHooks;
            }
          }
          final hasCommand =
              next['command'] is String ||
              next['bash'] is String ||
              next['powershell'] is String ||
              (next['hooks'] is List && (next['hooks'] as List).isNotEmpty);
          return hasCommand
              ? <Map<String, Object?>>[next]
              : const <Map<String, Object?>>[];
        })
        .toList(growable: false);
  }

  bool _isManagedCommand(Object? command, String scriptFileName) {
    if (command is! String) {
      return false;
    }
    return command
        .replaceAll(r'\', '/')
        .contains('agent-hooks/$scriptFileName');
  }

  static String _resolveHome(Map<String, String>? environment) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.trim().isEmpty) {
      throw StateError('Could not resolve the user home directory.');
    }
    return home;
  }
}

class _AgentHookDescriptor {
  const _AgentHookDescriptor({
    required this.configPath,
    required this.configLabel,
    required this.scriptFileName,
    required this.scriptPath,
    required this.events,
  });

  final String configPath;
  final String configLabel;
  final String scriptFileName;
  final String scriptPath;
  final List<_ManagedHookEvent> events;
}

class _ManagedHookEvent {
  const _ManagedHookEvent(this.eventName, {this.matcher});

  final String eventName;
  final String? matcher;
}

String _shQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}
