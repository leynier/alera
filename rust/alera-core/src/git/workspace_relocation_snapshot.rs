use git2::{DiffOptions, ErrorCode, Index, Oid, Repository, Signature, StashFlags};

use super::{open_repo, GitError, GitErrorKind};

/// The persisted relocation ID names both the stash entry and a protected Git
/// ref. A crash after stash-save but before journal update can recover by name.
pub fn stash_for_workspace_relocation(
    path: &str,
    relocation_id: &str,
) -> Result<Option<String>, GitError> {
    let id = operation_id(relocation_id)?;
    super::validate_handoff_state(path)?;
    let mut repo = open_repo(path)?;
    if let Some(oid) = find_snapshot(&mut repo, &id)? {
        if !super::is_worktree_clean(path)? {
            return Err(GitError::new(GitErrorKind::Conflict, format!("Relocation snapshot {oid} was retained, but its source has local changes. Resolve or restore that snapshot before retrying; no additional files were changed.")));
        }
        retain_snapshot(&repo, &id, oid)?;
        return Ok(Some(oid.to_string()));
    }
    let signature = Signature::now("Alera", "alera@example.com").map_err(GitError::from_git2)?;
    match repo.stash_save(
        &signature,
        &snapshot_label(&id),
        Some(StashFlags::INCLUDE_UNTRACKED),
    ) {
        Ok(oid) => {
            retain_snapshot(&repo, &id, oid)?;
            Ok(Some(oid.to_string()))
        }
        Err(error) if error.code() == ErrorCode::NotFound => Ok(None),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

pub fn find_workspace_relocation_snapshot(
    path: &str,
    relocation_id: &str,
) -> Result<Option<String>, GitError> {
    let id = operation_id(relocation_id)?;
    let mut repo = open_repo(path)?;
    Ok(find_snapshot(&mut repo, &id)?.map(|oid| oid.to_string()))
}

/// Detect an apply that completed before its journal phase was persisted. Both
/// the staging boundary and every transferred file must match before resuming.
pub fn workspace_matches_relocation_snapshot(path: &str, oid: &str) -> Result<bool, GitError> {
    let repo = open_repo(path)?;
    let oid = Oid::from_str(oid).map_err(GitError::from_git2)?;
    verify_stash_commit(&repo, oid)?;
    let snapshot = repo.find_commit(oid).map_err(GitError::from_git2)?;
    let head = repo
        .head()
        .and_then(|head| head.peel_to_commit())
        .map_err(GitError::from_git2)?;
    if head.id() != snapshot.parent_id(0).map_err(GitError::from_git2)? {
        return Ok(false);
    }
    let mut actual_index = repo.index().map_err(GitError::from_git2)?;
    if actual_index.has_conflicts() {
        return Ok(false);
    }
    let staged = snapshot.parent(1).map_err(GitError::from_git2)?;
    if actual_index
        .write_tree_to(&repo)
        .map_err(GitError::from_git2)?
        != staged.tree_id()
    {
        return Ok(false);
    }
    let mut expected = Index::new().map_err(GitError::from_git2)?;
    expected
        .read_tree(&snapshot.tree().map_err(GitError::from_git2)?)
        .map_err(GitError::from_git2)?;
    if snapshot.parent_count() == 3 {
        let untracked = snapshot
            .parent(2)
            .and_then(|commit| commit.tree())
            .map_err(GitError::from_git2)?;
        let mut untracked_index = Index::new().map_err(GitError::from_git2)?;
        untracked_index
            .read_tree(&untracked)
            .map_err(GitError::from_git2)?;
        for entry in untracked_index.iter() {
            expected.add(&entry).map_err(GitError::from_git2)?;
        }
    }
    let mut options = DiffOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_typechange(true);
    let diff = repo
        .diff_index_to_workdir(Some(&expected), Some(&mut options))
        .map_err(GitError::from_git2)?;
    Ok(diff.deltas().len() == 0)
}

pub fn apply_workspace_relocation_snapshot(path: &str, oid: &str) -> Result<(), GitError> {
    if workspace_matches_relocation_snapshot(path, oid)? {
        return Ok(());
    }
    if !super::is_worktree_clean(path)? {
        return Err(GitError::new(GitErrorKind::Conflict, format!("The destination differs from relocation snapshot {oid}. Its files and the recovery snapshot were preserved; resolve the destination before retrying.")));
    }
    let repo = open_repo(path)?;
    let snapshot = repo
        .find_commit(Oid::from_str(oid).map_err(GitError::from_git2)?)
        .map_err(GitError::from_git2)?;
    let head = repo
        .head()
        .and_then(|head| head.peel_to_commit())
        .map_err(GitError::from_git2)?;
    if head.id() != snapshot.parent_id(0).map_err(GitError::from_git2)? {
        return Err(GitError::new(GitErrorKind::Conflict, "The destination commit changed after relocation preparation; restore the expected commit before retrying."));
    }
    super::apply_handoff_stash(path, oid)?;
    if !workspace_matches_relocation_snapshot(path, oid)? {
        return Err(GitError::new(GitErrorKind::Conflict, format!("Relocation snapshot {oid} could not be verified after application. Recovery data and destination files were retained.")));
    }
    Ok(())
}

fn find_snapshot(repo: &mut Repository, id: &str) -> Result<Option<Oid>, GitError> {
    match repo.find_reference(&snapshot_reference(id)) {
        Ok(reference) => {
            let oid = reference.target().ok_or_else(|| {
                GitError::new(
                    GitErrorKind::Conflict,
                    "Relocation recovery reference is not an immutable commit",
                )
            })?;
            verify_stash_commit(repo, oid)?;
            return Ok(Some(oid));
        }
        Err(error) if error.code() == ErrorCode::NotFound => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }
    let label = snapshot_label(id);
    let mut found = Vec::new();
    repo.stash_foreach(|_, message, oid| {
        if message.ends_with(&label) {
            found.push(*oid);
        }
        true
    })
    .map_err(GitError::from_git2)?;
    if found.len() > 1 {
        return Err(GitError::new(GitErrorKind::Conflict, "Multiple snapshots match this relocation. Recovery entries were retained; choose the verified snapshot before continuing."));
    }
    if let Some(oid) = found.first() {
        verify_stash_commit(repo, *oid)?;
    }
    Ok(found.first().copied())
}

fn verify_stash_commit(repo: &Repository, oid: Oid) -> Result<(), GitError> {
    let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
    if !(2..=3).contains(&commit.parent_count()) {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "Relocation recovery reference is not a stash commit",
        ));
    }
    Ok(())
}

fn retain_snapshot(repo: &Repository, id: &str, oid: Oid) -> Result<(), GitError> {
    let reference = snapshot_reference(id);
    if let Ok(existing) = repo.find_reference(&reference) {
        if existing.target() == Some(oid) {
            return Ok(());
        }
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "Relocation recovery reference changed; no reference was overwritten",
        ));
    }
    repo.reference(
        &reference,
        oid,
        false,
        "retain workspace relocation recovery",
    )
    .map_err(GitError::from_git2)?;
    Ok(())
}

fn operation_id(value: &str) -> Result<String, GitError> {
    uuid::Uuid::parse_str(value)
        .map(|id| id.to_string())
        .map_err(|_| {
            GitError::new(
                GitErrorKind::Conflict,
                "A valid relocation ID is required before snapshotting work",
            )
        })
}

fn snapshot_reference(id: &str) -> String {
    format!("refs/alera/workspace-relocations/{id}")
}

fn snapshot_label(id: &str) -> String {
    format!("alera workspace relocation {id}")
}
