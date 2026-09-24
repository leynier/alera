use alera_core::runtime::{RuntimeStore, WorkspaceRelocationPhase, LOCAL_HOST_ID};
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, clap::ValueEnum, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum OwnerSetupAction {
    Run,
    Cancel,
    Recover,
}

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerSetupArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub workspace_id: String,
    #[arg(long)]
    pub instance_id: String,
    #[arg(long)]
    pub project_id: String,
    #[arg(long)]
    pub relocation_id: uuid::Uuid,
    #[arg(long)]
    pub attempt_id: Option<uuid::Uuid>,
    #[arg(long, value_enum)]
    pub action: OwnerSetupAction,
}

pub(crate) async fn run(args: RemoteOwnerSetupArgs) -> Result<Value> {
    if !args.state_dir.is_absolute()
        || args.workspace_id.trim().is_empty()
        || args.instance_id.trim().is_empty()
        || args.project_id.trim().is_empty()
        || (!matches!(args.action, OwnerSetupAction::Run) && args.attempt_id.is_none())
    {
        bail!("Provide the exact owner task, project, relocation and setup attempt before changing setup state");
    }
    let store = RuntimeStore::open_read_only(&args.state_dir)
        .await
        .context("Owner setup state is unavailable; no runtime was started")?;
    let id = args.relocation_id.to_string();
    let workspace = store
        .find_workspace(&args.workspace_id)
        .await?
        .context("Owner task not found")?;
    let journal = store
        .find_workspace_relocation(&id)
        .await?
        .context("Owner relocation not found")?;
    let latest = store
        .list_workspace_relocation_recovery(&workspace.id, 1)
        .await?;
    if workspace.instance_id != args.instance_id
        || workspace.project_id != args.project_id
        || workspace.host_id != LOCAL_HOST_ID
        || journal.destination.id != workspace.id
        || journal.destination.instance_id != workspace.instance_id
        || journal.destination.project_id != workspace.project_id
        || journal.destination.host_id != workspace.host_id
        || journal.destination.path != workspace.path
        || journal.destination.kind != workspace.kind
        || journal.phase != WorkspaceRelocationPhase::Completed
        || latest.first().is_none_or(|entry| entry.relocation.id != id)
    {
        bail!("Setup no longer belongs to this task instance and completed relocation");
    }
    let before = store
        .find_relocation_setup(&id)
        .await?
        .context("Owner setup recipe is unavailable")?;
    let attempt = args.attempt_id.map(|id| id.to_string());
    if attempt
        .as_deref()
        .is_some_and(|id| before.attempt_id.as_deref() != Some(id))
    {
        bail!("Owner setup attempt changed; inspect recovery before retrying");
    }
    let mut client = crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
        &args.state_dir, crate::terminal_host::protocol::RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY,
    ).await?.context("The owner runtime is unavailable; process closure remains unverified and no replacement runtime was started")?;
    let verb = match args.action {
        OwnerSetupAction::Run => "workspace.runSetup",
        OwnerSetupAction::Cancel => "workspace.cancelRelocationSetup",
        OwnerSetupAction::Recover => "workspace.recoverRelocationSetup",
    };
    let result = client
        .request_value(
            verb,
            &json!({"id":workspace.id,"relocationId":id,"attemptId":attempt}),
        )
        .await?;
    let setup = store
        .find_relocation_setup(&id)
        .await?
        .context("The owner setup receipt disappeared; inspect recovery")?;
    Ok(
        json!({"version":1,"workspace":workspace,"relocationId":id,"action":args.action,"result":result,"setup":setup}),
    )
}
