use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Result};

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RemoteWorkspaceOwnerRegistration {
    pub project: Project,
    pub workspace: Workspace,
    pub repository_path: Option<String>,
}

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteWorkspaceOwnerArgs {
    #[arg(long)]
    pub state_dir: std::path::PathBuf,
    #[arg(long)]
    pub metadata_base64: String,
}

pub(crate) async fn run(args: RemoteWorkspaceOwnerArgs) -> Result<Workspace> {
    let registration = parse_registration(&args)?;
    let store = RuntimeStore::open(&args.state_dir).await?;
    register(&store, registration).await
}

pub(crate) fn parse_registration(
    args: &RemoteWorkspaceOwnerArgs,
) -> Result<RemoteWorkspaceOwnerRegistration> {
    use base64::Engine;
    if !args.state_dir.is_absolute() {
        bail!("An absolute owner runtime directory is required");
    }
    if args.metadata_base64.len() > 1_048_576 {
        bail!("Remote owner metadata is too large");
    }
    let bytes = base64::engine::general_purpose::STANDARD.decode(&args.metadata_base64)?;
    Ok(serde_json::from_slice(&bytes)?)
}

pub(crate) async fn register(
    store: &RuntimeStore,
    registration: RemoteWorkspaceOwnerRegistration,
) -> Result<Workspace> {
    let RemoteWorkspaceOwnerRegistration {
        mut project,
        mut workspace,
        repository_path,
    } = registration;
    if project.id.trim().is_empty()
        || workspace.id.trim().is_empty()
        || workspace.instance_id.trim().is_empty()
        || workspace.project_id != project.id
        || workspace.status != WorkspaceStatus::Active
    {
        bail!("An active task with stable project, workspace and instance identities is required");
    }
    let inspection =
        crate::project_checkout_inspection::inspect(project.repo_path.clone(), project.kind)
            .await?;
    project.repo_path = inspection.path;
    let path = workspace.path.clone();
    let (path, repository_path) =
        tokio::task::spawn_blocking(move || -> Result<(String, Option<String>)> {
            let canonical = |path: String| -> Result<String> {
                crate::windows_path_form::canonicalize(path)?
                    .to_str()
                    .map(str::to_string)
                    .ok_or_else(|| anyhow!("Owner checkout path is not valid UTF-8"))
            };
            Ok((
                canonical(path)?,
                repository_path.map(canonical).transpose()?,
            ))
        })
        .await??;
    workspace.path = path;
    workspace.host_id = LOCAL_HOST_ID.into();
    let mut owner_repository = project.repo_path.clone();
    match workspace.kind {
        WorkspaceKind::Main if workspace.path == project.repo_path => {
            if repository_path
                .as_deref()
                .is_some_and(|path| !crate::windows_path_form::same_path(path, &project.repo_path))
            {
                bail!("A shared task cannot use a different repository origin");
            }
            workspace.branch = inspection.branch
        }
        WorkspaceKind::Main => bail!("A shared task must use the registered project checkout"),
        WorkspaceKind::Linked => {
            if project.kind != ProjectKind::GitRepository {
                bail!("A linked task requires a Git repository");
            }
            let repository = repository_path.unwrap_or_else(|| project.repo_path.clone());
            let path = workspace.path.clone();
            let (branch, repository) =
                tokio::task::spawn_blocking(move || -> Result<(String, String)> {
                    let repository = crate::windows_path_form::canonicalize(repository)?
                        .to_str()
                        .map(str::to_owned)
                        .ok_or_else(|| anyhow!("Repository path is not valid UTF-8"))?;
                    let expected_path = std::fs::canonicalize(&path)?;
                    if path == repository
                        || !alera_core::git::checkouts_share_repository(&repository, &path)?
                        || !alera_core::git::list_worktrees(&repository)?
                            .iter()
                            .any(|entry| {
                                std::fs::canonicalize(&entry.path)
                                    .is_ok_and(|path| path == expected_path)
                            })
                    {
                        bail!("The linked task is not owned by the registered repository");
                    }
                    Ok((alera_core::git::current_branch(&path)?, repository))
                })
                .await??;
            workspace.branch = Some(branch);
            owner_repository = repository;
        }
    }
    if let Some(existing) = store.find_workspace(&workspace.id).await? {
        if existing.instance_id != workspace.instance_id
            || existing.project_id != project.id
            || existing.host_id != LOCAL_HOST_ID
            || !crate::windows_path_form::same_path(&existing.path, &workspace.path)
            || existing.kind != workspace.kind
            || existing.status != WorkspaceStatus::Active
        {
            bail!(
                "Remote task identity already belongs to another workspace; no state was replaced"
            );
        }
        let owner = store
            .find_project(&project.id)
            .await?
            .ok_or_else(|| anyhow!("Remote task project is unavailable"))?;
        if !crate::windows_path_form::same_path(&owner.repo_path, &project.repo_path)
            || owner.kind != project.kind
        {
            bail!("Remote task repository ownership changed");
        }
        if workspace.kind == WorkspaceKind::Linked
            && store
                .find_workspace_checkout(&workspace.id)
                .await?
                .and_then(|checkout| checkout.repository_path)
                .as_deref()
                != Some(owner_repository.as_str())
        {
            bail!("Remote linked task repository origin changed; no state was replaced");
        }
        return Ok(existing);
    }
    store
        .register_owner_project_checkout(project.clone())
        .await?;
    match workspace.kind {
        WorkspaceKind::Main => store.insert_workspace(workspace).await,
        WorkspaceKind::Linked => {
            store
                .insert_workspace_with_repository(workspace, &owner_repository)
                .await
        }
    }
}

#[cfg(test)]
#[path = "remote_workspace_owner_tests.rs"]
mod tests;
