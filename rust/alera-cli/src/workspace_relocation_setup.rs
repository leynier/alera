use std::collections::HashSet;
use std::path::Path;

use alera_core::runtime::{Project, RuntimeStore, WorktreeSetupReport};
use anyhow::{anyhow, bail, Result};

pub(crate) async fn prepare(
    store: &RuntimeStore,
    project: &Project,
    relocation_id: &str,
) -> Result<()> {
    if store.find_relocation_setup(relocation_id).await?.is_some() {
        return Ok(());
    }
    let config = crate::worktree_setup::effective_project_config(store, project).await?;
    prepare_with_config(store, project, relocation_id, config).await
}

pub(crate) async fn prepare_with_config(
    store: &RuntimeStore,
    project: &Project,
    relocation_id: &str,
    mut config: alera_core::runtime::ProjectConfig,
) -> Result<()> {
    if store.find_relocation_setup(relocation_id).await?.is_some() {
        return Ok(());
    }
    let root = project.repo_path.clone();
    let included = tokio::task::spawn_blocking(move || {
        crate::worktree_include::expand_worktree_include(Path::new(&root))
    })
    .await??;
    let explicit = config
        .worktree
        .copy
        .iter()
        .map(|rule| rule.from.clone())
        .collect::<HashSet<_>>();
    config.worktree.copy.extend(
        included
            .into_iter()
            .filter(|rule| !explicit.contains(&rule.from)),
    );
    store
        .prepare_relocation_setup(relocation_id, &config)
        .await?;
    Ok(())
}

pub(crate) async fn run(
    store: &RuntimeStore,
    workspace_id: &str,
    relocation_id: &str,
) -> Result<WorktreeSetupReport> {
    let journal = store
        .find_workspace_relocation(relocation_id)
        .await?
        .ok_or_else(|| anyhow!("Relocation not found"))?;
    if journal.destination.id != workspace_id {
        bail!("Setup receipt belongs to a different task");
    }
    let receipt = store
        .find_relocation_setup(relocation_id)
        .await?
        .ok_or_else(|| anyhow!("Relocation setup recipe was not prepared"))?;
    if let Some(report) = receipt.report {
        return Ok(report);
    }
    let claimed = store.claim_relocation_setup(&receipt).await?;
    let mut project = store
        .find_project(&journal.destination.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project no longer exists"))?;
    project.repo_path = journal.repository_path;
    let report = crate::worktree_setup::run_setup_config(
        store,
        &project,
        &journal.destination,
        &claimed.config,
        false,
        Some(&claimed),
    )
    .await;
    store.finish_relocation_setup(&claimed, &report).await
}

pub(crate) async fn defer(
    store: &RuntimeStore,
    workspace: &alera_core::runtime::Workspace,
    relocation_id: &str,
    directory: Option<&Path>,
) -> Result<(WorktreeSetupReport, Option<String>)> {
    let receipt = store
        .find_relocation_setup(relocation_id)
        .await?
        .ok_or_else(|| anyhow!("Setup recipe was not prepared"))?;
    if receipt.report.is_some()
        || directory.is_none()
        || (receipt.config.worktree.copy.is_empty() && receipt.config.worktree.setup.is_empty())
    {
        return Ok((run(store, &workspace.id, relocation_id).await?, None));
    }
    prepare_launcher(
        store,
        workspace,
        relocation_id,
        directory.expect("checked above"),
    )
    .await
}

pub(crate) async fn prepare_launcher(
    store: &RuntimeStore,
    workspace: &alera_core::runtime::Workspace,
    relocation_id: &str,
    directory: &Path,
) -> Result<(WorktreeSetupReport, Option<String>)> {
    let latest = store
        .list_workspace_relocation_recovery(&workspace.id, 1)
        .await?
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("Relocation not found"))?;
    let destination = &latest.relocation.destination;
    if latest.relocation.id != relocation_id
        || latest.relocation.phase != alera_core::runtime::WorkspaceRelocationPhase::Completed
        || destination.instance_id != workspace.instance_id
        || destination.host_id != workspace.host_id
        || destination.path != workspace.path
    {
        bail!("Task location no longer matches this completed relocation; inspect workspace recovery before preparing setup");
    }
    let receipt = latest
        .setup
        .ok_or_else(|| anyhow!("Setup recipe was not prepared"))?;
    if let Some(report) = receipt.report {
        return Ok((report, None));
    }
    if receipt.attempt_id.is_some() {
        bail!("Setup has an unconfirmed attempt; inspect workspace recovery instead of launching its commands again");
    }
    if receipt.config.worktree.copy.is_empty() && receipt.config.worktree.setup.is_empty() {
        return Ok((WorktreeSetupReport::empty(), None));
    }
    let script = crate::worktree_setup_script::write_relocation_setup_script(
        directory,
        &std::env::current_exe()?,
        &workspace.id,
        &workspace.path,
        relocation_id,
    )?;
    Ok((WorktreeSetupReport::empty(), Some(script.command)))
}
