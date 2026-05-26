import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:path/path.dart' as p;

part 'managed_hooks/agy_managed_agent_hook.dart';
part 'managed_hooks/amp_managed_agent_hook.dart';
part 'managed_hooks/claude_managed_agent_hook.dart';
part 'managed_hooks/codex_managed_agent_hook.dart';
part 'managed_hooks/copilot_managed_agent_hook.dart';
part 'managed_hooks/cursor_managed_agent_hook.dart';
part 'managed_hooks/opencode_managed_agent_hook.dart';
part 'managed_hooks/pi_managed_agent_hook.dart';

enum ManagedAgentHookInstallState { installed, notInstalled, partial, error }

enum ManagedAgentHookPlatform { posix, windows }

enum _AgentHookConfigShape { hooks, agyBundle }

enum _ManagedHookDefinitionShape {
  nestedCommand,
  directCommand,
  topLevelCommand,
  agyToolCommand,
}

const String _managedArtifactMarker = 'ALERA_AGENT_STATUS_MANAGED_FILE';

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
  }) : _environment = environment ?? Platform.environment,
       _homeDirectory = homeDirectory ?? _resolveHome(environment),
       _platform =
           platform ??
           (Platform.isWindows
               ? ManagedAgentHookPlatform.windows
               : ManagedAgentHookPlatform.posix);

  final Map<String, String> _environment;
  final String _homeDirectory;
  final ManagedAgentHookPlatform _platform;

  ManagedAgentHookInstallStatus status(AgentType agentType) {
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _managedArtifactStatus(artifact);
    }
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
    final hooks = _hookContainer(config, descriptor);
    for (final event in descriptor.events) {
      final command = _managedCommand(descriptor: descriptor, event: event);
      final definitions = _definitionsFromValue(hooks[event.eventName]);
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
    if (descriptor.agentType == AgentType.copilot &&
        config['disableAllHooks'] == true &&
        managedHooksPresent) {
      return ManagedAgentHookInstallStatus(
        agentType: agentType,
        state: ManagedAgentHookInstallState.partial,
        configPath: descriptor.configPath,
        managedHooksPresent: true,
        detail: 'Managed Copilot hook file is disabled.',
      );
    }
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
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      final current = _managedArtifactStatus(artifact);
      if (current.state == ManagedAgentHookInstallState.error) {
        return current;
      }
      _writeManagedArtifact(artifact);
      return _managedArtifactStatus(artifact);
    }
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

    final hooks = _hookContainer(config, descriptor);
    final managedEvents = descriptor.events
        .map((event) => event.eventName)
        .toSet();
    for (final entry in hooks.entries.toList(growable: false)) {
      if (managedEvents.contains(entry.key)) {
        continue;
      }
      final definitions = _definitionsFromValue(entry.value);
      final cleaned = _removeManagedCommands(
        definitions,
        descriptor.managedScriptFileNames,
      );
      if (cleaned.isEmpty) {
        hooks.remove(entry.key);
      } else {
        hooks[entry.key] = cleaned;
      }
    }
    for (final event in descriptor.events) {
      final current = _definitionsFromValue(hooks[event.eventName]);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.managedScriptFileNames,
      );
      final definition = _managedHookDefinition(
        descriptor,
        event,
        _managedCommand(descriptor: descriptor, event: event),
      );
      hooks[event.eventName] = <Object?>[...cleaned, definition];
    }
    _setHookContainer(config, descriptor, hooks);
    if (descriptor.agentType == AgentType.copilot) {
      config['version'] = 1;
      config.remove('disableAllHooks');
    }
    if (descriptor.agentType == AgentType.cursor) {
      config['version'] ??= 1;
    }
    _writeManagedScript(
      descriptor.scriptPath,
      _managedScript(descriptor: descriptor),
    );
    for (final wrapper in descriptor.windowsWrappers.entries) {
      _writeManagedScript(wrapper.key, wrapper.value);
    }
    _writeJsonObject(descriptor.configPath, config);
    return status(agentType);
  }

  ManagedAgentHookInstallStatus remove(AgentType agentType) {
    final artifact = _managedArtifact(agentType);
    if (artifact != null) {
      return _removeManagedArtifact(artifact);
    }
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
    final hooks = _hookContainer(config, descriptor);
    var changed = false;
    for (final entry in hooks.entries.toList(growable: false)) {
      final definitions = _definitionsFromValue(entry.value);
      final cleaned = _removeManagedCommands(
        definitions,
        descriptor.managedScriptFileNames,
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
      _setHookContainer(config, descriptor, hooks);
      _writeJsonObject(descriptor.configPath, config);
    }
    return status(agentType);
  }

  Future<List<ManagedAgentHookInstallStatus>> installAll() async {
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values) install(agentType),
    ];
  }

  Future<List<ManagedAgentHookInstallStatus>> removeAll() async {
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values) remove(agentType),
    ];
  }

  Future<List<ManagedAgentHookInstallStatus>> reconcile({
    required Iterable<AgentType> enabledAgentTypes,
  }) async {
    final enabled = enabledAgentTypes.toSet();
    return <ManagedAgentHookInstallStatus>[
      for (final agentType in AgentType.values)
        enabled.contains(agentType) ? install(agentType) : remove(agentType),
    ];
  }

  _AgentHookDescriptor _descriptor(AgentType agentType) {
    final extension = switch ((agentType, _platform)) {
      (AgentType.copilot, ManagedAgentHookPlatform.windows) => 'ps1',
      (_, ManagedAgentHookPlatform.windows) => 'cmd',
      (_, ManagedAgentHookPlatform.posix) => 'sh',
    };
    final scriptFileName = 'alera-${agentType.key}-hook.$extension';
    final scriptPath = p.join(
      _homeDirectory,
      '.alera',
      'agent-hooks',
      scriptFileName,
    );
    return switch (agentType) {
      AgentType.codex => _codexDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.claude => _claudeDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.copilot => _copilotDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.cursor => _cursorDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.agy => _agyDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.opencode ||
      AgentType.pi ||
      AgentType.amp => throw ArgumentError.value(
        agentType,
        'agentType',
        'Managed artifact agents do not use JSON hook descriptors.',
      ),
    };
  }

  _ManagedHookArtifact? _managedArtifact(AgentType agentType) {
    return switch (agentType) {
      AgentType.opencode => _opencodeArtifact(),
      AgentType.pi => _piArtifact(),
      AgentType.amp => _ampArtifact(),
      AgentType.codex ||
      AgentType.claude ||
      AgentType.copilot ||
      AgentType.cursor ||
      AgentType.agy => null,
    };
  }

  ManagedAgentHookInstallStatus _managedArtifactStatus(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: artifact.path,
        managedHooksPresent: false,
      );
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Rename it before enabling this hook.',
      );
    }
    if (content == artifact.content) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.installed,
        configPath: artifact.path,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: artifact.agentType,
      state: ManagedAgentHookInstallState.partial,
      configPath: artifact.path,
      managedHooksPresent: true,
      detail: 'Managed ${artifact.label} needs to be updated.',
    );
  }

  ManagedAgentHookInstallStatus _removeManagedArtifact(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return _managedArtifactStatus(artifact);
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Refusing to remove it.',
      );
    }
    file.deleteSync();
    return _managedArtifactStatus(artifact);
  }

  void _writeManagedArtifact(_ManagedHookArtifact artifact) {
    final file = File(artifact.path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == artifact.content) {
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(artifact.content);
    tmp.renameSync(artifact.path);
  }

  String _managedCommand({
    required _AgentHookDescriptor descriptor,
    required _ManagedHookEvent event,
  }) {
    if (descriptor.agentType == AgentType.agy &&
        _platform == ManagedAgentHookPlatform.windows) {
      return _agyWindowsWrapperPath(event.eventName);
    }
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(descriptor.scriptPath)} ]; then '
            '${descriptor.eventEnvVar}=${_shQuote(event.eventName)} '
            '/bin/sh ${_shQuote(descriptor.scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        descriptor.agentType == AgentType.copilot
            ? '\$env:${descriptor.eventEnvVar} = \'${_powerShellSingleQuote(event.eventName)}\'; '
                  'powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
                  '${_powerShellPath(descriptor.scriptPath)}'
            : 'cmd /d /s /c "if exist ""${descriptor.scriptPath}"" '
                  '(set ${descriptor.eventEnvVar}=${event.eventName}&& call ""${descriptor.scriptPath}"")"',
    };
  }

  String _managedScript({required _AgentHookDescriptor descriptor}) {
    final source = descriptor.agentType.key;
    if (descriptor.agentType == AgentType.agy) {
      return _agyManagedScript(descriptor);
    }
    final eventEnvVar = descriptor.eventEnvVar;
    if (_platform == ManagedAgentHookPlatform.windows) {
      if (descriptor.agentType == AgentType.copilot) {
        return _windowsPowerShellManagedScript(
          source: source,
          eventEnvVar: eventEnvVar,
          writeEmptyResponse: true,
        );
      }
      return <String>[
        '@echo off',
        'setlocal',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(source, eventEnvVar),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
      if (descriptor.agentType == AgentType.copilot) "printf '{}\\n'",
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
      '  --data-urlencode "hookEventName=\${$eventEnvVar}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _windowsPostCommand(String source, String eventEnvVar) {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:$eventEnvVar; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/$source\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
  }

  Map<String, Object?> _managedHookDefinition(
    _AgentHookDescriptor descriptor,
    _ManagedHookEvent event,
    String command,
  ) {
    final shape = event.definitionShape ?? descriptor.definitionShape;
    return switch (shape) {
      _ManagedHookDefinitionShape.nestedCommand => <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{'type': 'command', 'command': command},
        ],
      },
      _ManagedHookDefinitionShape.directCommand => <String, Object?>{
        'type': 'command',
        if (_platform == ManagedAgentHookPlatform.windows)
          'powershell': command
        else
          'bash': command,
        'timeoutSec': 5,
      },
      _ManagedHookDefinitionShape.topLevelCommand => <String, Object?>{
        'command': command,
      },
      _ManagedHookDefinitionShape.agyToolCommand => <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{'type': 'command', 'command': command},
        ],
      },
    };
  }

  Map<String, Object?> _hookContainer(
    Map<String, Object?> config,
    _AgentHookDescriptor descriptor,
  ) {
    return switch (descriptor.configShape) {
      _AgentHookConfigShape.hooks => _hooksMap(config),
      _AgentHookConfigShape.agyBundle => _mapFromValue(
        config[descriptor.bundleName],
      ),
    };
  }

  void _setHookContainer(
    Map<String, Object?> config,
    _AgentHookDescriptor descriptor,
    Map<String, Object?> hooks,
  ) {
    switch (descriptor.configShape) {
      case _AgentHookConfigShape.hooks:
        config['hooks'] = hooks;
      case _AgentHookConfigShape.agyBundle:
        if (hooks.isEmpty) {
          config.remove(descriptor.bundleName);
        } else {
          config[descriptor.bundleName] = hooks;
        }
    }
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

  String _windowsPowerShellManagedScript({
    required String source,
    required String eventEnvVar,
    required bool writeEmptyResponse,
  }) {
    return <String>[
      if (writeEmptyResponse) "Write-Output '{}'",
      'if (\$env:ALERA_AGENT_HOOK_ENDPOINT -and (Test-Path -LiteralPath \$env:ALERA_AGENT_HOOK_ENDPOINT)) {',
      '  try {',
      '    Get-Content -LiteralPath \$env:ALERA_AGENT_HOOK_ENDPOINT | ForEach-Object {',
      "      if (\$_ -match '^set ([A-Za-z0-9_]+)=(.*)\$') {",
      "        [Environment]::SetEnvironmentVariable(\$matches[1], \$matches[2], 'Process')",
      '      }',
      '    }',
      '  } catch {}',
      '}',
      'if (-not \$env:ALERA_AGENT_HOOK_PORT -or -not \$env:ALERA_AGENT_HOOK_TOKEN -or -not \$env:ALERA_TERMINAL_SESSION_ID -or -not \$env:ALERA_WORKSPACE_ID -or -not \$env:ALERA_TAB_ID) { exit 0 }',
      '\$inputData = [Console]::In.ReadToEnd()',
      'if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }',
      'try {',
      '  \$payload = \$inputData | ConvertFrom-Json',
      '  \$body = @{',
      '    terminalSessionId = \$env:ALERA_TERMINAL_SESSION_ID',
      '    workspaceId = \$env:ALERA_WORKSPACE_ID',
      '    tabId = \$env:ALERA_TAB_ID',
      '    hookEventName = \$env:$eventEnvVar',
      '    version = \$env:ALERA_AGENT_HOOK_VERSION',
      '    payload = \$payload',
      '  } | ConvertTo-Json -Depth 100',
      "  Invoke-WebRequest -UseBasicParsing -Method Post -Uri ('http://127.0.0.1:' + \$env:ALERA_AGENT_HOOK_PORT + '/hook/$source') -Headers @{ 'Content-Type'='application/json'; '$aleraAgentHookTokenHeader'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$body -TimeoutSec 2 | Out-Null",
      '} catch {}',
      'exit 0',
      '',
    ].join('\r\n');
  }

  Map<String, Object?> _mapFromValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return <String, Object?>{};
  }

  Map<String, Object?> _hooksMap(Map<String, Object?> config) {
    return _mapFromValue(config['hooks']);
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
    List<String> scriptFileNames,
  ) {
    return definitions
        .expand((definition) {
          final next = <String, Object?>{...definition};
          for (final key in const <String>['command', 'bash', 'powershell']) {
            if (_isManagedCommand(next[key], scriptFileNames)) {
              next.remove(key);
            }
          }
          final hooks = next['hooks'];
          if (hooks is List) {
            final cleanedHooks = <Object?>[
              for (final hook in hooks)
                if (hook is! Map ||
                    !_isManagedCommand(hook['command'], scriptFileNames))
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

  bool _isManagedCommand(Object? command, List<String> scriptFileNames) {
    if (command is! String) {
      return false;
    }
    final normalized = command.replaceAll(r'\', '/');
    return scriptFileNames.any(
      (scriptFileName) => normalized.contains('agent-hooks/$scriptFileName'),
    );
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
  _AgentHookDescriptor({
    required this.agentType,
    required this.configPath,
    required this.configLabel,
    required this.scriptFileName,
    required this.scriptPath,
    required this.eventEnvVar,
    required this.configShape,
    required this.definitionShape,
    required this.events,
    this.bundleName = 'hooks',
    List<String>? managedScriptFileNames,
    this.windowsWrappers = const <String, String>{},
  }) : managedScriptFileNames =
           managedScriptFileNames ?? <String>[scriptFileName];

  final AgentType agentType;
  final String configPath;
  final String configLabel;
  final String scriptFileName;
  final String scriptPath;
  final String eventEnvVar;
  final _AgentHookConfigShape configShape;
  final _ManagedHookDefinitionShape definitionShape;
  final String bundleName;
  final List<String> managedScriptFileNames;
  final Map<String, String> windowsWrappers;
  final List<_ManagedHookEvent> events;
}

class _ManagedHookArtifact {
  const _ManagedHookArtifact({
    required this.agentType,
    required this.label,
    required this.path,
    required this.content,
  });

  final AgentType agentType;
  final String label;
  final String path;
  final String content;
}

class _ManagedHookEvent {
  const _ManagedHookEvent(this.eventName, {this.matcher, this.definitionShape});

  final String eventName;
  final String? matcher;
  final _ManagedHookDefinitionShape? definitionShape;
}

String _shQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _powerShellSingleQuote(String value) => value.replaceAll("'", "''");

String _powerShellPath(String value) => "'${_powerShellSingleQuote(value)}'";
