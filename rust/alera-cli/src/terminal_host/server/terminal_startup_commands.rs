use alera_core::runtime::WorkspaceTabRecord;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn terminal_session_id(tab: &WorkspaceTabRecord) -> String {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .unwrap_or(&tab.id)
        .to_string()
}

pub(super) fn initial_command(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("initialCommand")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
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
    tab.payload
        .get("initialPromptOnce")
        .and_then(Value::as_bool)
        == Some(true)
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

#[cfg(test)]
mod tests {
    use super::*;

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
