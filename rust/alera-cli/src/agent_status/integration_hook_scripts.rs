use std::path::PathBuf;

use super::integration_config::home_dir;

// One script backs every managed hook command the runtime installs, for every
// agent, parameterized by `ALERA_AGENT_TYPE` and `ALERA_AGENT_HOOK_EVENT`.
pub(super) fn write_managed_script() -> anyhow::Result<PathBuf> {
    let directory = home_dir()?.join(".alera/agent-hooks");
    std::fs::create_dir_all(&directory)?;
    #[cfg(windows)]
    let (path, contents) = (
        directory.join("alera-runtime-agent-hook.cmd"),
        WINDOWS_HOOK_SCRIPT,
    );
    #[cfg(not(windows))]
    let (path, contents) = (
        directory.join("alera-runtime-agent-hook.sh"),
        POSIX_HOOK_SCRIPT,
    );
    std::fs::write(&path, contents)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755))?;
    }
    Ok(path)
}

pub(super) const POSIX_HOOK_SCRIPT: &str = r#"#!/bin/sh
# Antigravity and Copilot read a JSON response on stdout for every hook, and
# Antigravity additionally requires a `decision` on Stop. An empty object is how
# an observational hook opts out. This has to be written before the guards
# below, because a hook that cannot reach Alera still owes the agent an answer.
if [ "$ALERA_AGENT_TYPE" = "agy" ] && [ "$ALERA_AGENT_HOOK_EVENT" = "Stop" ]; then
  printf '{"decision":""}\n'
elif [ "$ALERA_AGENT_TYPE" = "agy" ] || [ "$ALERA_AGENT_TYPE" = "copilot" ]; then
  printf '{}\n'
fi
if [ -z "$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -n "$ALERA_RUNTIME_DIR" ]; then
  ALERA_AGENT_HOOK_ENDPOINT="$ALERA_RUNTIME_DIR/agent-hooks/endpoint.env"
fi
if [ -n "$ALERA_AGENT_HOOK_ENDPOINT" ] && [ -r "$ALERA_AGENT_HOOK_ENDPOINT" ]; then
  . "$ALERA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :
fi
if [ -z "$ALERA_AGENT_HOOK_PORT" ] || [ -z "$ALERA_AGENT_HOOK_TOKEN" ] || [ -z "$ALERA_TERMINAL_SESSION_ID" ] || [ -z "$ALERA_WORKSPACE_ID" ] || [ -z "$ALERA_TAB_ID" ] || [ -z "$ALERA_AGENT_TYPE" ]; then
  exit 0
fi
payload=$(cat)
if [ -z "$payload" ]; then payload='{}'; fi
# Pipe the payload through curl's stdin so tens-of-KB tool JSON stays off the
# command line. Same wire body as an inline `payload=` argument.
printf '%s' "$payload" | curl -sS -X POST "http://127.0.0.1:${ALERA_AGENT_HOOK_PORT}/hook/${ALERA_AGENT_TYPE}" \
  --connect-timeout 0.5 --max-time 1.5 \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "X-Alera-Agent-Hook-Token: ${ALERA_AGENT_HOOK_TOKEN}" \
  --data-urlencode "terminalSessionId=${ALERA_TERMINAL_SESSION_ID}" \
  --data-urlencode "workspaceId=${ALERA_WORKSPACE_ID}" \
  --data-urlencode "tabId=${ALERA_TAB_ID}" \
  --data-urlencode "hookEventName=${ALERA_AGENT_HOOK_EVENT}" \
  --data-urlencode "version=${ALERA_AGENT_HOOK_VERSION}" \
  --data-urlencode "payload@-" >/dev/null 2>&1 || true
exit 0
"#;

#[cfg(windows)]
pub(super) const WINDOWS_HOOK_SCRIPT: &str = r#"@echo off
setlocal
if /I "%ALERA_AGENT_TYPE%"=="agy" (
  if /I "%ALERA_AGENT_HOOK_EVENT%"=="Stop" (
    echo {"decision":""}
  ) else (
    echo {}
  )
) else if /I "%ALERA_AGENT_TYPE%"=="copilot" (
  echo {}
)
if not defined ALERA_AGENT_HOOK_ENDPOINT if defined ALERA_RUNTIME_DIR set "ALERA_AGENT_HOOK_ENDPOINT=%ALERA_RUNTIME_DIR%\agent-hooks\endpoint.cmd"
if defined ALERA_AGENT_HOOK_ENDPOINT if exist "%ALERA_AGENT_HOOK_ENDPOINT%" call "%ALERA_AGENT_HOOK_ENDPOINT%" 2>nul
if "%ALERA_AGENT_HOOK_PORT%"=="" exit /b 0
if "%ALERA_AGENT_HOOK_TOKEN%"=="" exit /b 0
if "%ALERA_TERMINAL_SESSION_ID%"=="" exit /b 0
if "%ALERA_WORKSPACE_ID%"=="" exit /b 0
if "%ALERA_TAB_ID%"=="" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command "$inputData=[Console]::In.ReadToEnd(); if ([string]::IsNullOrWhiteSpace($inputData)) { $inputData='{}' }; try { $body=@{ terminalSessionId=$env:ALERA_TERMINAL_SESSION_ID; workspaceId=$env:ALERA_WORKSPACE_ID; tabId=$env:ALERA_TAB_ID; hookEventName=$env:ALERA_AGENT_HOOK_EVENT; version=$env:ALERA_AGENT_HOOK_VERSION; payload=($inputData | ConvertFrom-Json) } | ConvertTo-Json -Depth 100 -Compress; Invoke-WebRequest -UseBasicParsing -Method Post -Uri ('http://127.0.0.1:' + $env:ALERA_AGENT_HOOK_PORT + '/hook/' + $env:ALERA_AGENT_TYPE) -ContentType 'application/json' -Headers @{ 'X-Alera-Agent-Hook-Token'=$env:ALERA_AGENT_HOOK_TOKEN } -Body $body | Out-Null } catch {}"
exit /b 0
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_scripts_can_derive_the_current_runtime_endpoint() {
        assert!(POSIX_HOOK_SCRIPT.contains("$ALERA_RUNTIME_DIR/agent-hooks/endpoint.env"));
    }

    #[test]
    fn managed_script_answers_stdout_agents_before_the_environment_guards() {
        let response = POSIX_HOOK_SCRIPT
            .find(r#"printf '{"decision":""}\n'"#)
            .expect("agy Stop response");
        let guard = POSIX_HOOK_SCRIPT
            .find("$ALERA_AGENT_HOOK_PORT")
            .expect("environment guard");

        assert!(POSIX_HOOK_SCRIPT.contains(r#"[ "$ALERA_AGENT_HOOK_EVENT" = "Stop" ]"#));
        assert!(POSIX_HOOK_SCRIPT.contains(r#"[ "$ALERA_AGENT_TYPE" = "copilot" ]"#));
        assert!(POSIX_HOOK_SCRIPT.contains(r#"printf '{}\n'"#));
        // A hook that cannot reach Alera still owes the agent an answer.
        assert!(response < guard);
    }

    #[test]
    fn managed_script_keeps_hook_payloads_off_the_command_line() {
        assert!(POSIX_HOOK_SCRIPT.contains(r#"--data-urlencode "payload@-""#));
        assert!(!POSIX_HOOK_SCRIPT.contains(r#"payload=${payload}"#));
    }

    #[cfg(windows)]
    #[test]
    fn windows_managed_script_answers_stdout_agents() {
        assert!(WINDOWS_HOOK_SCRIPT.contains(r#"if /I "%ALERA_AGENT_TYPE%"=="agy" ("#));
        assert!(WINDOWS_HOOK_SCRIPT.contains(r#"else if /I "%ALERA_AGENT_TYPE%"=="copilot" ("#));
        assert!(WINDOWS_HOOK_SCRIPT.contains(r#"echo {"decision":""}"#));
    }

    #[cfg(windows)]
    #[test]
    fn windows_managed_script_can_derive_the_current_runtime_endpoint() {
        assert!(WINDOWS_HOOK_SCRIPT.contains("%ALERA_RUNTIME_DIR%\\agent-hooks\\endpoint.cmd"));
    }
}
