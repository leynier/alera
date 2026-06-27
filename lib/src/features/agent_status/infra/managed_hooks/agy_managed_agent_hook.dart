part of '../managed_agent_hook_installer.dart';

extension _AgyManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _agyDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    final events = const <_ManagedHookEvent>[
      _ManagedHookEvent('PreInvocation'),
      _ManagedHookEvent('PostInvocation'),
      _ManagedHookEvent('Stop'),
      _ManagedHookEvent(
        'PostToolUse',
        matcher: '*',
        definitionShape: _ManagedHookDefinitionShape.agyToolCommand,
      ),
    ];
    final wrappers = <String, String>{};
    if (_platform == ManagedAgentHookPlatform.windows) {
      for (final event in events) {
        final path = _agyWindowsWrapperPath(event.eventName);
        wrappers[path] = _agyWindowsWrapperScript(event.eventName);
      }
    }
    return _AgentHookDescriptor(
      agentType: AgentType.agy,
      configPath: p.join(_homeDirectory, '.gemini', 'config', 'hooks.json'),
      configLabel: 'Antigravity hooks.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_AGY_EVENT',
      configShape: _AgentHookConfigShape.agyBundle,
      definitionShape: _ManagedHookDefinitionShape.nestedCommand,
      bundleName: 'alera-status',
      managedScriptFileNames: <String>[
        scriptFileName,
        if (_platform == ManagedAgentHookPlatform.windows)
          for (final event in events)
            p.basename(_agyWindowsWrapperPath(event.eventName)),
      ],
      windowsWrappers: wrappers,
      events: events,
    );
  }

  String _agyManagedScript(_AgentHookDescriptor descriptor) {
    if (_platform == ManagedAgentHookPlatform.windows) {
      return <String>[
        '@echo off',
        'setlocal',
        'if /I "%${descriptor.eventEnvVar}%"=="Stop" (',
        '  echo {"decision":""}',
        ') else (',
        '  echo {}',
        ')',
        'if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul',
        'if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0',
        'if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0',
        'if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0',
        'if "%ALERA_WORKSPACE_ID%"=="" exit /b 0',
        'if "%ALERA_TAB_ID%"=="" exit /b 0',
        _windowsPostCommand(
          descriptor.agentType.key,
          descriptor.eventEnvVar,
          emptyPayloadFallbackEvent: 'Stop',
        ),
        'exit /b 0',
        '',
      ].join('\r\n');
    }
    return <String>[
      '#!/bin/sh',
      'case "\$${descriptor.eventEnvVar}" in',
      '  Stop)',
      '    printf \'{"decision":""}\\n\'',
      '    ;;',
      '  *)',
      '    printf "{}\\n"',
      '    ;;',
      'esac',
      'if [ -n "\$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -r "\$ALERA_AGENT_HOOK_ENDPOINT" ]; then',
      '  . "\$ALERA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :',
      'fi',
      'if [ -z "\$ALERA_AGENT_HOOK_PORT" ] || [ -z "\$ALERA_AGENT_HOOK_TOKEN" ] || [ -z "\$ALERA_TERMINAL_SESSION_ID" ] || [ -z "\$ALERA_WORKSPACE_ID" ] || [ -z "\$ALERA_TAB_ID" ]; then',
      '  exit 0',
      'fi',
      'payload=\$(cat)',
      'if [ -z "\$payload" ]; then',
      '  case "\$${descriptor.eventEnvVar}" in',
      '    Stop)',
      "      payload='{}'",
      '      ;;',
      '    *)',
      '      exit 0',
      '      ;;',
      '  esac',
      'fi',
      'curl -sS -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/${descriptor.agentType.key}" \\',
      '  -H "Content-Type: application/x-www-form-urlencoded" \\',
      '  -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '  --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '  --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '  --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '  --data-urlencode "hook_event_name=\${${descriptor.eventEnvVar}}" \\',
      '  --data-urlencode "version=\${ALERA_AGENT_HOOK_VERSION}" \\',
      '  --data-urlencode "payload=\${payload}" >/dev/null 2>&1 || true',
      'exit 0',
      '',
    ].join('\n');
  }

  String _agyWindowsWrapperPath(String eventName) {
    final fileName = switch (eventName) {
      'PreInvocation' => 'alera-agy-pre-invocation.cmd',
      'PostInvocation' => 'alera-agy-post-invocation.cmd',
      'Stop' => 'alera-agy-stop.cmd',
      'PostToolUse' => 'alera-agy-post-tool-use.cmd',
      // coverage:ignore-start
      // Event names are fixed by _agyDescriptor; this fallback keeps wrapper
      // naming deterministic if AGY introduces another event.
      _ => 'alera-agy-${eventName.toLowerCase()}.cmd',
      // coverage:ignore-end
    };
    return p.join(_homeDirectory, '.alera', 'agent-hooks', fileName);
  }

  String _agyWindowsWrapperScript(String eventName) {
    return <String>[
      '@echo off',
      'setlocal',
      'set "ALERA_AGY_EVENT=$eventName"',
      'set "ALERA_AGY_CORE=%~dp0alera-agy-hook.cmd"',
      'if exist "%ALERA_AGY_CORE%" (',
      '  call "%ALERA_AGY_CORE%"',
      '  exit /b 0',
      ')',
      'if /I "%ALERA_AGY_EVENT%"=="Stop" (',
      '  echo {"decision":""}',
      ') else (',
      '  echo {}',
      ')',
      'exit /b 0',
      '',
    ].join('\r\n');
  }
}
