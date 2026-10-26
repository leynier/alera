part of 'claude_runtime_home_service.dart';

const _claudeWindowsHookScript = r'''param([string]$HookEventName)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  # Grok also reads Claude settings, but only Claude exports CLAUDECODE.
  if ([string]::IsNullOrWhiteSpace($env:CLAUDECODE) -or $env:GROK_HOOK_EVENT) { exit 0 }
  if ([string]::IsNullOrWhiteSpace($env:ALERA_TERMINAL_SESSION_ID) -or
      [string]::IsNullOrWhiteSpace($env:ALERA_WORKSPACE_ID) -or
      [string]::IsNullOrWhiteSpace($env:ALERA_TAB_ID) -or
      [string]::IsNullOrWhiteSpace($HookEventName)) { exit 0 }

  $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
  $endpoint = @{
    ALERA_AGENT_HOOK_PORT = $env:ALERA_AGENT_HOOK_PORT
    ALERA_AGENT_HOOK_TOKEN = $env:ALERA_AGENT_HOOK_TOKEN
    ALERA_AGENT_HOOK_VERSION = $env:ALERA_AGENT_HOOK_VERSION
  }
  $endpointPath = $env:ALERA_AGENT_HOOK_ENDPOINT
  if (-not $endpointPath -and $env:ALERA_RUNTIME_DIR) {
    $endpointPath = Join-Path $env:ALERA_RUNTIME_DIR 'agent-hooks\endpoint.cmd'
  }
  if ($endpointPath -and [System.IO.File]::Exists($endpointPath)) {
    # Endpoint files contain assignments, never commands to execute.
    foreach ($line in [System.IO.File]::ReadAllLines($endpointPath, $utf8)) {
      if ($line -match '^\s*set\s+"?(ALERA_AGENT_HOOK_(?:PORT|TOKEN|VERSION))=([A-Za-z0-9._:/-]+)"?\s*$') {
        $endpoint[$Matches[1]] = $Matches[2]
      }
    }
  }
  $port = 0
  if (-not [int]::TryParse($endpoint.ALERA_AGENT_HOOK_PORT, [ref]$port) -or
      $port -lt 1 -or $port -gt 65535 -or
      [string]::IsNullOrWhiteSpace($endpoint.ALERA_AGENT_HOOK_TOKEN)) { exit 0 }

  $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8, $false)
  $inputData = $reader.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($inputData) -or
      -not $inputData.TrimStart().StartsWith('{')) { exit 0 }
  $payload = ConvertFrom-Json -InputObject $inputData
  if ($payload -isnot [System.Management.Automation.PSCustomObject]) { exit 0 }
  $multiplexer = if ($env:TMUX) { 'tmux' } elseif ($env:STY) { 'screen' } elseif ($env:ZELLIJ) { 'zellij' } else { '' }
  $body = @{
    terminalSessionId = $env:ALERA_TERMINAL_SESSION_ID
    workspaceId = $env:ALERA_WORKSPACE_ID
    tabId = $env:ALERA_TAB_ID
    hookEventName = $HookEventName
    version = $endpoint.ALERA_AGENT_HOOK_VERSION
    claudeConfigDir = $env:CLAUDE_CONFIG_DIR
    agentPid = $env:CLAUDE_PID
    multiplexer = $multiplexer
    payload = $payload
  } | ConvertTo-Json -Depth 100 -Compress
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Post `
    -Uri ('http://127.0.0.1:' + $port + '/hook/claude') `
    -ContentType 'application/json; charset=utf-8' `
    -Headers @{ 'X-Alera-Agent-Hook-Token' = $endpoint.ALERA_AGENT_HOOK_TOKEN } `
    -Body ($utf8.GetBytes($body)) | Out-Null
} catch {}
exit 0
''';
