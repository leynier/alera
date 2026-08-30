use crate::terminal_host::emulator::EmulatorManager;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) async fn close_tab(
    manager: Option<&mut EmulatorManager>,
    tab_id: &str,
    ended_pointer_tab_ids: &mut Vec<String>,
    closed_session_tab_ids: &mut Vec<String>,
) -> HostResult<()> {
    let Some(manager) = manager else {
        return Ok(());
    };
    ended_pointer_tab_ids.push(tab_id.to_string());
    let warnings = manager.close_tab(tab_id).await;
    if !manager.contains(tab_id) {
        closed_session_tab_ids.push(tab_id.to_string());
    }
    ensure_emulators_closed(warnings, &format!("mobile emulator tab `{tab_id}`"))
}

pub(super) async fn close_workspace(
    manager: Option<&mut EmulatorManager>,
    workspace_id: &str,
    ended_pointer_tab_ids: &mut Vec<String>,
    closed_session_tab_ids: &mut Vec<String>,
) -> HostResult<()> {
    let Some(manager) = manager else {
        return Ok(());
    };
    let tab_ids = manager.tab_ids_for_workspace(workspace_id);
    ended_pointer_tab_ids.extend(tab_ids.iter().cloned());
    let warnings = manager.close_workspace(workspace_id).await;
    closed_session_tab_ids.extend(
        tab_ids
            .into_iter()
            .filter(|tab_id| !manager.contains(tab_id)),
    );
    ensure_emulators_closed(
        warnings,
        &format!("mobile emulators for workspace `{workspace_id}`"),
    )
}

pub(super) async fn close_workspaces(
    mut manager: Option<&mut EmulatorManager>,
    workspace_ids: &[String],
    ended_pointer_tab_ids: &mut Vec<String>,
    closed_session_tab_ids: &mut Vec<String>,
) -> HostResult<()> {
    for workspace_id in workspace_ids {
        close_workspace(
            manager.as_deref_mut(),
            workspace_id,
            ended_pointer_tab_ids,
            closed_session_tab_ids,
        )
        .await?;
    }
    Ok(())
}

fn ensure_emulators_closed(warnings: Vec<String>, target: &str) -> HostResult<()> {
    if warnings.is_empty() {
        return Ok(());
    }
    Err(HostError::state(format!(
        "Could not close {target}: {}",
        warnings.join("; ")
    )))
}
