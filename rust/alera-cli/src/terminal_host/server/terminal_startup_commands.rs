use alera_core::runtime::WorkspaceTabRecord;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::{
    AgentInitialDeliveryMechanismV1, AgentInitialDeliveryReplayV1, AgentProfileLaunchSnapshotV1,
    AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY,
};

pub(super) fn terminal_session_id(tab: &WorkspaceTabRecord) -> String {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .unwrap_or(&tab.id)
        .to_string()
}

pub(super) fn initial_command(tab: &WorkspaceTabRecord) -> HostResult<Option<String>> {
    if let Some(snapshot) = agent_profile_launch_snapshot(tab)? {
        return Ok(snapshot.command().map(str::to_string));
    }
    Ok(tab
        .payload
        .get("initialCommand")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string))
}

pub(super) fn auto_closes_on_success(tab: &WorkspaceTabRecord) -> bool {
    tab.payload
        .get("autoCloseOnSuccess")
        .and_then(Value::as_bool)
        == Some(true)
}

pub(super) fn auto_close_setup_command(command: &str, interactive_shell: &str) -> String {
    let executable = interactive_shell
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(interactive_shell)
        .to_ascii_lowercase();
    match executable.as_str() {
        "cmd" | "cmd.exe" => format!("{command} & exit /b"),
        "powershell" | "powershell.exe" | "pwsh" | "pwsh.exe" => {
            format!("& {{ {command} }}; exit $LASTEXITCODE")
        }
        _ => format!("exec {command}"),
    }
}

pub(super) fn initial_managed_agent_launch(
    tab: &WorkspaceTabRecord,
) -> HostResult<Option<crate::terminal_host::orchestration::managed_agent_launch::ManagedAgentLaunch>>
{
    if let Some(snapshot) = agent_profile_launch_snapshot(tab)? {
        return Ok(snapshot.managed_launch());
    }
    tab.payload
        .get("initialManagedAgentLaunch")
        .filter(|value| !value.is_null())
        .cloned()
        .map(serde_json::from_value)
        .transpose()
        .map_err(|error| HostError::format(format!("invalid managed agent launch: {error}")))
}

pub(super) fn delivers_initial_command_once(tab: &WorkspaceTabRecord) -> bool {
    tab.payload
        .get("initialCommandOnce")
        .and_then(Value::as_bool)
        == Some(true)
}

pub(super) fn delivers_initial_prompt_once(tab: &WorkspaceTabRecord) -> bool {
    if let Ok(Some(snapshot)) = agent_profile_launch_snapshot(tab) {
        return snapshot.initial_delivery.replay == AgentInitialDeliveryReplayV1::Once;
    }
    tab.payload
        .get("initialPromptOnce")
        .and_then(Value::as_bool)
        == Some(true)
}

pub(super) fn replays_initial_prompt_on_restart(tab: &WorkspaceTabRecord) -> HostResult<bool> {
    Ok(match agent_profile_launch_snapshot(tab)? {
        Some(snapshot) => {
            snapshot.initial_delivery.replay == AgentInitialDeliveryReplayV1::OnRestart
        }
        None => !delivers_initial_prompt_once(tab),
    })
}

pub(super) fn initial_prompt(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("initialPrompt")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn pending_agent_type(tab: &WorkspaceTabRecord) -> Option<&str> {
    tab.payload
        .pointer("/pendingAgentPrompt/agent")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
}

/// Which agent the tab launches, for deciding the shape of its initial prompt.
///
/// The fallbacks read tabs written by an older host, which named the agent only
/// inside the payload it was going to deliver later. The app attaches to
/// whichever sidecar is already running, so both spellings have to resolve.
pub(super) fn tab_agent_type(tab: &WorkspaceTabRecord) -> Option<&str> {
    if let Some(agent_type) = tab
        .payload
        .pointer("/agentProfileLaunchV1/agentType")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
    {
        return Some(agent_type);
    }
    [
        "/agentType",
        "/pendingAgentPrompt/agent",
        "/orchestrationSpawn/agent",
    ]
    .into_iter()
    .find_map(|pointer| {
        tab.payload
            .pointer(pointer)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
    })
}

pub(super) fn initial_delivery_mechanism(
    tab: &WorkspaceTabRecord,
) -> HostResult<Option<AgentInitialDeliveryMechanismV1>> {
    Ok(agent_profile_launch_snapshot(tab)?.map(|snapshot| snapshot.initial_delivery.mechanism))
}

pub(super) fn agent_profile_id(tab: &WorkspaceTabRecord) -> Option<&str> {
    tab.payload
        .pointer("/agentProfileLaunchV1/profile/id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .or_else(|| {
            tab.payload
                .get("agentProfileId")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
        })
}

fn agent_profile_launch_snapshot(
    tab: &WorkspaceTabRecord,
) -> HostResult<Option<AgentProfileLaunchSnapshotV1>> {
    let snapshot: Option<AgentProfileLaunchSnapshotV1> = tab
        .payload
        .get(AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY)
        .filter(|value| !value.is_null())
        .cloned()
        .map(serde_json::from_value)
        .transpose()
        .map_err(|error| {
            HostError::format(format!("invalid agent profile launch snapshot: {error}"))
        })?;
    if snapshot
        .as_ref()
        .is_some_and(|snapshot| snapshot.version != 1)
    {
        return Err(HostError::format(
            "unsupported agent profile launch snapshot version".to_string(),
        ));
    }
    Ok(snapshot)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::json;

    fn tab(payload: Value) -> WorkspaceTabRecord {
        let now = Utc::now();
        WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "terminal".to_string(),
            title: "Agent".to_string(),
            created_at: now,
            updated_at: now,
            payload,
        }
    }

    #[test]
    fn legacy_agent_tab_launch_fields_remain_readable() {
        let tab = tab(json!({
            "initialCommand": "codex --search",
            "agentType": "codex",
            "agentProfileId": "legacy-profile",
            "initialPromptOnce": true
        }));

        assert_eq!(
            initial_command(&tab).unwrap().as_deref(),
            Some("codex --search")
        );
        assert_eq!(tab_agent_type(&tab), Some("codex"));
        assert_eq!(agent_profile_id(&tab), Some("legacy-profile"));
        assert!(delivers_initial_prompt_once(&tab));
        assert!(initial_delivery_mechanism(&tab).unwrap().is_none());
    }

    #[test]
    fn setup_command_replaces_posix_shell() {
        assert_eq!(
            auto_close_setup_command("/bin/sh \"/tmp/setup.sh\"", "/bin/zsh"),
            "exec /bin/sh \"/tmp/setup.sh\""
        );
    }

    #[test]
    fn setup_command_preserves_cmd_exit_status() {
        assert_eq!(
            auto_close_setup_command("cmd /d /c \"C:\\\\setup.cmd\"", "cmd.exe"),
            "cmd /d /c \"C:\\\\setup.cmd\" & exit /b"
        );
    }

    #[test]
    fn setup_command_preserves_powershell_exit_status() {
        assert_eq!(
            auto_close_setup_command("cmd /d /c \"C:\\\\setup.cmd\"", "pwsh.exe"),
            "& { cmd /d /c \"C:\\\\setup.cmd\" }; exit $LASTEXITCODE"
        );
    }
}
