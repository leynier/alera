use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use super::{
    clean_managed_definitions, env_path, home_dir, managed_command, managed_hook_definition,
    object_field, read_json_object, write_json_object,
};

pub(super) fn install_copilot(script: &Path) -> anyhow::Result<()> {
    let path = copilot_hooks_path()?;
    let events = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
        "Stop",
        "ErrorOccurred",
        "PermissionRequest",
        "Notification",
    ];
    let hooks = events
        .into_iter()
        .map(|event| (event.to_string(), json!([copilot_handler(script, event)])))
        .collect::<Map<_, _>>();
    write_json_object(
        &path,
        &Map::from_iter([
            ("version".to_string(), json!(1)),
            ("hooks".to_string(), Value::Object(hooks)),
        ]),
    )
}

#[cfg(not(windows))]
fn copilot_handler(script: &Path, event: &str) -> Value {
    json!({ "type": "command", "bash": managed_command(script, "copilot", event), "timeoutSec": 5 })
}

/// Copilot on Windows runs only the `powershell` field; a `bash` entry never
/// runs there. The handler posts from that one PowerShell instead of chaining
/// into the `.cmd` hook, which would start a second one: since 1.0.88 a
/// `preToolUse` hook that fails or times out denies the tool.
#[cfg(windows)]
fn copilot_handler(_script: &Path, event: &str) -> Value {
    json!({ "type": "command", "powershell": copilot_powershell_command(event), "timeoutSec": 10 })
}

/// Copilot runs this as `pwsh -nop -nol -c "<command>"` (verified on 1.0.83).
/// The `{}` answer comes first: Copilot reads a JSON response even when the
/// hook cannot reach Alera. It always exits 0: a caught failed post would
/// otherwise exit 1, and a failing `preToolUse` hook denies the tool. Payload bytes are read and sent as UTF-8
/// explicitly, because Windows PowerShell 5.1 defaults to the OEM code page,
/// and progress is off because 5.1 renders it per chunk and slows the post.
#[cfg(any(windows, test))]
fn copilot_powershell_command(event: &str) -> String {
    format!(
        "{MANAGED_POWERSHELL_MARKER}; '{{}}'; $ErrorActionPreference='SilentlyContinue'; $ProgressPreference='SilentlyContinue'; \
$f=$env:ALERA_AGENT_HOOK_ENDPOINT; if(-not $f -and $env:ALERA_RUNTIME_DIR){{$f=Join-Path $env:ALERA_RUNTIME_DIR 'agent-hooks\\endpoint.cmd'}}; \
if($f -and (Test-Path -LiteralPath $f)){{foreach($l in Get-Content -LiteralPath $f){{if($l -match '^set ([A-Z0-9_]+)=(.*)$'){{Set-Item -Path ('env:'+$Matches[1]) -Value $Matches[2]}}}}}}; \
if($env:ALERA_AGENT_HOOK_PORT -and $env:ALERA_AGENT_HOOK_TOKEN -and $env:ALERA_TERMINAL_SESSION_ID -and $env:ALERA_WORKSPACE_ID -and $env:ALERA_TAB_ID){{\
try{{$r=New-Object System.IO.StreamReader([Console]::OpenStandardInput(),(New-Object System.Text.UTF8Encoding($false)));$i=$r.ReadToEnd();if([string]::IsNullOrWhiteSpace($i)){{$i='{{}}'}};\
$b=@{{terminalSessionId=$env:ALERA_TERMINAL_SESSION_ID;workspaceId=$env:ALERA_WORKSPACE_ID;tabId=$env:ALERA_TAB_ID;hookEventName='{event}';version=$env:ALERA_AGENT_HOOK_VERSION;multiplexer=$(if($env:TMUX){{'tmux'}}elseif($env:STY){{'screen'}}elseif($env:ZELLIJ){{'zellij'}});payload=($i|ConvertFrom-Json)}}|ConvertTo-Json -Depth 100 -Compress;\
Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Method Post -Uri ('http://127.0.0.1:'+$env:ALERA_AGENT_HOOK_PORT+'/hook/copilot') -ContentType 'application/json; charset=utf-8' -Headers @{{'X-Alera-Agent-Hook-Token'=$env:ALERA_AGENT_HOOK_TOKEN}} -Body ([System.Text.Encoding]::UTF8.GetBytes($b))|Out-Null}}catch{{}}}}; exit 0"
    )
}

/// Alera recognizes its own hook entries by this marker; the PowerShell form
/// has no script path to carry it.
#[cfg(any(windows, test))]
const MANAGED_POWERSHELL_MARKER: &str = "$null='alera-runtime-agent-hook'";

pub(super) fn install_grok(script: &Path) -> anyhow::Result<()> {
    let path = grok_hooks_path()?;
    let hooks = [
        ("SessionStart", None),
        ("UserPromptSubmit", None),
        ("PreToolUse", Some("*")),
        ("PostToolUse", Some("*")),
        ("PostToolUseFailure", Some("*")),
        ("Notification", None),
        ("Stop", None),
        ("StopFailure", None),
        // Replaces `Stop` for Ctrl+C, a declined permission and turn limits.
        ("StopCancelled", None),
        ("SessionEnd", None),
    ]
    .into_iter()
    .map(|(event, matcher)| {
        (
            event.to_string(),
            json!([managed_hook_definition(
                matcher,
                &managed_command(script, "grok", event)
            )]),
        )
    })
    .collect::<Map<_, _>>();
    write_json_object(
        &path,
        &Map::from_iter([("hooks".to_string(), Value::Object(hooks))]),
    )
}

pub(super) fn install_agy(script: &Path) -> anyhow::Result<()> {
    let path = home_dir()?.join(".gemini/config/hooks.json");
    let mut config = read_json_object(&path)?.unwrap_or_default();
    apply_agy_bundle(&mut config, script);
    write_json_object(&path, &config)
}

pub(super) fn cleanup_agy(home: &Path) -> anyhow::Result<()> {
    let path = home.join(".gemini/config/hooks.json");
    let Some(mut config) = read_json_object(&path)? else {
        return Ok(());
    };
    let Some(bundle) = config.get("alera-status").cloned() else {
        return Ok(());
    };
    let Some(mut bundle) = bundle.as_object().cloned() else {
        return Ok(());
    };
    let mut changed = false;
    for event in ["PreInvocation", "PostInvocation", "Stop", "PostToolUse"] {
        let Some(value) = bundle.remove(event) else {
            continue;
        };
        let had = value.as_array().map(Vec::len).unwrap_or(0);
        let cleaned = clean_managed_definitions(Some(value));
        if cleaned.len() != had {
            changed = true;
        }
        if !cleaned.is_empty() {
            bundle.insert(event.to_string(), Value::Array(cleaned));
        }
    }
    if bundle.is_empty() {
        config.remove("alera-status");
        changed = true;
    } else if changed {
        config.insert("alera-status".to_string(), Value::Object(bundle));
    }
    if !changed {
        return Ok(());
    }
    write_json_object(&path, &config)
}

pub(super) fn cleanup_dedicated_hooks_file(path: &Path) -> anyhow::Result<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

pub(super) fn copilot_hooks_path() -> anyhow::Result<PathBuf> {
    Ok(env_path("COPILOT_HOME")
        .unwrap_or(home_dir()?.join(".copilot"))
        .join("hooks/alera.json"))
}

pub(super) fn grok_hooks_path() -> anyhow::Result<PathBuf> {
    Ok(env_path("GROK_HOME")
        .unwrap_or(home_dir()?.join(".grok"))
        .join("hooks/alera-status.json"))
}

// Antigravity keeps each hook set under its own top-level key and uses two
// schemas inside it: lifecycle events take a flat `{ type, command }` handler,
// tool events a matcher wrapping `hooks`. `PreToolUse` is deliberately absent -
// Antigravity requires a permission `decision` from it, which an observational
// hook cannot give without taking over the user's tool policy.
pub(super) fn apply_agy_bundle(config: &mut Map<String, Value>, script: &Path) {
    let bundle = object_field(config, "alera-status");
    // Installing is an explicit request to enable, so the documented `enabled`
    // opt-out cannot survive it. Every other non-event key is left alone.
    bundle.remove("enabled");
    for event in ["PreInvocation", "PostInvocation", "Stop"] {
        let mut definitions = clean_managed_definitions(bundle.remove(event));
        definitions.push(
            json!({ "type": "command", "command": managed_command(script, "agy", event), "timeout": 10 }),
        );
        bundle.insert(event.to_string(), Value::Array(definitions));
    }
    let mut tool_definitions = clean_managed_definitions(bundle.remove("PostToolUse"));
    tool_definitions.push(
        json!({ "matcher": "*", "hooks": [{ "type": "command", "command": managed_command(script, "agy", "PostToolUse"), "timeout": 10 }] }),
    );
    bundle.insert("PostToolUse".to_string(), Value::Array(tool_definitions));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agy_cleanup_removes_alera_handlers_and_keeps_user_ones() {
        let home = tempfile::tempdir().unwrap();
        let path = home.path().join(".gemini/config/hooks.json");
        write_json_object(
            &path,
            &Map::from_iter([
                (
                    "alera-status".to_string(),
                    json!({
                        "Stop": [
                            { "type": "command", "command": "echo user" },
                            { "type": "command", "command": "/home/user/.alera/agent-hooks/alera-runtime-agent-hook.sh" }
                        ]
                    }),
                ),
                (
                    "other-bundle".to_string(),
                    json!({ "Stop": [{ "type": "command", "command": "echo other" }] }),
                ),
            ]),
        )
        .unwrap();

        cleanup_agy(home.path()).unwrap();

        let config = read_json_object(&path).unwrap().unwrap();
        assert_eq!(
            config["alera-status"]["Stop"],
            json!([{ "type": "command", "command": "echo user" }])
        );
        assert_eq!(
            config["other-bundle"]["Stop"],
            json!([{ "type": "command", "command": "echo other" }])
        );
    }

    #[test]
    fn dedicated_hook_file_cleanup_deletes_only_the_alera_file() {
        let root = tempfile::tempdir().unwrap();
        let alera = root.path().join("hooks/alera.json");
        let other = root.path().join("hooks/user.json");
        std::fs::create_dir_all(alera.parent().unwrap()).unwrap();
        std::fs::write(&alera, "{}\n").unwrap();
        std::fs::write(&other, "{\"keep\":true}\n").unwrap();

        cleanup_dedicated_hooks_file(&alera).unwrap();

        assert!(!alera.exists());
        assert!(other.exists());
    }
}

#[cfg(test)]
mod copilot_powershell_tests {
    use super::*;

    #[test]
    fn the_windows_copilot_handler_answers_first_and_carries_the_marker() {
        let command = copilot_powershell_command("PreToolUse");
        assert!(command.starts_with(MANAGED_POWERSHELL_MARKER));
        assert!(command.find("'{}'").unwrap() < command.find("Invoke-WebRequest").unwrap());
        assert!(command.contains("hookEventName='PreToolUse'"));
        assert!(command.ends_with("; exit 0"));
        assert!(
            !command.contains('"'),
            "pwsh -c wraps the command in double quotes"
        );
        assert!(command.contains("agent-hooks\\endpoint.cmd"));
        assert!(super::super::is_alera_managed_definition(&json!({
            "hooks": [{ "powershell": command }]
        })));
        if let Ok(path) = std::env::var("ALERA_DUMP_COPILOT_POWERSHELL") {
            std::fs::write(path, copilot_powershell_command("Stop")).unwrap();
        }
    }
}
