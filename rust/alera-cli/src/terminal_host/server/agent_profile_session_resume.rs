use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::{
    AgentProfileEffectiveLaunchV1, AgentProfileLaunchSnapshotV1,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::agent_session_resume::{
    apply_resume_to_command, usable_native_session_id, AgentSessionResumeShape,
};

pub(super) fn requested_resume_session(
    payload: &Value,
    prompt: &str,
) -> HostResult<Option<String>> {
    let id = match payload.get("resumeSessionId") {
        None | Some(Value::Null) => return Ok(None),
        Some(Value::String(id)) => usable_native_session_id(id),
        _ => None,
    }
    .ok_or_else(|| HostError::format("resumeSessionId must be a valid non-empty session ID."))?;
    if !prompt.is_empty() {
        return Err(HostError::format(
            "A session resume cannot include an initial prompt.",
        ));
    }
    Ok(Some(id.to_string()))
}

pub(super) fn prepare_resume_snapshot(
    snapshot: &mut AgentProfileLaunchSnapshotV1,
    id: &str,
) -> HostResult<()> {
    let shape = adapter_for(&snapshot.agent_type)
        .and_then(|adapter| adapter.session_resume)
        .ok_or_else(|| HostError::format("This agent does not support session resume."))?;
    match &mut snapshot.launch {
        AgentProfileEffectiveLaunchV1::Managed { argv, .. } => {
            // fx's structured resumeLast setting must not override an explicit ID.
            if snapshot.agent_type == "fx" {
                argv.retain(|arg| arg != "--continue");
            }
        }
        AgentProfileEffectiveLaunchV1::Command { command } => {
            if !command_can_resume(command, shape)
                || apply_resume_to_command(command, shape, id, "/bin/sh").is_none()
            {
                return Err(HostError::format("This custom command cannot safely resume a session. Use a managed profile or a simple command without session selectors or shell operators."));
            }
        }
    }
    Ok(())
}

fn command_can_resume(command: &str, shape: AgentSessionResumeShape) -> bool {
    let command = command.trim();
    if command.is_empty()
        || command.chars().any(|ch| {
            ch.is_control()
                || matches!(
                    ch,
                    '|' | '&' | ';' | '<' | '>' | '$' | '`' | '(' | ')' | '%' | '!' | '^' | '#'
                )
        })
    {
        return false;
    }
    // Both insertion and wrapper detection need an unambiguous executable.
    let executable = command.split_whitespace().next().unwrap_or("");
    if command.ends_with('\\')
        || executable.ends_with('\\')
        || executable.contains(['\'', '"'])
        || is_launch_prefix(executable)
    {
        return false;
    }
    let mut quote = None;
    for ch in command.chars() {
        if matches!(ch, '\'' | '"') {
            if quote == Some(ch) {
                quote = None;
            } else if quote.is_none() {
                quote = Some(ch);
            }
        }
    }
    if quote.is_some() {
        return false;
    }
    // Only inspect selectors; never rebuild the user's opaque command line.
    let selectors = command.replace(['\'', '"', '\\'], "");
    let tokens = selectors.split_whitespace().collect::<Vec<_>>();
    !tokens.iter().skip(1).any(|token| {
        let token = token.split('=').next().unwrap_or("");
        (token == "-c" && !matches!(shape, AgentSessionResumeShape::Subcommand(_)))
            || matches!(
                token,
                "--" | "resume"
                    | "continue"
                    | "threads"
                    | "--resume"
                    | "--continue"
                    | "--session"
                    | "--session-id"
                    | "--conversation"
                    | "--last"
                    | "--fork"
                    | "--fork-session"
                    | "-r"
            )
    })
}

fn is_launch_prefix(executable: &str) -> bool {
    // Wrappers may consume either inserted subcommands or appended flags.
    // Keep paths and Windows executable suffixes equivalent.
    if executable.contains('=') {
        return true;
    }
    let name = executable
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(executable)
        .to_ascii_lowercase();
    let name = [".exe", ".cmd", ".bat"]
        .iter()
        .find_map(|suffix| name.strip_suffix(suffix))
        .unwrap_or(&name);
    matches!(
        name,
        "env"
            | "exec"
            | "command"
            | "sudo"
            | "nice"
            | "time"
            | "npx"
            | "npm"
            | "pnpm"
            | "yarn"
            | "bun"
            | "bunx"
            | "uv"
            | "uvx"
            | "pipx"
            | "nix"
            | "docker"
            | "podman"
            | "sh"
            | "bash"
            | "zsh"
            | "fish"
            | "cmd"
            | "powershell"
            | "pwsh"
            | "node"
            | "deno"
            | "python"
            | "python3"
            | "ruby"
            | "perl"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn explicit_resume_requires_a_safe_id_and_no_prompt() {
        assert_eq!(
            requested_resume_session(&json!({"resumeSessionId": " sess-1 "}), "").unwrap(),
            Some("sess-1".into())
        );
        for id in ["", "--last", "a b", "x;y", "x\ny", "%PATH%", "a\"b"] {
            assert!(
                requested_resume_session(&json!({"resumeSessionId": id}), "").is_err(),
                "{id}"
            );
        }
        assert!(requested_resume_session(&json!({"resumeSessionId": "sess-1"}), "hello").is_err());
    }

    #[test]
    fn command_resume_refuses_ambiguous_or_conflicting_commands() {
        for command in [
            "codex resume old",
            "codex --resume=old",
            "codex --res\"\"ume old",
            "codex # ignore the appended resume",
            "codex && echo hello",
            "codex --",
            "codex --model \"unclosed",
            "codex $(echo hi)",
        ] {
            assert!(
                !command_can_resume(command, AgentSessionResumeShape::Subcommand(&["resume"])),
                "{command}"
            );
        }
        assert!(command_can_resume(
            "codex --model gpt-5 --sandbox workspace-write",
            AgentSessionResumeShape::Subcommand(&["resume"])
        ));
        assert!(command_can_resume(
            "codex -c model_reasoning_effort=high",
            AgentSessionResumeShape::Subcommand(&["resume"])
        ));
        assert!(command_can_resume(
            "ccs work --permission-mode auto",
            AgentSessionResumeShape::Flag("--resume")
        ));
    }

    #[test]
    fn resume_rejects_assignments_and_package_launchers() {
        for command in [
            "CODEX_HOME=/tmp/custom codex",
            "CODEX_HOME='/tmp/custom home' codex",
            "npx @openai/codex",
            "npx --yes @openai/codex",
            "bunx @sourcegraph/amp",
            "pnpm dlx @openai/codex",
            "npm exec --package @openai/codex codex",
            "/usr/bin/env CODEX_HOME=/tmp/custom codex",
            "/usr/bin/npx @openai/codex",
            "C:\\tools\\npx.cmd @openai/codex",
            "NPX.EXE @openai/codex",
        ] {
            for shape in [
                AgentSessionResumeShape::Subcommand(&["resume"]),
                AgentSessionResumeShape::Subcommand(&["threads", "continue"]),
                AgentSessionResumeShape::Flag("--resume"),
                AgentSessionResumeShape::EqualsFlag("--resume"),
            ] {
                assert!(!command_can_resume(command, shape), "{command}");
            }
        }
        for command in [
            "codex --model test-model",
            "/opt/bin/codex --model test-model",
            "C:\\tools\\codex.exe --model test-model",
            "/tmp/record-agent.sh --model test-model",
        ] {
            assert!(
                command_can_resume(command, AgentSessionResumeShape::Subcommand(&["resume"])),
                "{command}"
            );
        }
    }

    #[test]
    fn resume_rejects_shell_wrappers_and_ambiguous_executable_boundaries() {
        for command in [
            "bash -lc 'claude --model opus'",
            "sh -lc 'claude --model opus'",
            "powershell.exe -Command 'claude --model opus'",
            "C:\\tools\\bash.exe -lc 'claude --model opus'",
            "\"bash\" -lc 'claude --model opus'",
            r"/opt/Agent\ Tools/codex --model test-model",
            r#"/opt/Agent" Tools"/codex --model test-model"#,
            r#""C:\Agent Tools\claude.exe" --model opus"#,
        ] {
            for shape in [
                AgentSessionResumeShape::Subcommand(&["resume"]),
                AgentSessionResumeShape::Flag("--resume"),
                AgentSessionResumeShape::EqualsFlag("--resume"),
            ] {
                assert!(!command_can_resume(command, shape), "{command}");
            }
        }
        assert!(command_can_resume(
            "ccs work --model opus",
            AgentSessionResumeShape::Flag("--resume")
        ));
        assert!(command_can_resume(
            r"C:\tools\claude.exe --model opus",
            AgentSessionResumeShape::Flag("--resume")
        ));
    }

    #[test]
    fn resume_retains_managed_options_on_every_shell() {
        use crate::terminal_host::orchestration::agent_registry::AGENT_ADAPTERS;
        use crate::terminal_host::orchestration::agent_session_resume::apply_resume_to_managed_launch;
        use crate::terminal_host::orchestration::managed_agent_launch::build_managed_agent_launch;
        use crate::terminal_host::orchestration::managed_launch_shell_rendering::render_managed_launch;
        for adapter in AGENT_ADAPTERS {
            let config = match adapter.agent_type {
                "codex" => {
                    json!({"model": "test-model", "effort": "high", "sandbox": "workspace-write", "approvalPolicy": "on-request"})
                }
                "claude" => {
                    json!({"ccsProfile": "work", "model": "opus", "permissionMode": "auto", "effort": "high"})
                }
                "fx" => json!({"resumeLast": true, "record": true}),
                _ => json!({}),
            };
            let launch = build_managed_agent_launch(adapter.agent_type, &config).unwrap();
            let mut snapshot: AgentProfileLaunchSnapshotV1 = serde_json::from_value(json!({
                "version": 1, "profile": {"id": "p", "name": "Profile", "revision": 0},
                "agentType": adapter.agent_type, "launchMode": "managed",
                "launch": {"kind": "managed", "executable": launch.executable, "argv": launch.arguments},
                "target": {"target": "localTerminal", "platform": "linux"},
                "initialDelivery": {"mechanism": {"kind": "positionalAfterTerminator"}, "replay": "once"}
            })).unwrap();
            prepare_resume_snapshot(&mut snapshot, "sess-1").unwrap();
            let mut resumed = snapshot.managed_launch().unwrap();
            let expected = resumed.arguments.clone();
            assert!(!expected.iter().any(|arg| arg == "--continue"));
            assert!(apply_resume_to_managed_launch(
                &mut resumed,
                adapter.session_resume.unwrap(),
                "sess-1"
            ));
            let retained = resumed
                .arguments
                .iter()
                .filter(|arg| expected.contains(arg))
                .cloned()
                .collect::<Vec<_>>();
            assert_eq!(retained, expected, "{}", adapter.agent_type);
            if adapter.agent_type == "claude" {
                assert_eq!(resumed.arguments[0], "work");
            }
            for shell in ["/bin/bash", "/bin/zsh", "pwsh.exe", "cmd.exe"] {
                let rendered = render_managed_launch(&resumed, shell);
                assert!(rendered.contains("sess-1"));
                for arg in &expected {
                    assert!(rendered.contains(arg), "{shell}: {rendered}");
                }
            }
        }
    }
}
