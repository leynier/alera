use alera_core::runtime::{RuntimeStore, LOCAL_HOST_ID};
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerRecoveryArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub workspace_id: String,
    #[arg(long)]
    pub instance_id: String,
    #[arg(long)]
    pub project_id: String,
    #[arg(long, default_value_t = 20)]
    pub limit: u32,
}

pub(crate) async fn run(args: RemoteOwnerRecoveryArgs) -> Result<Value> {
    if !args.state_dir.is_absolute()
        || args.workspace_id.trim().is_empty()
        || args.instance_id.trim().is_empty()
        || args.project_id.trim().is_empty()
    {
        bail!("An absolute owner directory and exact task, instance and project identities are required");
    }
    let store = RuntimeStore::open_read_only(&args.state_dir)
        .await
        .context("Owner recovery state is unavailable; no runtime was started or state created")?;
    let workspace = store
        .find_workspace(&args.workspace_id)
        .await?
        .context("The owner has no recovery state for this task")?;
    if workspace.instance_id != args.instance_id
        || workspace.project_id != args.project_id
        || workspace.host_id != LOCAL_HOST_ID
    {
        bail!("Owner recovery belongs to a different task instance or project");
    }
    let mut items = crate::workspace_relocation_recovery::inspect(
        &store,
        &workspace.id,
        args.limit.clamp(1, 100),
    )
    .await?;
    items.retain(|item| {
        let source = &item.relocation.source;
        let destination = &item.relocation.destination;
        source.id == workspace.id
            && source.instance_id == workspace.instance_id
            && source.project_id == workspace.project_id
            && source.host_id == LOCAL_HOST_ID
            && destination.id == source.id
            && destination.instance_id == source.instance_id
            && destination.project_id == source.project_id
            && destination.host_id == LOCAL_HOST_ID
    });
    Ok(json!({"version":1,"workspace":workspace,"items":items,"platform":std::env::consts::OS}))
}
