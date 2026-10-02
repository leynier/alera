part of 'codex_runtime_home_service.dart';

extension _CodexRuntimeHomeServiceIo on CodexRuntimeHomeService {
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
    } catch (_) {}
    return null;
  }

  void _writeJsonObject(String path, Map<String, Object?> config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final serialized =
        '${const JsonEncoder.withIndent('  ').convert(config)}\n';
    if (file.existsSync() && file.readAsStringSync() == serialized) {
      return;
    }
    if (file.existsSync()) {
      file.copySync('$path.bak');
    }
    final tmp = File(
      p.join(file.parent.path, '.${DateTime.now().microsecondsSinceEpoch}.tmp'),
    )..writeAsStringSync(serialized);
    tmp.renameSync(path);
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

  String _managedCommand(String scriptPath, String eventName) {
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
      'attempt=0',
      'while [ "\$attempt" -lt 3 ]; do',
      '  httpCode=\$(curl -sS --connect-timeout 0.2 --max-time 0.5 -X POST "http://127.0.0.1:\${ALERA_AGENT_HOOK_PORT}/hook/codex" \\',
      '    -H "Content-Type: application/x-www-form-urlencoded" \\',
      '    -H "$aleraAgentHookTokenHeader: \${ALERA_AGENT_HOOK_TOKEN}" \\',
      '    --data-urlencode "terminalSessionId=\${ALERA_TERMINAL_SESSION_ID}" \\',
      '    --data-urlencode "workspaceId=\${ALERA_WORKSPACE_ID}" \\',
      '    --data-urlencode "tabId=\${ALERA_TAB_ID}" \\',
      '    --data-urlencode "hookEventName=\${ALERA_AGENT_HOOK_EVENT}" \\',
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

  String _windowsPostCommand() {
    return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "\$utf8=[System.Text.UTF8Encoding]::new(\$false); [Console]::InputEncoding=\$utf8; [Console]::OutputEncoding=\$utf8; \$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace(\$inputData)) { exit 0 }; try { \$body=@{ terminalSessionId=\$env:ALERA_TERMINAL_SESSION_ID; workspaceId=\$env:ALERA_WORKSPACE_ID; tabId=\$env:ALERA_TAB_ID; hookEventName=\$env:ALERA_AGENT_HOOK_EVENT; version=\$env:ALERA_AGENT_HOOK_VERSION; payload=(\$inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; \$bodyBytes=\$utf8.GetBytes(\$body); for (\$attempt=0; \$attempt -lt 2; \$attempt++) { \$retry=\$false; try { \$response=Invoke-WebRequest -UseBasicParsing -Method Post -Uri (\'http://127.0.0.1:\' + \$env:ALERA_AGENT_HOOK_PORT + \'/hook/codex\') -ContentType \'application/json; charset=utf-8\' -Headers @{ \'$aleraAgentHookTokenHeader\'=\$env:ALERA_AGENT_HOOK_TOKEN } -Body \$bodyBytes -TimeoutSec 1; \$statusCode=[int]\$response.StatusCode; \$retry=\$statusCode -eq 429 -or \$statusCode -eq 503 } catch { \$statusCode=0; if (\$_.Exception.Response) { \$statusCode=[int]\$_.Exception.Response.StatusCode }; \$retry=\$statusCode -eq 0 -or \$statusCode -eq 429 -or \$statusCode -eq 503 }; if (-not \$retry -or \$attempt -eq 1) { break } } } catch {}"';
  }
}
