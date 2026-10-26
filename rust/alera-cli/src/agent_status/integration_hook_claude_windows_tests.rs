use super::*;

#[test]
fn command_uses_bash_quoted_native_path_and_the_legacy_string_schema() {
    let script =
        Path::new(r"C:\Users\O'Brien $value `literal`\hook dir\alera-runtime-agent-hook.ps1");

    assert_eq!(
        managed_command(script, "PostToolUse"),
        r"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Users\O'\''Brien $value `literal`\hook dir\alera-runtime-agent-hook.ps1' -HookEventName PostToolUse"
    );
}

#[test]
fn script_reads_utf8_json_data_and_posts_the_existing_fields() {
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("[Console]::OpenStandardInput()"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("[System.Text.UTF8Encoding]::new($false, $true)"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("ConvertFrom-Json -InputObject $inputData"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("-Body ($utf8.GetBytes($body))"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("-TimeoutSec 2"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("'/hook/claude'"));
    for field in [
        "terminalSessionId",
        "workspaceId",
        "tabId",
        "hookEventName",
        "version",
        "claudeConfigDir",
        "agentPid",
        "multiplexer",
        "payload",
    ] {
        assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains(&format!("{field} = ")));
    }
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT
        .contains("'X-Alera-Agent-Hook-Token' = $env:ALERA_AGENT_HOOK_TOKEN"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("$env:TMUX"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("$env:STY"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("$env:ZELLIJ"));
}

#[test]
fn script_keeps_session_guards_and_silent_success_on_errors() {
    let guard = CLAUDE_WINDOWS_HOOK_SCRIPT.find("$env:CLAUDECODE").unwrap();
    let read = CLAUDE_WINDOWS_HOOK_SCRIPT
        .find("$reader.ReadToEnd()")
        .unwrap();
    let post = CLAUDE_WINDOWS_HOOK_SCRIPT
        .find("Invoke-WebRequest")
        .unwrap();
    assert!(guard < read && read < post);
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("$env:GROK_HOOK_EVENT"));
    assert!(!CLAUDE_WINDOWS_HOOK_SCRIPT.contains("CLAUDE_PROJECT_DIR"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("[string]::IsNullOrWhiteSpace($inputData)"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("$ErrorActionPreference = 'Stop'"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.ends_with("| Out-Null\n} catch {}\nexit 0\n"));
    assert!(!CLAUDE_WINDOWS_HOOK_SCRIPT.contains("Write-"));
}

#[test]
fn script_loads_only_endpoint_assignments_as_data() {
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT
        .contains("Join-Path $env:ALERA_RUNTIME_DIR 'agent-hooks\\endpoint.cmd'"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT
        .contains("[System.IO.File]::ReadAllLines($endpoint, [System.Text.Encoding]::UTF8)"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains("(ALERA_AGENT_HOOK_(?:PORT|TOKEN|VERSION))"));
    assert!(CLAUDE_WINDOWS_HOOK_SCRIPT.contains(
        "SetEnvironmentVariable($Matches[1].ToUpperInvariant(), $Matches[2], 'Process')"
    ));
    for forbidden in [
        "Invoke-Expression",
        "ScriptBlock",
        "cmd.exe",
        "call ",
        ". $endpoint",
        "& $endpoint",
    ] {
        assert!(
            !CLAUDE_WINDOWS_HOOK_SCRIPT.contains(forbidden),
            "{forbidden}"
        );
    }
}

#[test]
fn claude_script_has_its_own_ps1_without_replacing_the_shared_cmd() {
    let directory = tempfile::tempdir().unwrap();
    let shared = directory.path().join("alera-runtime-agent-hook.cmd");
    std::fs::write(&shared, "shared fixture").unwrap();

    let script = write_script(&shared).unwrap();

    assert_eq!(script, shared.with_extension("ps1"));
    assert_eq!(
        std::fs::read_to_string(script).unwrap(),
        CLAUDE_WINDOWS_HOOK_SCRIPT
    );
    assert_eq!(std::fs::read_to_string(shared).unwrap(), "shared fixture");
}

#[test]
#[ignore = "Exports actual generated artifacts for the standalone Windows acceptance runner"]
fn export_windows_claude_hook_fixture() {
    let fixture = std::env::var_os("ALERA_WINDOWS_CLAUDE_FIXTURE_PATH")
        .expect("Set ALERA_WINDOWS_CLAUDE_FIXTURE_PATH to the output JSON path");
    let script = std::env::var_os("ALERA_WINDOWS_CLAUDE_SCRIPT_PATH")
        .expect("Set ALERA_WINDOWS_CLAUDE_SCRIPT_PATH to a native Windows PS1 path in the runner's temporary folder");
    let script = Path::new(&script);
    let contents = serde_json::json!({
        "command": managed_command(script, "PostToolUse"),
        "scriptPath": script.to_string_lossy(),
        "scriptContent": CLAUDE_WINDOWS_HOOK_SCRIPT,
        "expectedFields": {
            "terminalSessionId": "fixture-session", "workspaceId": "fixture-workspace",
            "tabId": "fixture-tab", "hookEventName": "PostToolUse", "version": "1",
            "claudeConfigDir": "C:\\fixture\\claude-config", "agentPid": "12345", "multiplexer": "tmux"
        }
    });
    std::fs::write(fixture, serde_json::to_vec_pretty(&contents).unwrap()).unwrap();
}
