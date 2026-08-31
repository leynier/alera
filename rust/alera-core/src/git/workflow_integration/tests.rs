use std::fs;
use std::path::Path;

use git2::{build::CheckoutBuilder, Repository};
use tempfile::TempDir;
use uuid::Uuid;

use super::*;
use crate::git::{ensure_workflow_worktree, verify_workflow_worktree};

struct Fixture {
    directory: TempDir,
    repo_path: String,
    base: String,
    integration: WorkflowGitResource,
    source: WorkflowGitResource,
}

impl Fixture {
    fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let repo_path = directory.path().join("repo");
        let repo = Repository::init(&repo_path).unwrap();
        let mut config = repo.config().unwrap();
        config.set_str("user.name", "Workflow Test").unwrap();
        config
            .set_str("user.email", "workflow@example.invalid")
            .unwrap();
        let base = commit(
            &repo_path,
            &[("shared.txt", "base\n"), (".gitignore", "ignored.txt\n")],
        );
        let repo_path = repo_path.to_str().unwrap().to_owned();
        let integration = resource(&directory, &repo_path, &base);
        let source = resource(&directory, &repo_path, &base);
        Self {
            directory,
            repo_path,
            base,
            integration,
            source,
        }
    }

    fn request(&self, changes: &[(&str, &str)]) -> WorkflowIntegrationRequest {
        let source_sha = if changes.is_empty() {
            self.base.clone()
        } else {
            commit(Path::new(&self.source.path), changes)
        };
        WorkflowIntegrationRequest {
            id: Uuid::new_v4().to_string(),
            repo_path: self.repo_path.clone(),
            run_id: Uuid::new_v4().to_string(),
            revision: 1,
            task_id: Uuid::new_v4().to_string(),
            dispatch_id: Uuid::new_v4().to_string(),
            integration: self.integration.clone(),
            source: self.source.clone(),
            expected_sha: self.base.clone(),
            source_sha,
            result_digest: "a".repeat(64),
            artifacts: changes.iter().map(|(path, _)| (*path).to_owned()).collect(),
        }
    }
}

fn resource(directory: &TempDir, repo: &str, base: &str) -> WorkflowGitResource {
    let id = Uuid::new_v4().to_string();
    let path = directory.path().join(&id).to_str().unwrap().to_owned();
    ensure_workflow_worktree(repo, &path, base, &id).unwrap();
    WorkflowGitResource {
        id,
        path,
        base_sha: base.into(),
    }
}

fn commit(path: &Path, changes: &[(&str, &str)]) -> String {
    let repo = Repository::open(path).unwrap();
    let mut index = repo.index().unwrap();
    for (name, content) in changes {
        let target = path.join(name);
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::write(&target, content).unwrap();
        index.add_path(Path::new(name)).unwrap();
    }
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let parent = repo.head().ok().map(|h| h.peel_to_commit().unwrap());
    let parents = parent.iter().collect::<Vec<_>>();
    let signature = repo.signature().unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "test: change files",
        &tree,
        &parents,
    )
    .unwrap()
    .to_string()
}

fn prepared(request: &WorkflowIntegrationRequest) -> WorkflowIntegrationReceipt {
    match prepare_workflow_integration(request).unwrap() {
        WorkflowGitPreparation::Ready { receipt } => *receipt,
        other => panic!("expected preparation, got {other:?}"),
    }
}

#[test]
fn workflow_integration_squashes_exact_result_and_preserves_source_changes() {
    let fixture = Fixture::new();
    fs::write(
        Path::new(&fixture.repo_path).join("shared.txt"),
        "owner dirty\n",
    )
    .unwrap();
    let request = fixture.request(&[("result.txt", "done\n")]);
    let receipt = prepared(&request);
    let repo = Repository::open(&fixture.integration.path).unwrap();
    assert_eq!(head_oid(&repo).unwrap().to_string(), fixture.base);
    assert!(!Path::new(&fixture.integration.path)
        .join("result.txt")
        .exists());
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
    let result = repo
        .find_commit(oid(&receipt.integrated_sha).unwrap())
        .unwrap();
    assert_eq!(result.parent_count(), 1);
    assert_eq!(result.parent_id(0).unwrap().to_string(), fixture.base);
    assert_eq!(
        fs::read_to_string(Path::new(&fixture.integration.path).join("result.txt")).unwrap(),
        "done\n"
    );
    assert_eq!(
        fs::read_to_string(Path::new(&fixture.repo_path).join("shared.txt")).unwrap(),
        "owner dirty\n"
    );
    assert!(is_worktree_clean(&fixture.integration.path).unwrap());
    assert!(verify_workflow_worktree(
        &fixture.repo_path,
        &fixture.integration.path,
        &fixture.base,
        &fixture.integration.id
    )
    .is_err());
    assert_eq!(
        verify_workflow_worktree_tip(
            &fixture.repo_path,
            &fixture.integration.path,
            &fixture.base,
            &fixture.integration.id
        )
        .unwrap(),
        receipt.integrated_sha
    );
}

#[test]
fn workflow_integration_replays_before_checkout_after_checkout_and_after_ref_update() {
    let fixture = Fixture::new();
    let request = fixture.request(&[("result.txt", "done\n")]);
    let receipt = prepared(&request);
    assert_eq!(prepared(&request), receipt);
    let repo = Repository::open(&fixture.integration.path).unwrap();
    let candidate = repo
        .find_commit(oid(&receipt.integrated_sha).unwrap())
        .unwrap();
    repo.checkout_tree(candidate.as_object(), Some(CheckoutBuilder::new().safe()))
        .unwrap();
    assert_eq!(head_oid(&repo).unwrap().to_string(), fixture.base);
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
    assert_eq!(prepared(&request), receipt);
    assert_eq!(head_oid(&repo).unwrap().to_string(), receipt.integrated_sha);
}

#[test]
fn workflow_integration_no_changes_does_not_create_empty_commit() {
    let fixture = Fixture::new();
    let request = fixture.request(&[]);
    let receipt = prepared(&request);
    assert_eq!(receipt.integrated_sha, fixture.base);
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
}

#[test]
fn workflow_integration_merges_parallel_results_from_their_original_bases() {
    let fixture = Fixture::new();
    let first = fixture.request(&[("a.txt", "first\n")]);
    let first_receipt = prepared(&first);
    apply_workflow_integration(&first).unwrap();
    let source = resource(&fixture.directory, &fixture.repo_path, &fixture.base);
    let source_sha = commit(Path::new(&source.path), &[("b.txt", "second\n")]);
    let second = WorkflowIntegrationRequest {
        id: Uuid::new_v4().to_string(),
        task_id: Uuid::new_v4().to_string(),
        dispatch_id: Uuid::new_v4().to_string(),
        source,
        source_sha,
        expected_sha: first_receipt.integrated_sha,
        artifacts: vec!["b.txt".into()],
        ..first
    };
    prepared(&second);
    apply_workflow_integration(&second).unwrap();
    for (path, value) in [("a.txt", "first\n"), ("b.txt", "second\n")] {
        assert_eq!(
            fs::read_to_string(Path::new(&fixture.integration.path).join(path)).unwrap(),
            value
        );
    }
}

#[test]
fn workflow_integration_conflict_preserves_index_files_and_head() {
    let fixture = Fixture::new();
    let mut request = fixture.request(&[("shared.txt", "worker\n")]);
    request.expected_sha = commit(
        Path::new(&fixture.integration.path),
        &[("shared.txt", "other worker\n")],
    );
    let repo = Repository::open(&fixture.integration.path).unwrap();
    let index = fs::read(repo.path().join("index")).unwrap();
    assert_eq!(
        prepare_workflow_integration(&request).unwrap(),
        WorkflowGitPreparation::Conflict {
            paths: vec!["shared.txt".into()],
            truncated: false,
        }
    );
    assert_eq!(fs::read(repo.path().join("index")).unwrap(), index);
    assert_eq!(head_oid(&repo).unwrap().to_string(), request.expected_sha);
    assert_eq!(
        fs::read_to_string(Path::new(&fixture.integration.path).join("shared.txt")).unwrap(),
        "other worker\n"
    );
    assert!(receipt::load(&repo, &request).unwrap().is_none());
}

#[test]
fn workflow_integration_rejects_dirty_source_and_target_without_staging() {
    for dirty_source in [true, false] {
        let fixture = Fixture::new();
        let request = fixture.request(&[("result.txt", "done\n")]);
        let path = if dirty_source {
            &fixture.source.path
        } else {
            &fixture.integration.path
        };
        fs::write(Path::new(path).join("uncommitted.txt"), "retain").unwrap();
        assert!(prepare_workflow_integration(&request)
            .unwrap_err()
            .to_string()
            .contains("pending changes"));
        assert_eq!(
            fs::read_to_string(Path::new(path).join("uncommitted.txt")).unwrap(),
            "retain"
        );
    }
}

#[test]
fn workflow_integration_rejects_head_drift_and_changed_receipt_identity() {
    let fixture = Fixture::new();
    let request = fixture.request(&[("result.txt", "done\n")]);
    prepared(&request);
    let mut altered = request.clone();
    altered.result_digest = "b".repeat(64);
    assert!(prepare_workflow_integration(&altered)
        .unwrap_err()
        .to_string()
        .contains("identity changed"));
    let drift = commit(
        Path::new(&fixture.integration.path),
        &[("foreign.txt", "retain")],
    );
    assert!(apply_workflow_integration(&request)
        .unwrap_err()
        .to_string()
        .contains("drifted"));
    let repo = Repository::open(&fixture.integration.path).unwrap();
    assert_eq!(head_oid(&repo).unwrap().to_string(), drift);
    assert!(!Path::new(&fixture.integration.path)
        .join("result.txt")
        .exists());
}

#[test]
fn workflow_integration_rejects_missing_or_escaping_artifacts() {
    for artifact in [
        "missing.txt",
        "../shared.txt",
        "./shared.txt",
        "/shared.txt",
        "a\\b",
        "a//b",
        ".git/config",
    ] {
        let fixture = Fixture::new();
        let mut request = fixture.request(&[]);
        request.artifacts = vec![artifact.into()];
        assert!(
            prepare_workflow_integration(&request).is_err(),
            "{artifact}"
        );
    }
}

#[test]
fn workflow_integration_preserves_ignored_obstructions_and_partial_checkouts() {
    let fixture = Fixture::new();
    let request = fixture.request(&[("ignored.txt", "committed\n")]);
    let target = Path::new(&fixture.integration.path).join("ignored.txt");
    fs::write(&target, "user ignored\n").unwrap();
    prepared(&request);
    assert!(apply_workflow_integration(&request).is_err());
    assert_eq!(fs::read_to_string(target).unwrap(), "user ignored\n");
    let fixture = Fixture::new();
    let request = fixture.request(&[("shared.txt", "changed\n"), ("result.txt", "done\n")]);
    prepared(&request);
    fs::write(
        Path::new(&fixture.integration.path).join("shared.txt"),
        "changed\n",
    )
    .unwrap();
    assert!(apply_workflow_integration(&request)
        .unwrap_err()
        .to_string()
        .contains("partial"));
    assert!(!Path::new(&fixture.integration.path)
        .join("result.txt")
        .exists());
}

#[test]
fn workflow_integration_receipt_retains_both_commit_graphs() {
    let fixture = Fixture::new();
    let request = fixture.request(&[("result.txt", "done\n")]);
    let receipt = prepared(&request);
    let repo = Repository::open(&fixture.repo_path).unwrap();
    let reference = repo
        .find_reference(&format!("refs/alera/workflow-integrations/{}", request.id))
        .unwrap();
    let commit = reference.peel_to_commit().unwrap();
    assert_eq!(
        commit.parent_id(0).unwrap().to_string(),
        receipt.integrated_sha
    );
    assert_eq!(commit.parent_id(1).unwrap().to_string(), request.source_sha);
    let mut walker = repo.revwalk().unwrap();
    walker.push(commit.id()).unwrap();
    let reachable = walker.map(Result::unwrap).collect::<Vec<_>>();
    assert!(reachable.contains(&oid(&request.expected_sha).unwrap()));
    assert!(reachable.contains(&oid(&request.source.base_sha).unwrap()));
}

#[test]
fn workflow_integration_binds_artifacts_to_the_merged_tree() {
    let fixture = Fixture::new();
    let mut request = fixture.request(&[("shared.txt", "base\nworker\n")]);
    request.expected_sha = commit(
        Path::new(&fixture.integration.path),
        &[("shared.txt", "parent\nbase\n")],
    );
    let receipt = prepared(&request);
    let repo = Repository::open(&fixture.integration.path).unwrap();
    let merged = repo
        .find_commit(oid(&receipt.integrated_sha).unwrap())
        .unwrap()
        .tree()
        .unwrap();
    let source = repo
        .find_commit(oid(&request.source_sha).unwrap())
        .unwrap()
        .tree()
        .unwrap();
    assert_eq!(
        receipt.artifact_digest,
        artifact_digest(&merged, &request.artifacts).unwrap()
    );
    assert_ne!(
        receipt.artifact_digest,
        artifact_digest(&source, &request.artifacts).unwrap()
    );
    apply_workflow_integration(&request).unwrap();
    assert_eq!(
        fs::read_to_string(Path::new(&fixture.integration.path).join("shared.txt")).unwrap(),
        "parent\nbase\nworker\n"
    );
}

#[test]
fn workflow_integration_rejects_changed_source_tip_and_foreign_resource() {
    let fixture = Fixture::new();
    let request = fixture.request(&[("result.txt", "done\n")]);
    prepared(&request);
    commit(
        Path::new(&fixture.source.path),
        &[("result.txt", "changed\n")],
    );
    assert!(apply_workflow_integration(&request)
        .unwrap_err()
        .to_string()
        .contains("branch changed"));
    let fixture = Fixture::new();
    let mut request = fixture.request(&[]);
    request.source.id = Uuid::new_v4().to_string();
    assert!(prepare_workflow_integration(&request).is_err());
}

#[cfg(unix)]
#[test]
fn workflow_integration_rejects_symlink_artifacts_without_reading_their_target() {
    let fixture = Fixture::new();
    let mut request = fixture.request(&[]);
    let repo = Repository::open(&fixture.source.path).unwrap();
    std::os::unix::fs::symlink(
        "/unreadable-target",
        Path::new(&fixture.source.path).join("link"),
    )
    .unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("link")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    let signature = repo.signature().unwrap();
    request.source_sha = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            "test: link artifact",
            &tree,
            &[&parent],
        )
        .unwrap()
        .to_string();
    request.artifacts = vec!["link".into()];
    assert!(prepare_workflow_integration(&request)
        .unwrap_err()
        .to_string()
        .contains("regular files"));
}
