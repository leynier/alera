use alera_core::runtime::{AutomationState, AutomationTarget, RuntimeStore};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRemovalDependency {
    pub id: String,
    pub name: String,
    pub active_runs: usize,
    pub requires_pause: bool,
}

#[cfg(test)]
#[path = "project_removal_dependency_rpc_tests.rs"]
mod project_rpc_tests;

pub async fn prepare_cli_removal_dependencies(
    client: &mut crate::runtime_host_client::RuntimeHostRpcClient,
    workspace_id: &str,
    approved: bool,
) -> Result<()> {
    prepare_cli_dependencies(
        client,
        workspace_id,
        approved,
        "workspace.removalDependencies",
        "Workspace",
    )
    .await
}

pub async fn prepare_cli_project_removal_dependencies(
    client: &mut crate::runtime_host_client::RuntimeHostRpcClient,
    project_id: &str,
    approved: bool,
) -> Result<()> {
    prepare_cli_dependencies(
        client,
        project_id,
        approved,
        "project.removalDependencies",
        "Project",
    )
    .await
}

async fn prepare_cli_dependencies(
    client: &mut crate::runtime_host_client::RuntimeHostRpcClient,
    workspace_id: &str,
    approved: bool,
    request_type: &str,
    owner_kind: &str,
) -> Result<()> {
    let dependencies: Vec<WorkspaceRemovalDependency> = client
        .request(request_type, &serde_json::json!({"id": workspace_id}))
        .await?;
    if dependencies.is_empty() {
        return Ok(());
    }
    if !approved {
        bail!("{owner_kind} removal affects these automations: {}. Review this impact and pass --pause-automations-and-cancel-runs to pause them and cancel all their active runs. Their history is preserved; their targets must be updated before resuming.", dependencies.iter().map(|dependency| format!("{} ({} active runs)", dependency.name, dependency.active_runs)).collect::<Vec<_>>().join(", "));
    }
    let approved_ids = dependencies
        .iter()
        .map(|dependency| dependency.id.clone())
        .collect::<std::collections::HashSet<_>>();
    tokio::time::timeout(std::time::Duration::from_secs(30), async {
        for dependency in dependencies.iter().filter(|dependency| dependency.requires_pause) {
            client.request_value("automation.pause", &serde_json::json!({"id": dependency.id, "activeRuns": "cancel-active", "reason": format!("{owner_kind} removal requested")})).await?;
        }
        loop {
            let pending: Vec<WorkspaceRemovalDependency> = client.request(request_type, &serde_json::json!({"id": workspace_id})).await?;
            let pending = pending.iter().filter(|dependency| dependency.requires_pause).collect::<Vec<_>>();
            if pending.is_empty() { return Ok(()); }
            if pending.iter().any(|dependency| !approved_ids.contains(&dependency.id)) { bail!("Automation dependencies changed; review their impact again before removing the workspace"); }
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        }
    }).await.map_err(|_| anyhow::anyhow!("Automation shutdown has not completed. The target was preserved; retry after its runs stop."))?
}

pub async fn workspace_removal_dependencies(
    store: &RuntimeStore,
    workspace_id: &str,
) -> Result<Vec<WorkspaceRemovalDependency>> {
    let definitions = store.list_automations(false).await?;
    let runs = store.list_active_automation_runs().await?;
    let mut result = Vec::new();
    for definition in definitions {
        let targets_workspace = match &definition.target {
            AutomationTarget::ExistingTab {
                workspace_id: target,
                ..
            }
            | AutomationTarget::FreshTab {
                workspace_id: target,
                ..
            } => target == workspace_id,
            AutomationTarget::ManagedWorkspace {
                source_workspace_id,
                ..
            } => source_workspace_id == workspace_id,
            AutomationTarget::ProjectCheckout { .. } => false,
        };
        let affected_run = runs.iter().any(|run| {
            run.automation_id == definition.id
                && (run.workspace_id.as_deref() == Some(workspace_id)
                    || run
                        .target_identity
                        .as_ref()
                        .and_then(|identity| identity.workspace_id.as_deref())
                        == Some(workspace_id))
        });
        if !targets_workspace && !affected_run {
            continue;
        }
        let active_runs = runs
            .iter()
            .filter(|run| run.automation_id == definition.id)
            .count();
        result.push(WorkspaceRemovalDependency {
            id: definition.id,
            name: definition.name,
            active_runs,
            requires_pause: definition.state == AutomationState::Active || active_runs > 0,
        });
    }
    Ok(result)
}
