use alera_core::runtime::{
    RuntimeStore, Workspace, WorkspaceKind, WorkspaceRelocationIntent, WorkspaceRelocationPhase,
    LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Result};
use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};

#[path = "remote_owner_relocation_preparation.rs"]
mod preparation;

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerRelocationArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub request_base64: String,
    #[arg(long)]
    pub prepare_only: bool,
    #[arg(long)]
    pub enroll_never_started_base64: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OwnerRelocationRequest {
    workspace: Workspace,
    intent: WorkspaceRelocationIntent,
    relocation_id: uuid::Uuid,
    workspace_root: Option<String>,
    setup_config: Option<alera_core::runtime::ProjectConfig>,
}

pub(crate) async fn run(args: RemoteOwnerRelocationArgs) -> Result<Value> {
    let request = parse_request(&args)?;
    if let Some(encoded) = &args.enroll_never_started_base64 {
        let metadata = crate::remote_workspace_owner::parse_registration(
            &crate::remote_workspace_owner::RemoteWorkspaceOwnerArgs {
                state_dir: args.state_dir.clone(),
                metadata_base64: encoded.clone(),
            },
        )?;
        let mut source = metadata.workspace;
        source.host_id = LOCAL_HOST_ID.into();
        if !same_location(&source, &request.workspace) {
            bail!("Owner enrollment does not match the relocation's original task and checkout");
        }
    }
    let capability = crate::terminal_host::protocol::RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY;
    let mut connection =
        crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
            &args.state_dir,
            capability,
        )
        .await?;
    if connection.is_none() {
        if args.enroll_never_started_base64.is_none() {
            bail!("The owner runtime is unavailable. Verify its processes before relocating the task; no replacement runtime was started.");
        }
        crate::terminal_host::runtime_owner::ensure_no_live_owner(&args.state_dir)?;
    }
    let store = RuntimeStore::open(&args.state_dir).await?;
    let id = request.relocation_id.to_string();
    let prior = store.find_workspace_relocation(&id).await?;
    if let Some(encoded) = &args.enroll_never_started_base64 {
        let source = &request.workspace;
        if prior.is_some() {
            crate::remote_owner_enrollment::require_never_started(
                &store,
                &source.id,
                &source.instance_id,
            )
            .await?;
        } else {
            crate::remote_owner_enrollment::enroll_never_started(
                &args.state_dir,
                &source.id,
                &source.instance_id,
                source.kind,
                encoded,
            )
            .await?;
        }
        if connection.is_none() {
            connection = Some(crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_with_required_capability(&args.state_dir, capability).await?);
        }
    }
    let mut client = connection.ok_or_else(|| anyhow!("The owner runtime is unavailable"))?;
    let expected = prior
        .as_ref()
        .map_or(&request.workspace, |journal| &journal.source);
    if !same_location(expected, &request.workspace) {
        bail!("The relocation ID belongs to another task instance or source checkout");
    }
    let current = store
        .find_workspace(&request.workspace.id)
        .await?
        .ok_or_else(|| anyhow!("Register the task with its owner before relocating it"))?;
    let current_expected = prior.as_ref().map_or(&request.workspace, |journal| {
        if matches!(
            journal.phase,
            WorkspaceRelocationPhase::Committed
                | WorkspaceRelocationPhase::RemovingSource
                | WorkspaceRelocationPhase::Completed
        ) {
            &journal.destination
        } else {
            &journal.source
        }
    });
    if !same_location(&current, current_expected) {
        bail!("The owner task identity or location changed; refresh its relocation history");
    }
    if args.prepare_only {
        let journal = preparation::prepare(&store, &request, prior.as_ref()).await?;
        return Ok(json!({"version":1,"prepared":true,"relocation":journal,"workspace":current}));
    }
    let operation = if request.intent.to_project_checkout {
        "handOn"
    } else {
        "handOff"
    };
    let payload = json!({
        "id":request.workspace.id,
        "expectedInstanceId":request.workspace.instance_id,
        "relocationId":id,
        "branch":request.intent.branch,
        "path":request.intent.destination_path,
        "replacementBranch":request.intent.replacement_branch,
        "reuseExistingBranch":request.intent.replacement_branch.is_some(),
        "moveChanges":request.intent.move_changes,
        "sharedImpactConfirmed":true,
        "closeSessions":true,
    });
    let result = crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard(
        &mut client,
        operation,
        &payload,
    )
    .await?;
    let journal = store.find_workspace_relocation(&id).await?
        .ok_or_else(|| anyhow!("The owner did not persist the relocation journal; preserve Home state and retry the same relocation ID"))?;
    let workspace: Workspace = serde_json::from_value(result["workspace"].clone())?;
    if journal.phase != WorkspaceRelocationPhase::Completed
        || !same_location(&journal.source, &request.workspace)
        || !same_location(&workspace, &journal.destination)
    {
        bail!("The owner response does not verify the requested relocation; preserve Home state and inspect recovery");
    }
    Ok(json!({"version":1,"relocation":journal,"workspace":workspace,"result":result}))
}

fn same_location(left: &Workspace, right: &Workspace) -> bool {
    left.id == right.id
        && left.instance_id == right.instance_id
        && left.project_id == right.project_id
        && left.host_id == LOCAL_HOST_ID
        && right.host_id == LOCAL_HOST_ID
        && left.path == right.path
        && left.kind == right.kind
}

fn parse_request(args: &RemoteOwnerRelocationArgs) -> Result<OwnerRelocationRequest> {
    if !args.state_dir.is_absolute() || args.request_base64.len() > 1_048_576 {
        bail!("An absolute owner runtime directory and bounded relocation request are required");
    }
    let bytes = base64::engine::general_purpose::STANDARD.decode(&args.request_base64)?;
    let request: OwnerRelocationRequest = serde_json::from_slice(&bytes)?;
    let intent = &request.intent;
    if request.workspace.id.trim().is_empty()
        || request.workspace.instance_id.trim().is_empty()
        || request.workspace.host_id != LOCAL_HOST_ID
        || intent.workspace_id != request.workspace.id
        || !intent.shared_impact_confirmed
    {
        bail!("Confirm the shared impact and provide the exact owner-local task identity");
    }
    if request.setup_config.is_some() && (!args.prepare_only || intent.to_project_checkout) {
        bail!("Setup configuration is accepted only during Hand Off preparation");
    }
    if request.workspace_root.is_some()
        && (!args.prepare_only || intent.destination_path.is_some() || intent.to_project_checkout)
    {
        bail!("Choose a worktree root only during Hand Off preparation and without an explicit destination");
    }
    if intent.to_project_checkout {
        if request.workspace.kind != WorkspaceKind::Linked
            || intent.destination_path.is_some()
            || intent.branch.is_some()
            || intent.replacement_branch.is_some()
            || !intent.move_changes
        {
            bail!("Hand On requires a linked task and moves its changes to the registered project checkout");
        }
    } else if request.workspace.kind != WorkspaceKind::Main
        || (!args.prepare_only
            && intent
                .destination_path
                .as_deref()
                .is_none_or(|path| path.trim().is_empty()))
        || intent
            .branch
            .as_deref()
            .is_none_or(|branch| branch.trim().is_empty())
        || (intent.replacement_branch.is_some() && !intent.move_changes)
    {
        bail!("Hand Off requires a shared task, destination and branch; moving the current branch must move its changes");
    }
    Ok(request)
}

#[cfg(test)]
#[path = "remote_owner_relocation_tests.rs"]
mod tests;
