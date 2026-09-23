use alera_core::runtime::{
    OwnerAutomationPrecheck, OwnerAutomationPrecheckRequest, Project, RuntimeStore, LOCAL_HOST_ID,
};
use anyhow::{bail, Context, Result};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub(crate) enum OwnerPrecheckAction {
    Start,
    Probe,
    Status,
    Cancel,
}

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerPrecheckArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub metadata_base64: String,
    #[arg(long, value_enum)]
    pub action: OwnerPrecheckAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OwnerPrecheckEnvelope {
    pub project: Project,
    pub request: OwnerAutomationPrecheckRequest,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<alera_core::runtime::Workspace>,
}

pub(crate) async fn run(args: RemoteOwnerPrecheckArgs) -> Result<Value> {
    let envelope = parse(&args)?;
    if matches!(
        args.action,
        OwnerPrecheckAction::Start | OwnerPrecheckAction::Probe
    ) {
        inspect(&envelope).await?;
    }
    let capability = if envelope.request.workspace.is_some() {
        crate::terminal_host::protocol::RUNTIME_HOST_LINKED_OWNER_PRECHECK_CAPABILITY
    } else {
        crate::terminal_host::protocol::RUNTIME_HOST_OWNER_PRECHECK_CAPABILITY
    };
    if matches!(args.action, OwnerPrecheckAction::Probe) {
        let existing =
            crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
                &args.state_dir,
                capability,
            )
            .await?;
        return Ok(
            serde_json::json!({"version": 1, "request": envelope.request,
            "capability": capability, "runtimeRunning": existing.is_some()}),
        );
    }
    let mut client = if matches!(args.action, OwnerPrecheckAction::Start) {
        crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_with_required_capability(
            &args.state_dir,
            capability,
        )
        .await?
    } else {
        match crate::runtime_host_client::RuntimeHostRpcClient::connect_with_required_capability(
            &args.state_dir,
            capability,
        )
        .await?
        {
            Some(client) => client,
            None => return completed_without_runtime(&args.state_dir, &envelope).await,
        }
    };
    if !matches!(args.action, OwnerPrecheckAction::Status) {
        let store = RuntimeStore::open(&args.state_dir).await?;
        register_for_action(&store, &envelope, args.action).await?;
    }
    let verb = match args.action {
        OwnerPrecheckAction::Start => "automation.ownerPrecheck.start",
        OwnerPrecheckAction::Status => "automation.ownerPrecheck.status",
        OwnerPrecheckAction::Cancel => "automation.ownerPrecheck.cancel",
        OwnerPrecheckAction::Probe => bail!("Capability probes do not execute owner requests"),
    };
    let result = client.request_value(verb, &envelope.request).await?;
    if result.get("version").and_then(Value::as_u64) != Some(1) {
        bail!("Unsupported owner precheck response version");
    }
    let job: OwnerAutomationPrecheck = serde_json::from_value(
        result
            .get("job")
            .cloned()
            .context("Owner precheck response has no job")?,
    )?;
    if job.request != envelope.request {
        bail!("Owner precheck response does not match the requested operation");
    }
    Ok(result)
}

async fn completed_without_runtime(
    state_dir: &std::path::Path,
    envelope: &OwnerPrecheckEnvelope,
) -> Result<Value> {
    const UNVERIFIED: &str = "The owner runtime is unavailable; precheck closure remains unverified and no replacement runtime was started";
    if !tokio::fs::try_exists(state_dir.join(alera_core::runtime::RUNTIME_DATABASE_FILE_NAME))
        .await?
    {
        bail!(UNVERIFIED);
    }
    let store = RuntimeStore::open(state_dir).await?;
    let job = store
        .find_owner_automation_precheck(&envelope.request.operation_id)
        .await?
        .filter(|job| job.outcome.is_some())
        .context(UNVERIFIED)?;
    if job.request != envelope.request {
        bail!("Owner precheck response does not match the requested operation");
    }
    let processes = match &job.process_id {
        Some(id) => store.automation_precheck_processes(id).await?,
        None => Vec::new(),
    };
    Ok(serde_json::json!({"version":1,"job":job,"processes":processes}))
}

fn parse(args: &RemoteOwnerPrecheckArgs) -> Result<OwnerPrecheckEnvelope> {
    if !args.state_dir.is_absolute() || args.metadata_base64.len() > 1_048_576 {
        bail!("An absolute owner runtime directory and bounded precheck metadata are required");
    }
    let bytes = base64::engine::general_purpose::STANDARD.decode(&args.metadata_base64)?;
    let envelope: OwnerPrecheckEnvelope = serde_json::from_slice(&bytes)?;
    let request = &envelope.request;
    let id = uuid::Uuid::parse_str(&request.operation_id)?;
    if id.is_nil()
        || id.to_string() != request.operation_id
        || request.origin_id.trim().is_empty()
        || request.run_id.trim().is_empty()
        || envelope.project.id.trim().is_empty()
        || request.project_id != envelope.project.id
        || (request.workspace.is_none() && request.path != envelope.project.repo_path)
        || !std::path::Path::new(&request.path).is_absolute()
        || request.precheck.command.trim().is_empty()
        || !(1..=15 * 60).contains(&request.precheck.timeout_seconds)
    {
        bail!("Owner precheck metadata must identify its exact project, checkout, origin and run");
    }
    validate_workspace(&envelope)?;
    Ok(envelope)
}

async fn inspect(envelope: &OwnerPrecheckEnvelope) -> Result<()> {
    crate::owner_precheck_checkout::inspect(&envelope.request, envelope.project.kind).await
}

async fn register_project(store: &RuntimeStore, envelope: &OwnerPrecheckEnvelope) -> Result<()> {
    if envelope.request.workspace.is_some() {
        return register_linked_workspace(store, envelope).await;
    }
    store
        .register_owner_project_checkout(envelope.project.clone())
        .await?;
    Ok(())
}

async fn register_for_action(
    store: &RuntimeStore,
    envelope: &OwnerPrecheckEnvelope,
    action: OwnerPrecheckAction,
) -> Result<()> {
    if matches!(action, OwnerPrecheckAction::Start)
        || (matches!(action, OwnerPrecheckAction::Cancel)
            && store
                .find_owner_automation_precheck(&envelope.request.operation_id)
                .await?
                .is_none())
    {
        register_project(store, envelope).await?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "remote_owner_precheck_tests.rs"]
mod tests;

fn validate_workspace(envelope: &OwnerPrecheckEnvelope) -> Result<()> {
    use alera_core::runtime::{ProjectKind, WorkspaceKind, WorkspaceStatus};
    match (&envelope.request.workspace, &envelope.workspace) {
        (None, None) => Ok(()),
        (Some(scope), Some(workspace))
            if scope.kind == WorkspaceKind::Linked
                && envelope.project.kind == ProjectKind::GitRepository
                && workspace.kind == scope.kind
                && workspace.status == WorkspaceStatus::Active
                && !scope.workspace_id.trim().is_empty()
                && !scope.instance_id.trim().is_empty()
                && workspace.id == scope.workspace_id
                && workspace.instance_id == scope.instance_id
                && workspace.project_id == envelope.request.project_id
                && workspace.path == envelope.request.path
                && scope
                    .repository_path
                    .as_ref()
                    .is_some_and(|path| std::path::Path::new(path).is_absolute()) =>
        {
            Ok(())
        }
        _ => bail!("Owner precheck workspace metadata does not match its exclusive scope"),
    }
}

async fn register_linked_workspace(
    store: &RuntimeStore,
    envelope: &OwnerPrecheckEnvelope,
) -> Result<()> {
    validate_workspace(envelope)?;
    crate::owner_precheck_checkout::inspect(&envelope.request, envelope.project.kind).await?;
    let mut workspace = envelope
        .workspace
        .clone()
        .context("The exclusive owner task is missing")?;
    workspace.host_id = LOCAL_HOST_ID.into();
    let origin = envelope
        .request
        .workspace
        .as_ref()
        .and_then(|scope| scope.repository_path.as_deref())
        .context("The repository origin is missing")?;
    if let Some(existing) = store.find_workspace(&workspace.id).await? {
        let project = store
            .find_project(&workspace.project_id)
            .await?
            .context("The exclusive owner project is missing")?;
        if project.kind != envelope.project.kind {
            bail!("Owner precheck project type changed; no task was replaced");
        }
        let binding = store
            .find_workspace_checkout(&workspace.id)
            .await?
            .context("The exclusive checkout binding is missing")?;
        if existing.instance_id != workspace.instance_id
            || existing.project_id != workspace.project_id
            || existing.host_id != workspace.host_id
            || existing.kind != workspace.kind
            || existing.status != workspace.status
            || existing.path != workspace.path
            || binding.repository_path.as_deref() != Some(origin)
        {
            bail!(
                "Owner precheck task identity or repository origin changed; no task was replaced"
            );
        }
        return Ok(());
    }
    // The repository origin can be a legacy bare repository. Enrolling a task
    // must not turn that storage directory into a project checkout.
    store
        .register_project_identity(envelope.project.clone())
        .await?;
    store
        .insert_workspace_with_repository(workspace, origin)
        .await?;
    Ok(())
}
