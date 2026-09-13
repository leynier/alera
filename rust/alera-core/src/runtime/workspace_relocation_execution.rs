use anyhow::{anyhow, bail, Result};

use super::{
    RuntimeStore, Workspace, WorkspaceKind, WorkspaceRelocation, WorkspaceRelocationPhase as Phase,
    LOCAL_HOST_ID,
};
use crate::git;

impl RuntimeStore {
    /// The caller must hold the runtime mutation barrier and a verified buffer
    /// guard, and reject source processes that cannot be relocated reliably.
    pub async fn resume_local_workspace_relocation(
        &self,
        id: &str,
        verify_safety: impl Fn() -> Result<()>,
    ) -> Result<Workspace> {
        loop {
            verify_safety()?;
            let journal = self
                .find_workspace_relocation(id)
                .await?
                .ok_or_else(|| anyhow!("Relocation not found: {id}"))?;
            if journal.source.host_id != LOCAL_HOST_ID
                || journal.destination.host_id != LOCAL_HOST_ID
            {
                bail!("Run relocation on its owning host");
            }
            let next = match journal.phase {
                Phase::Prepared => {
                    git_step(&journal, validate_prepared).await?;
                    Phase::Snapshotting
                }
                Phase::Snapshotting => {
                    let snapshot = git_step(&journal, |journal| {
                        require_checkout(
                            &journal.source.path,
                            &journal.original_branch,
                            &journal.source_commit,
                        )?;
                        if journal.move_changes {
                            Ok(git::stash_for_workspace_relocation(
                                &journal.source.path,
                                &journal.id,
                            )?)
                        } else {
                            Ok(None)
                        }
                    })
                    .await?;
                    self.advance_workspace_relocation(&journal, Phase::Snapshotted, snapshot)
                        .await?;
                    continue;
                }
                Phase::Snapshotted => Phase::PreparingDestination,
                Phase::PreparingDestination => {
                    git_step(&journal, prepare_destination).await?;
                    Phase::DestinationReady
                }
                Phase::DestinationReady => Phase::ApplyingChanges,
                Phase::ApplyingChanges => {
                    git_step(&journal, |journal| {
                        require_destination(journal)?;
                        if let Some(oid) = &journal.recovery_stash_oid {
                            git::apply_workspace_relocation_snapshot(&journal.destination.path, oid)?;
                        } else if !git::is_worktree_clean(&journal.destination.path)? {
                            bail!("Destination acquired local changes during relocation; files were retained");
                        }
                        Ok(())
                    }).await?;
                    Phase::ChangesApplied
                }
                Phase::ChangesApplied => {
                    git_step(&journal, verify_transferred).await?;
                    verify_safety()?;
                    self.commit_workspace_relocation(&journal).await?;
                    continue;
                }
                Phase::Committed if journal.source.kind == WorkspaceKind::Linked => {
                    Phase::RemovingSource
                }
                Phase::Committed => Phase::Completed,
                Phase::RemovingSource => {
                    git_step(&journal, |journal| {
                        verify_transferred(journal)?;
                        match std::fs::symlink_metadata(&journal.source.path) {
                            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                                match git::remove_worktree(
                                    &journal.repository_path,
                                    &journal.source.path,
                                    false,
                                ) {
                                    Ok(()) => return Ok(()),
                                    Err(error)
                                        if error.kind == git::GitErrorKind::WorktreeNotFound =>
                                    {
                                        return Ok(())
                                    }
                                    Err(error) => return Err(error.into()),
                                }
                            }
                            Err(error) => return Err(error.into()),
                            Ok(_) => {}
                        }
                        require_checkout(&journal.source.path, "HEAD", &journal.source_commit)?;
                        if !git::checkouts_share_repository(
                            &journal.repository_path,
                            &journal.source.path,
                        )? {
                            bail!("Source worktree ownership changed; no directory was removed");
                        }
                        git::validate_handoff_removal(&journal.source.path)?;
                        git::remove_worktree(
                            &journal.repository_path,
                            &journal.source.path,
                            false,
                        )?;
                        Ok(())
                    })
                    .await?;
                    Phase::Completed
                }
                Phase::Completed => {
                    return self
                        .find_workspace(&journal.source.id)
                        .await?
                        .ok_or_else(|| anyhow!("Relocated workspace no longer exists"))
                }
            };
            verify_safety()?;
            self.advance_workspace_relocation(&journal, next, journal.recovery_stash_oid.clone())
                .await?;
        }
    }
}

async fn git_step<T: Send + 'static>(
    journal: &WorkspaceRelocation,
    work: impl FnOnce(&WorkspaceRelocation) -> Result<T> + Send + 'static,
) -> Result<T> {
    let owned = journal.clone();
    tokio::task::spawn_blocking(move || work(&owned)).await?
        .map_err(|error| {
            let message = format!("Relocation {} is retained at {:?}; resume it after resolving this condition: {error:#}", journal.id, journal.phase);
            error.context(message)
        })
}

pub(super) fn validate_prepared(journal: &WorkspaceRelocation) -> Result<()> {
    require_checkout(
        &journal.source.path,
        &journal.original_branch,
        &journal.source_commit,
    )?;
    git::validate_handoff_state(&journal.source.path)?;
    if journal.original_branch == "HEAD" {
        bail!("Create or check out a branch before relocating this workspace");
    }
    if journal.destination.kind == WorkspaceKind::Main {
        git::validate_no_ignored_handoff_files(&journal.source.path)?;
        require_original_destination(journal)?;
        if !git::is_worktree_clean(&journal.destination.path)? {
            bail!("The project checkout has local changes; resolve them before handing on");
        }
        if destination_branch(journal)? != journal.original_branch {
            bail!("Hand On must bring the source branch onto the project checkout");
        }
    } else {
        match std::fs::symlink_metadata(&journal.destination.path) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
            Ok(_) => bail!("The relocation destination already exists; choose a new location"),
        }
        let branch = destination_branch(journal)?;
        if !git::is_valid_branch_name(branch)? {
            bail!("Invalid destination branch");
        }
        if let Some(replacement) = &journal.replacement_branch {
            if branch != journal.original_branch || replacement == branch {
                bail!("Moving the current branch requires a different explicit replacement branch");
            }
            validate_replacement(journal)?;
        } else if branch == journal.original_branch
            || git::branch_exists(&journal.repository_path, branch)?
        {
            bail!(
                "Choose a new branch, or explicitly prepare a replacement for the current branch"
            );
        }
    }
    if !journal.move_changes
        && (journal.destination.kind == WorkspaceKind::Main || journal.replacement_branch.is_some())
    {
        bail!("This relocation requires transferring all uncommitted changes");
    }
    if !git::checkouts_share_repository(&journal.repository_path, &journal.source.path)? {
        bail!("Source checkout no longer belongs to the prepared repository");
    }
    Ok(())
}

fn prepare_destination(journal: &WorkspaceRelocation) -> Result<()> {
    if journal.destination.kind == WorkspaceKind::Linked {
        if let Some(replacement) = &journal.replacement_branch {
            let replacement_commit = journal
                .replacement_commit
                .as_deref()
                .ok_or_else(|| anyhow!("Replacement commit was not recorded"))?;
            let live = git::current_branch(&journal.source.path)?;
            if live == journal.original_branch {
                require_checkout(
                    &journal.source.path,
                    &journal.original_branch,
                    &journal.source_commit,
                )?;
                if !git::is_worktree_clean(&journal.source.path)? {
                    bail!("Source acquired local changes after snapshotting; preserve them before retrying");
                }
                validate_replacement(journal)?;
                git::checkout_branch(&journal.source.path, replacement)?;
            }
            require_checkout(&journal.source.path, replacement, replacement_commit)?;
            if !git::is_worktree_clean(&journal.source.path)? {
                bail!("Replacement checkout acquired local changes; preserve them before retrying");
            }
        } else {
            require_checkout(
                &journal.source.path,
                &journal.original_branch,
                &journal.source_commit,
            )?;
            if journal.move_changes && !git::is_worktree_clean(&journal.source.path)? {
                bail!("Source acquired local changes after snapshotting; preserve them before retrying");
            }
        }
        git::create_workspace_relocation_worktree(
            &journal.repository_path,
            &journal.id,
            &journal.destination.path,
            destination_branch(journal)?,
            &journal.source_commit,
            journal.replacement_branch.is_some(),
        )?;
    } else {
        let source_branch = git::current_branch(&journal.source.path)?;
        if source_branch != journal.original_branch && source_branch != "HEAD" {
            bail!("Source branch changed after preparation");
        }
        require_checkout(&journal.source.path, &source_branch, &journal.source_commit)?;
        git::validate_handoff_removal(&journal.source.path)?;
        if !git::is_worktree_clean(&journal.destination.path)? {
            bail!("The project checkout acquired local changes; they were preserved");
        }
        let already_switched = git::current_branch(&journal.destination.path)?
            == destination_branch(journal)?
            && git::checkout_commit(&journal.destination.path)? == journal.source_commit;
        if !already_switched {
            require_original_destination(journal)?;
        }
        if source_branch != "HEAD" {
            git::detach_head(&journal.source.path)?;
        }
        if !already_switched {
            git::checkout_branch(&journal.destination.path, destination_branch(journal)?)?;
        }
    }
    require_destination(journal)
}

fn validate_replacement(journal: &WorkspaceRelocation) -> Result<()> {
    let branch = journal
        .replacement_branch
        .as_deref()
        .ok_or_else(|| anyhow!("Replacement branch was not recorded"))?;
    let commit = journal
        .replacement_commit
        .as_deref()
        .ok_or_else(|| anyhow!("Replacement commit was not recorded"))?;
    if !git::is_valid_branch_name(branch)?
        || git::local_branch_commit(&journal.repository_path, branch)? != commit
    {
        bail!("Replacement branch changed after preparation");
    }
    if let Some(path) = git::branch_checkout_path(&journal.repository_path, branch)? {
        bail!("Replacement branch {branch} is already checked out at {path}");
    }
    Ok(())
}

fn require_checkout(path: &str, branch: &str, commit: &str) -> Result<()> {
    if git::current_branch(path)? != branch || git::checkout_commit(path)? != commit {
        bail!("Checkout at {path} no longer matches prepared branch {branch} and commit {commit}");
    }
    Ok(())
}

fn destination_branch(journal: &WorkspaceRelocation) -> Result<&str> {
    journal
        .destination
        .branch
        .as_deref()
        .ok_or_else(|| anyhow!("Destination branch was not recorded"))
}

fn require_destination(journal: &WorkspaceRelocation) -> Result<()> {
    require_checkout(
        &journal.destination.path,
        destination_branch(journal)?,
        &journal.source_commit,
    )?;
    if !git::checkouts_share_repository(&journal.repository_path, &journal.destination.path)? {
        bail!("Destination checkout no longer belongs to the prepared repository");
    }
    Ok(())
}

fn require_original_destination(journal: &WorkspaceRelocation) -> Result<()> {
    require_checkout(
        &journal.destination.path,
        journal
            .destination_original_branch
            .as_deref()
            .ok_or_else(|| anyhow!("Original destination branch was not recorded"))?,
        journal
            .destination_original_commit
            .as_deref()
            .ok_or_else(|| anyhow!("Original destination commit was not recorded"))?,
    )
}

fn verify_transferred(journal: &WorkspaceRelocation) -> Result<()> {
    require_destination(journal)?;
    if let Some(oid) = &journal.recovery_stash_oid {
        if !git::workspace_matches_relocation_snapshot(&journal.destination.path, oid)? {
            bail!(
                "Transferred files changed before relocation completed; recovery data was retained"
            );
        }
    } else if !git::is_worktree_clean(&journal.destination.path)? {
        bail!("Destination changed before relocation completed; files were retained");
    }
    Ok(())
}
