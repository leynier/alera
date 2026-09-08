use super::*;
use crate::git::ensure_workflow_worktree;

struct Fixture {
    _dir: tempfile::TempDir,
    repo: String,
    path: String,
    base: String,
    id: String,
}
impl Fixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let repo_path = dir.path().join("repo");
        let repo = git2::Repository::init(&repo_path).unwrap();
        std::fs::write(repo_path.join("tracked.txt"), "original\n").unwrap();
        std::fs::write(repo_path.join(".gitignore"), "ignored.txt\n").unwrap();
        let mut index = repo.index().unwrap();
        index.add_path(std::path::Path::new("tracked.txt")).unwrap();
        index.add_path(std::path::Path::new(".gitignore")).unwrap();
        index.write().unwrap();
        let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
        let signature = git2::Signature::now("Cleanup Test", "cleanup@example.invalid").unwrap();
        let base = repo
            .commit(Some("HEAD"), &signature, &signature, "fixture", &tree, &[])
            .unwrap()
            .to_string();
        let path = dir.path().join("owned").to_str().unwrap().to_owned();
        let id = uuid::Uuid::new_v4().to_string();
        let repo = repo_path.to_str().unwrap().to_owned();
        ensure_workflow_worktree(&repo, &path, &base, &id).unwrap();
        Self {
            _dir: dir,
            repo,
            path,
            base,
            id,
        }
    }
    fn preview(&self) -> WorkflowCleanupGitPreview {
        preview_workflow_cleanup(&self.repo, &self.path, &self.base, &self.id).unwrap()
    }
}

#[test]
fn cleanup_preview_is_read_only_and_retains_worktree_and_branch() {
    let fixture = Fixture::new();
    let repo = open_repo(&fixture.repo).unwrap();
    let receipt = format!("refs/alera/workflow-resources/{}", fixture.id);
    repo.find_reference(&receipt).unwrap().delete().unwrap();
    let checkout = open_repo(&fixture.path).unwrap();
    let index = std::fs::read(checkout.path().join("index")).unwrap();
    let preview = fixture.preview();
    assert_eq!(preview.head_sha, fixture.base);
    assert!(!preview.dirty && !preview.locked && !preview.operation_in_progress);
    assert!(repo.find_reference(&receipt).is_err());
    assert_eq!(std::fs::read(checkout.path().join("index")).unwrap(), index);
    assert!(repo.find_worktree(&fixture.id).is_ok());
    assert!(std::path::Path::new(&fixture.path)
        .join("tracked.txt")
        .exists());
}

#[test]
fn cleanup_preview_reports_tracked_untracked_and_ignored_changes_and_locks() {
    let fixture = Fixture::new();
    for (file, value) in [
        ("tracked.txt", "changed"),
        ("untracked.txt", "new"),
        ("ignored.txt", "retained"),
    ] {
        std::fs::write(std::path::Path::new(&fixture.path).join(file), value).unwrap();
    }
    let preview = fixture.preview();
    assert!(preview.dirty);
    assert_eq!(
        preview.changed_paths,
        ["ignored.txt", "tracked.txt", "untracked.txt"]
    );
    open_repo(&fixture.repo)
        .unwrap()
        .find_worktree(&fixture.id)
        .unwrap()
        .lock(Some("retained"))
        .unwrap();
    assert!(fixture.preview().locked);
    assert!(
        preview_workflow_cleanup(&fixture.repo, &fixture.repo, &fixture.base, &fixture.id).is_err()
    );
}
