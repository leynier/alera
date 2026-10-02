part of 'managed_agent_hook_installer.dart';

extension _ManagedAgentHookScripts on ManagedAgentHookInstallService {
  String _managedCommand({
    required _AgentHookDescriptor descriptor,
    required _ManagedHookEvent event,
  }) {
    if (descriptor.agentType == AgentType.agy &&
        _platform == ManagedAgentHookPlatform.windows) {
      // Quoted so a profile path containing a space stays one token once AGY
      // hands the command to cmd.
      return '"${_agyWindowsWrapperPath(event.eventName)}"';
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

  // coverage:ignore-start
  // External shell/cmd hook templates. Installer tests verify selection and
  // persistence; exercising each literal line belongs to agent CLI smoke tests.
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
      'attempt=0',
      'while [ "\$attempt" -lt 3 ]; do',
      '  httpCode=\$(curl -sS --connect-timeout 0.2 --max-time 0.5 -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/$source" \\',
      '    -H "Content-Type: application/x-www-form-urlencoded" \\',
      '    -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '    --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '    --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '    --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '    --data-urlencode "hookEventName=\${$eventEnvVar}" \\',
      '    --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '    --data-urlencode "payload=\${payload}" --write-out "%{http_code}" --output /dev/null 2>/dev/null)',
      '  curlStatus=\$?',
      '  if [ "\$curlStatus" -eq 0 ] && [ "\$httpCode" != "429" ] && [ "\$httpCode" != "503" ]; then',
      '    break',
      '  fi',
      '  if [ "\$attempt" -ge 2 ]; then',
      '    break',
      '  fi',
      '  if [ "\$attempt" -eq 0 ]; then sleep 0.05; else sleep 0.1; fi',
      '  attempt=\$((attempt + 1))',
      'done',
      'exit 0',
      '',
    ].join('\n');
  }
  // coverage:ignore-end

  String _windowsPostCommand(
    String source,
    String eventEnvVar, {
    String? emptyPayloadFallbackEvent,
    bool allowEmptyPayload = false,
  }) {
    final inputScript = allowEmptyPayload
        ? 'if ([string]::IsNullOrWhiteSpace(\$inputData)) { \$payload=@{} } else { \$payload=(\$inputData | ConvertFrom-Json) };'
        : emptyPayloadFallbackEvent == null
        ? 'if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; \$payload=(\$inputData | ConvertFrom-Json);'
        : 'if ([string]::IsNullOrWhiteSpace(\$inputData)) { if (\$env:$eventEnvVar -ieq \'${_powerShellSingleQuote(emptyPayloadFallbackEvent)}\') { \$payload=@{} } else { exit 0 } } else { \$payload=(\$inputData | ConvertFrom-Json) };';
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); $inputScript try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:$eventEnvVar; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=\$payload } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); for (\$attempt=0; \$attempt -lt 2; \$attempt++) { \$retry=\$false; try { \$response=Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/$source\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes -TimeoutSec 1; \$statusCode=[int]\$response.StatusCode; \$retry=\$statusCode -eq 429 -or \$statusCode -eq 503 } catch { \$statusCode=0; if (\$_.Exception.Response) { \$statusCode=[int]\$_.Exception.Response.StatusCode }; \$retry=\$statusCode -eq 0 -or \$statusCode -eq 429 -or \$statusCode -eq 503 }; if (-not \$retry -or \$attempt -eq 1) { break } } } catch {}"';
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
      _ManagedHookDefinitionShape.agyLifecycleCommand => <String, Object?>{
        'type': 'command',
        'command': command,
        'timeout': 10,
      },
      _ManagedHookDefinitionShape.agyToolCommand => <String, Object?>{
        if (event.matcher != null) 'matcher': event.matcher,
        'hooks': <Object?>[
          <String, Object?>{
            'type': 'command',
            'command': command,
            'timeout': 10,
          },
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
}
