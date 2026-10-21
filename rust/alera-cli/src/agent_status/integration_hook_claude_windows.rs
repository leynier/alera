use std::path::{Path, PathBuf};

pub(crate) fn write_script(shared_script: &Path) -> anyhow::Result<PathBuf> {
    let path = shared_script.with_extension("ps1");
    std::fs::write(&path, CLAUDE_WINDOWS_HOOK_SCRIPT)?;
    Ok(path)
}

pub(crate) fn managed_command(script: &Path, event: &str) -> String {
    // Claude runs command strings through Bash even on Windows. Native paths
    // remain valid with MSYS conversion disabled and single quotes keep them data.
    let script = script.to_string_lossy().replace('\'', "'\\''");
    format!(
        "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '{script}' -HookEventName {event}"
    )
}

pub(crate) const CLAUDE_WINDOWS_HOOK_SCRIPT: &str = r#"param([string]$HookEventName)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  if ([string]::IsNullOrEmpty($env:CLAUDECODE) -or -not [string]::IsNullOrEmpty($env:GROK_HOOK_EVENT)) { exit 0 }
  $endpoint = $env:ALERA_AGENT_HOOK_ENDPOINT
  if ([string]::IsNullOrEmpty($endpoint) -and -not [string]::IsNullOrEmpty($env:ALERA_RUNTIME_DIR)) {
    $endpoint = Join-Path $env:ALERA_RUNTIME_DIR 'agent-hooks\endpoint.cmd'
  }
  if (-not [string]::IsNullOrEmpty($endpoint) -and [System.IO.File]::Exists($endpoint)) {
    # endpoint.cmd is data, never a command or a PowerShell script.
    foreach ($line in [System.IO.File]::ReadAllLines($endpoint, [System.Text.Encoding]::UTF8)) {
      if ($line -match '^set "(ALERA_AGENT_HOOK_(?:PORT|TOKEN|VERSION))=([^"]*)"$' -or $line -match '^set (ALERA_AGENT_HOOK_(?:PORT|TOKEN|VERSION))=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($Matches[1].ToUpperInvariant(), $Matches[2], 'Process')
      }
    }
  }
  $port = 0
  if (-not [int]::TryParse($env:ALERA_AGENT_HOOK_PORT, [ref]$port) -or $port -lt 1 -or $port -gt 65535 -or [string]::IsNullOrEmpty($env:ALERA_AGENT_HOOK_TOKEN) -or [string]::IsNullOrEmpty($env:ALERA_TERMINAL_SESSION_ID) -or [string]::IsNullOrEmpty($env:ALERA_WORKSPACE_ID) -or [string]::IsNullOrEmpty($env:ALERA_TAB_ID) -or [string]::IsNullOrEmpty($HookEventName)) { exit 0 }
  $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
  $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8, $false)
  $inputData = $reader.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($inputData)) { exit 0 }
  $payload = ConvertFrom-Json -InputObject $inputData
  $body = @{
    terminalSessionId = $env:ALERA_TERMINAL_SESSION_ID
    workspaceId = $env:ALERA_WORKSPACE_ID
    tabId = $env:ALERA_TAB_ID
    hookEventName = $HookEventName
    version = $env:ALERA_AGENT_HOOK_VERSION
    claudeConfigDir = $env:CLAUDE_CONFIG_DIR
    agentPid = $env:CLAUDE_PID
    multiplexer = $(if ($env:TMUX) { 'tmux' } elseif ($env:STY) { 'screen' } elseif ($env:ZELLIJ) { 'zellij' })
    payload = $payload
  } | ConvertTo-Json -Depth 100 -Compress
  Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Post -Uri ('http://127.0.0.1:' + $port + '/hook/claude') -ContentType 'application/json; charset=utf-8' -Headers @{ 'X-Alera-Agent-Hook-Token' = $env:ALERA_AGENT_HOOK_TOKEN } -Body ($utf8.GetBytes($body)) | Out-Null
} catch {}
exit 0
"#;

#[cfg(test)]
#[path = "integration_hook_claude_windows_tests.rs"]
mod tests;
