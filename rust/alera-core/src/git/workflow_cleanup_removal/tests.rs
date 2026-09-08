use super::*;
use crate::git::ensure_workflow_worktree;

fn fixture() -> (tempfile::TempDir, String, WorkflowCleanupRemoval) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("repo");
    let repo = Repository::init(&path).unwrap();
    std::fs::write(path.join("tracked"), "retained content").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = git2::Signature::now("Test", "test@example.invalid").unwrap();
    let base = repo
        .commit(Some("HEAD"), &signature, &signature, "fixture", &tree, &[])
        .unwrap()
        .to_string();
    let request = WorkflowCleanupRemoval {
        cleanup_id: uuid::Uuid::new_v4().to_string(),
        resource_id: uuid::Uuid::new_v4().to_string(),
        path: dir.path().join("owned").to_str().unwrap().into(),
        base_sha: base.clone(),
        expected_head: base,
        remove_branch: false,
    };
    let path = path.to_str().unwrap().to_owned();
    ensure_workflow_worktree(
        &path,
        &request.path,
        &request.base_sha,
        &request.resource_id,
    )
    .unwrap();
    (dir, path, request)
}

#[test]
fn cleanup_removal_preserves_branch_and_replay_does_not_touch_reoccupied_path() {
    let (_dir, path, request) = fixture();
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    let repo = open_repo(&path).unwrap();
    assert!(!Path::new(&request.path).exists());
    assert!(repo.find_worktree(&request.resource_id).is_err());
    assert!(repo
        .find_reference(&format!(
            "refs/heads/alera/workflows/{}",
            request.resource_id
        ))
        .is_ok());
    std::fs::create_dir(&request.path).unwrap();
    let new_file = Path::new(&request.path).join("unrelated");
    std::fs::write(&new_file, "preserve").unwrap();
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    assert_eq!(std::fs::read_to_string(new_file).unwrap(), "preserve");
    let mut changed = request.clone();
    changed.remove_branch = true;
    assert!(remove_workflow_cleanup_resource(&path, &changed).is_err());
}

#[test]
fn cleanup_removal_deletes_only_explicit_branch_and_retains_reviewed_commit() {
    let (_dir, path, mut request) = fixture();
    request.remove_branch = true;
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    let repo = open_repo(&path).unwrap();
    assert!(repo
        .find_reference(&format!(
            "refs/heads/alera/workflows/{}",
            request.resource_id
        ))
        .is_err());
    let receipt = repo
        .find_reference(&format!(
            "refs/alera/workflow-cleanup/{}/{}",
            request.cleanup_id, request.resource_id
        ))
        .unwrap()
        .peel_to_commit()
        .unwrap();
    assert_eq!(
        receipt.parent_id(0).unwrap().to_string(),
        request.expected_head
    );
}

#[test]
fn cleanup_removal_rejects_dirty_locked_and_stale_resources_without_deletion() {
    let (_dir, path, request) = fixture();
    let untracked = Path::new(&request.path).join("untracked");
    std::fs::write(&untracked, "keep").unwrap();
    assert!(remove_workflow_cleanup_resource(&path, &request).is_err());
    assert!(untracked.exists());
    std::fs::remove_file(untracked).unwrap();
    let repo = open_repo(&path).unwrap();
    let worktree = repo.find_worktree(&request.resource_id).unwrap();
    worktree.lock(Some("busy")).unwrap();
    assert!(remove_workflow_cleanup_resource(&path, &request).is_err());
    worktree.unlock().unwrap();
    let mut stale = request.clone();
    stale.expected_head = "0".repeat(40);
    assert!(remove_workflow_cleanup_resource(&path, &stale).is_err());
    assert!(Path::new(&request.path).join("tracked").exists());
}

#[test]
fn cleanup_removal_recovers_after_git_prune_before_runtime_persistence() {
    let (_dir, path, request) = fixture();
    let repo = open_repo(&path).unwrap();
    let name = format!(
        "refs/alera/workflow-cleanup/{}/{}",
        request.cleanup_id, request.resource_id
    );
    persist_receipt(&repo, &name, &request).unwrap();
    crate::git::remove_worktree(&path, &request.path, false).unwrap();
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    assert!(verify_receipt(&repo, &format!("{name}-retired"), &request).unwrap());
}

#[test]
fn cleanup_removal_recovers_after_branch_deletion_but_refuses_unreceipted_absence() {
    let (_dir, path, mut request) = fixture();
    request.remove_branch = true;
    let repo = open_repo(&path).unwrap();
    let name = format!(
        "refs/alera/workflow-cleanup/{}/{}",
        request.cleanup_id, request.resource_id
    );
    persist_receipt(&repo, &name, &request).unwrap();
    crate::git::remove_worktree(&path, &request.path, false).unwrap();
    repo.find_reference(&format!(
        "refs/heads/alera/workflows/{}",
        request.resource_id
    ))
    .unwrap()
    .delete()
    .unwrap();
    remove_workflow_cleanup_resource(&path, &request).unwrap();
    assert!(verify_receipt(&repo, &format!("{name}-retired"), &request).unwrap());
    request.cleanup_id = uuid::Uuid::new_v4().to_string();
    assert!(remove_workflow_cleanup_resource(&path, &request).is_err());
}

#[test]
fn cleanup_removal_recovery_preserves_a_branch_checked_out_elsewhere() {
    let (dir, path, mut request) = fixture();
    request.remove_branch = true;
    let repo = open_repo(&path).unwrap();
    let name = format!(
        "refs/alera/workflow-cleanup/{}/{}",
        request.cleanup_id, request.resource_id
    );
    persist_receipt(&repo, &name, &request).unwrap();
    crate::git::remove_worktree(&path, &request.path, false).unwrap();
    let branch = repo
        .find_reference(&format!(
            "refs/heads/alera/workflows/{}",
            request.resource_id
        ))
        .unwrap();
    let mut options = git2::WorktreeAddOptions::new();
    options.reference(Some(&branch));
    repo.worktree("other", &dir.path().join("other"), Some(&options))
        .unwrap();
    assert!(remove_workflow_cleanup_resource(&path, &request)
        .unwrap_err()
        .to_string()
        .contains("checked out elsewhere"));
    assert!(repo.find_reference(branch.name().unwrap()).is_ok());
    assert!(dir.path().join("other/tracked").exists());
}

#[test]
fn cleanup_removal_receipt_cannot_authorize_another_repository_location() {
    let (dir, path, mut request) = fixture();
    request.remove_branch = true;
    {
        let repo = open_repo(&path).unwrap();
        let name = format!(
            "refs/alera/workflow-cleanup/{}/{}",
            request.cleanup_id, request.resource_id
        );
        persist_receipt(&repo, &name, &request).unwrap();
    }
    crate::git::remove_worktree(&path, &request.path, false).unwrap();
    let moved = dir.path().join("moved");
    std::fs::rename(&path, &moved).unwrap();
    assert!(remove_workflow_cleanup_resource(moved.to_str().unwrap(), &request).is_err());
    let repo = open_repo(moved.to_str().unwrap()).unwrap();
    assert!(repo
        .find_reference(&format!(
            "refs/heads/alera/workflows/{}",
            request.resource_id
        ))
        .is_ok());
}
