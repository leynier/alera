use anyhow::{anyhow, bail, Context, Result};
use serde::Serialize;

#[derive(Debug, clap::Args)]
pub(crate) struct CreateCheckoutWorktreeArgs {
    #[arg(long)]
    pub repository: String,
    #[arg(long)]
    pub path: String,
    #[arg(long)]
    pub branch: String,
    #[arg(long)]
    pub source: String,
    #[arg(long)]
    pub reuse_existing_branch: bool,
}

#[derive(Debug, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CreatedCheckoutWorktree {
    pub version: u32,
    pub repository_path: String,
    pub path: String,
    pub branch: String,
}

pub(crate) async fn create(args: CreateCheckoutWorktreeArgs) -> Result<CreatedCheckoutWorktree> {
    let inspection = crate::project_checkout_inspection::inspect(
        args.repository.clone(),
        alera_core::runtime::ProjectKind::GitRepository,
    )
    .await?;
    if inspection.path != args.repository {
        bail!("The registered repository resolves to a different directory");
    }
    tokio::task::spawn_blocking(move || {
        let path = std::path::Path::new(&args.path);
        if !path.is_absolute() || path.file_name().is_none() {
            bail!("An absolute new worktree path is required");
        }
        match std::fs::symlink_metadata(path) {
            Ok(_) => bail!("The worktree destination already exists; no files were changed"),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("Cannot inspect worktree destination"),
        }
        if !alera_core::git::is_valid_branch_name(&args.branch)? {
            bail!("Invalid worktree branch name");
        }
        if args.reuse_existing_branch
            && alera_core::git::branch_checkout_path(&args.repository, &args.branch)?.is_some()
        {
            bail!("The requested branch is already checked out on this host");
        }
        let parent = path
            .parent()
            .ok_or_else(|| anyhow!("Worktree parent is required"))?;
        std::fs::create_dir_all(parent)?;
        alera_core::git::create_worktree(
            &args.repository,
            &args.branch,
            &args.path,
            &args.source,
            args.reuse_existing_branch,
        )?;
        let path = std::fs::canonicalize(path)?
            .to_str()
            .ok_or_else(|| anyhow!("Worktree path is not valid UTF-8"))?
            .to_string();
        Ok(CreatedCheckoutWorktree {
            version: 1,
            repository_path: args.repository,
            path,
            branch: args.branch,
        })
    })
    .await?
}

#[cfg(test)]
#[path = "project_checkout_worktree_tests.rs"]
mod tests;
