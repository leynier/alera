part of 'claude_runtime_home_service.dart';

extension _ClaudeRuntimeHooks on ClaudeRuntimeHomeService {
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
    // Follow a symlink so a private settings file is updated in place. CCS
    // install targets are regular settings.local.json files; callers skip
    // anything that resolves into ~/.claude.
    final targetPath = _resolvedWritablePath(path);
    final file = File(targetPath);
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
    final tmp = File(tmpPath)..writeAsStringSync(serialized);
    tmp.renameSync(targetPath);
  }

  /// Absolute path to write, following a symlink when [path] is one.
  String _resolvedWritablePath(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      try {
        return Link(path).resolveSymbolicLinksSync();
      } catch (_) {
        return path;
      }
    }
    return path;
  }

  /// Install Alera-managed Claude status hooks into [settingsPath].
  ///
  /// When [baseConfig] is provided (runtime home), it is used as the starting
  /// document. Otherwise the existing file at [settingsPath] is merged so
  /// external homes (CCS shared settings) keep user/Orca hooks.
  bool _installManagedHooksAtSettings({
    required String settingsPath,
    required _ClaudeRuntimeHookDescriptor descriptor,
    Map<String, Object?>? baseConfig,
  }) {
    final existing = baseConfig ?? _readJsonObject(settingsPath);
    if (existing == null) {
      return false;
    }
    if (baseConfig == null &&
        _managedHooksComplete(existing, descriptor.managedScriptFileNames)) {
      return true;
    }
    final nextConfig = <String, Object?>{...existing};
    final hooks = _hooksMap(nextConfig);
    for (final entry in hooks.entries.toList(growable: false)) {
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
    for (final event in _claudeEvents) {
      final current = _definitionsFromValue(hooks[event.eventName]);
      final cleaned = _removeManagedCommands(
        current,
        descriptor.managedScriptFileNames,
      );
      hooks[event.eventName] = <Object?>[
        ...cleaned,
        _managedHookDefinition(
          event,
          _managedCommand(descriptor: descriptor, event: event),
        ),
      ];
    }
    nextConfig['hooks'] = hooks;
    _writeJsonObject(settingsPath, nextConfig);
    return true;
  }

  bool _removeManagedHooksAtSettings({
    required String settingsPath,
    required _ClaudeRuntimeHookDescriptor descriptor,
  }) {
    final config = _readJsonObject(settingsPath);
    if (config == null) {
      return false;
    }
    final hooks = _hooksMap(config);
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
      config['hooks'] = hooks;
      _writeJsonObject(settingsPath, config);
    }
    return true;
  }

  /// Status of managed hooks for a single settings.json.
  ManagedAgentHookInstallStatus _statusForSettings({
    required String settingsPath,
    required _ClaudeRuntimeHookDescriptor descriptor,
  }) {
    final config = _readJsonObject(settingsPath);
    if (config == null) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.error,
        configPath: settingsPath,
        managedHooksPresent: false,
        detail: 'Could not parse Claude settings.json.',
      );
    }

    final missing = <String>[];
    var presentCount = 0;
    final hooks = _hooksMap(config);
    for (final event in _claudeEvents) {
      final definitions = _definitionsFromValue(hooks[event.eventName]);
      final hasCommand = definitions.any(
        (definition) => _definitionHasManagedCommand(
          definition,
          descriptor.managedScriptFileNames,
        ),
      );
      if (hasCommand) {
        presentCount += 1;
      } else {
        missing.add(event.eventName);
      }
    }

    if (presentCount == 0) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: settingsPath,
        managedHooksPresent: false,
      );
    }
    if (missing.isEmpty) {
      return ManagedAgentHookInstallStatus(
        agentType: AgentType.claude,
        state: ManagedAgentHookInstallState.installed,
        configPath: settingsPath,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.claude,
      state: ManagedAgentHookInstallState.partial,
      configPath: settingsPath,
      managedHooksPresent: true,
      detail: 'Managed hook missing for events: ${missing.join(', ')}.',
    );
  }

  void _writeManagedScript(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == content) {
      if (_platform == ManagedAgentHookPlatform.posix && !Platform.isWindows) {
        setPosixFileMode(path, posixExecutableFileMode);
      }
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(content);
    if (_platform == ManagedAgentHookPlatform.posix && !Platform.isWindows) {
      setPosixFileMode(tmpPath, posixExecutableFileMode);
    }
    tmp.renameSync(path);
  }

  String _managedCommand({
    required _ClaudeRuntimeHookDescriptor descriptor,
    required _ClaudeHookEvent event,
  }) {
    return switch (_platform) {
      ManagedAgentHookPlatform.posix =>
        'if [ -x ${_shQuote(descriptor.scriptPath)} ]; then '
            'ALERA_AGENT_HOOK_EVENT=${_shQuote(event.eventName)} '
            '/bin/sh ${_shQuote(descriptor.scriptPath)}; fi',
      ManagedAgentHookPlatform.windows =>
        'cmd /d /s /c "if exist ""${descriptor.scriptPath}"" '
            '(set ALERA_AGENT_HOOK_EVENT=${event.eventName}&& call ""${descriptor.scriptPath}"")"',
    };
  }

  Map<String, Object?> _managedHookDefinition(
    _ClaudeHookEvent event,
    String command,
  ) {
    return <String, Object?>{
      if (event.matcher != null) 'matcher': event.matcher,
      'hooks': <Object?>[
        <String, Object?>{'type': 'command', 'command': command},
      ],
    };
  }

  String _managedScript() {
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
        _windowsPostCommand(),
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
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/claude" \\',
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

  String _windowsPostCommand() {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:ALERA_AGENT_HOOK_EVENT; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/claude\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes | Out-Null } catch {}"';
  }

  Map<String, Object?> _hooksMap(Map<String, Object?> config) {
    final hooks = config['hooks'];
    if (hooks is Map) {
      return Map<String, Object?>.from(hooks);
    }
    return <String, Object?>{};
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

  bool _managedHooksComplete(
    Map<String, Object?> config,
    Set<String> scriptFileNames,
  ) {
    final hooks = _hooksMap(config);
    return _claudeEvents.every((event) {
      final definitions = _definitionsFromValue(hooks[event.eventName]);
      return definitions.any(
        (definition) =>
            _definitionHasManagedCommand(definition, scriptFileNames),
      );
    });
  }

  bool _definitionHasManagedCommand(
    Map<String, Object?> definition,
    Set<String> scriptFileNames,
  ) {
    for (final key in const <String>['command', 'bash', 'powershell']) {
      if (_isManagedCommand(definition[key], scriptFileNames)) {
        return true;
      }
    }
    final hooks = definition['hooks'];
    if (hooks is! List) {
      return false;
    }
    return hooks.any(
      (hook) =>
          hook is Map && _isManagedCommand(hook['command'], scriptFileNames),
    );
  }

  List<Map<String, Object?>> _removeManagedCommands(
    List<Map<String, Object?>> definitions,
    Set<String> scriptFileNames,
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

  bool _isManagedCommand(Object? command, Set<String> scriptFileNames) {
    if (command is! String) {
      return false;
    }
    final normalized = command.replaceAll(r'\', '/');
    return scriptFileNames.any(
      (scriptFileName) => normalized.contains('agent-hooks/$scriptFileName'),
    );
  }

  bool _samePath(String left, String right) {
    return _absoluteNormalizedPath(left) == _absoluteNormalizedPath(right);
  }

  String _absoluteNormalizedPath(String path) {
    final absolute = p.isAbsolute(path) ? path : p.absolute(path);
    return p.normalize(absolute);
  }
}
