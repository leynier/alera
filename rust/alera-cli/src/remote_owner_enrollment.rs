use alera_core::runtime::{RuntimeStore, WorkspaceKind};
use anyhow::{bail, Result};
use std::path::Path;

pub(crate) async fn enroll_never_started(
    state_dir: &Path,
    workspace_id: &str,
    instance_id: &str,
    kind: WorkspaceKind,
    encoded: &str,
) -> Result<()> {
    use crate::remote_workspace_owner::{parse_registration, register, RemoteWorkspaceOwnerArgs};
    let registration = parse_registration(&RemoteWorkspaceOwnerArgs {
        state_dir: state_dir.into(),
        metadata_base64: encoded.into(),
    })?;
    if registration.workspace.id != workspace_id
        || registration.workspace.instance_id != instance_id
        || registration.workspace.kind != kind
    {
        bail!("Never-started enrollment belongs to another task instance or checkout kind");
    }
    let store = RuntimeStore::open(state_dir).await?;
    register(&store, registration).await?;
    require_never_started(&store, workspace_id, instance_id).await
}

pub(crate) async fn require_never_started(
    store: &RuntimeStore,
    workspace_id: &str,
    instance_id: &str,
) -> Result<()> {
    if store
        .workspace_terminal_launch_attempted(workspace_id, instance_id)
        .await?
        != Some(false)
    {
        bail!("The owner recorded an earlier terminal launch attempt; remote process closure is unverified");
    }
    store
        .require_workspace_process_closure(workspace_id)
        .await?;
    store.validate_workspace_setup_idle(workspace_id).await?;
    Ok(())
}
