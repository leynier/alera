use alera_core::runtime::WorkspaceTabRecord;

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::AgentInitialDeliveryMechanismV1;
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::agent_session_resume::{
    apply_resume_to_command, apply_resume_to_managed_launch,
};
use crate::terminal_host::orchestration::agent_startup_command::{
    append_initial_prompt_argument_for, command_with_initial_prompt_for,
};

use super::agent_native_session::native_session_resume;
use super::terminal_startup_commands::{
    auto_close_setup_command, auto_closes_on_success, initial_command, initial_delivery_mechanism,
    initial_managed_agent_launch, initial_prompt, tab_agent_type,
};

#[derive(Debug)]
pub(super) enum SpawnCommand {
    Line(String),
    Stdin { command: String, prompt: String },
}

pub(super) fn resolve_spawn_command(
    tab: &WorkspaceTabRecord,
    interactive_shell: &str,
) -> HostResult<Option<SpawnCommand>> {
    if let Some(command) = resume_spawn_command(tab, interactive_shell)? {
        return Ok(Some(command));
    }
    let managed_launch = initial_managed_agent_launch(tab)?;
    let adapter = tab_agent_type(tab).and_then(adapter_for);
    let delivery =
        initial_delivery_mechanism(tab)?.or_else(|| adapter.map(|item| item.startup_prompt.into()));
    let prompt = initial_prompt(tab);
    let prompt_arguments = delivery.as_ref().zip(prompt.as_deref());
    let command = if let Some(mut launch) = managed_launch {
        if let Some((mechanism, prompt)) = prompt_arguments {
            append_initial_prompt_argument_for(mechanism, &mut launch.arguments, prompt);
        }
        Some(
            crate::terminal_host::orchestration::managed_launch_shell_rendering::render_managed_launch(
                &launch,
                interactive_shell,
            ),
        )
    } else {
        initial_command(tab)?.map(|command| {
            let command = prompt_arguments
                .map(|(mechanism, prompt)| {
                    command_with_initial_prompt_for(mechanism, &command, prompt, interactive_shell)
                })
                .unwrap_or(command);
            wrap_auto_close(tab, command, interactive_shell)
        })
    };
    Ok(match (prompt_arguments, command) {
        (Some((AgentInitialDeliveryMechanismV1::StdinScript, prompt)), Some(command)) => {
            Some(SpawnCommand::Stdin {
                command,
                prompt: prompt.to_string(),
            })
        }
        (_, Some(command)) => Some(SpawnCommand::Line(command)),
        (_, None) => None,
    })
}

fn resume_spawn_command(
    tab: &WorkspaceTabRecord,
    interactive_shell: &str,
) -> HostResult<Option<SpawnCommand>> {
    let Some(resume) = native_session_resume(tab) else {
        return Ok(None);
    };
    if let Some(mut launch) = initial_managed_agent_launch(tab)? {
        if apply_resume_to_managed_launch(&mut launch, resume.shape, resume.session_id) {
            return Ok(Some(SpawnCommand::Line(
                crate::terminal_host::orchestration::managed_launch_shell_rendering::render_managed_launch(
                    &launch,
                    interactive_shell,
                ),
            )));
        }
        return Ok(None);
    }
    Ok(initial_command(tab)?.and_then(|command| {
        apply_resume_to_command(&command, resume.shape, resume.session_id, interactive_shell)
            .map(|command| SpawnCommand::Line(wrap_auto_close(tab, command, interactive_shell)))
    }))
}

fn wrap_auto_close(tab: &WorkspaceTabRecord, command: String, interactive_shell: &str) -> String {
    if auto_closes_on_success(tab) {
        auto_close_setup_command(&command, interactive_shell)
    } else {
        command
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::orchestration::agent_profile_launch_snapshot::AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY;
    use crate::terminal_host::orchestration::agent_session_resume::{
        AGENT_NATIVE_SESSION_AGENT_KEY, AGENT_NATIVE_SESSION_ID_KEY,
    };
    use chrono::Utc;
    use serde_json::json;

    fn tab(payload: serde_json::Value) -> WorkspaceTabRecord {
        WorkspaceTabRecord {
            id: "tab-1".into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Agent".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload,
        }
    }

    fn line(tab: &WorkspaceTabRecord) -> String {
        match resolve_spawn_command(tab, "/bin/zsh").unwrap() {
            Some(SpawnCommand::Line(command)) => command,
            other => panic!("expected a launch line, got {other:?}"),
        }
    }

    #[test]
    fn resume_path_replaces_the_initial_prompt_with_the_stored_session() {
        let snapshot = json!({
            "version": 1,
            "profile": {"id": "p1", "name": "Codex", "revision": 0},
            "agentType": "codex",
            "launchMode": "managed",
            "launch": {"kind": "managed", "executable": "codex", "argv": ["--search"]},
            "target": {"target": "localTerminal", "platform": "linux"},
            "initialDelivery": {"mechanism": {"kind": "positionalAfterTerminator"}, "replay": "once"}
        });
        let resumed = tab(json!({
            AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY: snapshot,
            "initialPrompt": "Do the work",
            AGENT_NATIVE_SESSION_ID_KEY: "sess-1",
            AGENT_NATIVE_SESSION_AGENT_KEY: "codex",
        }));
        assert_eq!(line(&resumed), "'codex' 'resume' 'sess-1' '--search'");

        let claude = tab(json!({
            "agentType": "claude",
            "initialCommand": "claude --permission-mode auto",
            "initialPrompt": "Do the work",
            AGENT_NATIVE_SESSION_ID_KEY: "sess-1",
            AGENT_NATIVE_SESSION_AGENT_KEY: "claude",
        }));
        assert_eq!(
            line(&claude),
            "claude --permission-mode auto '--resume' 'sess-1'"
        );
    }

    #[test]
    fn missing_id_path_keeps_the_original_prompt_launch() {
        let tab = tab(json!({
            "agentType": "claude",
            "initialCommand": "claude",
            "initialPrompt": "Do the work",
        }));
        assert_eq!(line(&tab), "claude -- 'Do the work'");
        assert!(native_session_resume(&tab).is_none());
    }
}
