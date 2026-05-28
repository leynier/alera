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
    final tmp = File(tmpPath)..writeAsStringSync(serialized);
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
