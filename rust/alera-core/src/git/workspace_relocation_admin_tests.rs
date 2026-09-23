use super::{init_repo, path_str, workdir};
use crate::git::{create_workspace_relocation_worktree, is_workspace_relocation_worktree};

#[test]
fn compact_registration_keeps_the_full_identity_and_retries_in_place() {
    let (directory, repo) = init_repo();
    let id = uuid::Uuid::new_v4();
    let destination = directory.path().join("compact-task");
    let commit = repo.head().unwrap().target().unwrap().to_string();
    for _ in 0..2 {
        create_workspace_relocation_worktree(
            path_str(workdir(&repo)),
            &id.to_string(),
            path_str(&destination),
            "compact-task",
            &commit,
            false,
        )
        .unwrap();
        assert!(is_workspace_relocation_worktree(
            path_str(workdir(&repo)),
            path_str(&destination),
            &id.to_string()
        )
        .unwrap());
    }
    assert_eq!(
        repo.worktrees().unwrap().get(0).unwrap(),
        Some(format!("alera-{}", id.simple()).as_str())
    );
    assert_eq!(repo.worktrees().unwrap().len(), 1);
}

#[test]
fn legacy_registration_is_reused_without_replacing_its_files() {
    let (directory, repo) = init_repo();
    let id = uuid::Uuid::new_v4();
    let destination = directory.path().join("legacy-task");
    let commit = repo.head().unwrap().peel_to_commit().unwrap();
    let branch = repo.branch("legacy-task", &commit, false).unwrap();
    let mut options = git2::WorktreeAddOptions::new();
    options.reference(Some(branch.get()));
    let name = format!("alera-relocation-{id}");
    repo.worktree(&name, &destination, Some(&options)).unwrap();
    create_workspace_relocation_worktree(
        path_str(workdir(&repo)),
        &id.to_string(),
        path_str(&destination),
        "legacy-task",
        &commit.id().to_string(),
        false,
    )
    .unwrap();
    assert!(is_workspace_relocation_worktree(
        path_str(workdir(&repo)),
        path_str(&destination),
        &id.to_string()
    )
    .unwrap());
    assert_eq!(
        repo.worktrees().unwrap().get(0).unwrap(),
        Some(name.as_str())
    );
    assert_eq!(repo.worktrees().unwrap().len(), 1);
}

#[cfg(windows)]
#[test]
fn oversized_registration_is_rejected_before_branch_or_folder_creation() {
    let (directory, seed) = init_repo();
    let padding = 160usize.saturating_sub(directory.path().to_string_lossy().len() + 1);
    let root = directory.path().join("r".repeat(padding));
    let repo = git2::Repository::clone(path_str(workdir(&seed)), &root).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let destination = directory.path().join("rejected");
    let commit = repo.head().unwrap().target().unwrap().to_string();
    let error = create_workspace_relocation_worktree(
        path_str(&root),
        &id,
        path_str(&destination),
        "rejected",
        &commit,
        false,
    )
    .unwrap_err();
    assert!(error.to_string().contains("insufficient space"));
    assert!(repo
        .find_branch("rejected", git2::BranchType::Local)
        .is_err());
    assert!(!destination.exists());
    assert_eq!(repo.worktrees().unwrap().len(), 0);
}
