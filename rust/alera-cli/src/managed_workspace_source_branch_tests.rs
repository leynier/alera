use std::path::Path;
use std::process::Command as StdCommand;

use alera_core::runtime::{Project, ProjectKind, RuntimeStore};
use chrono::Utc;

use super::{create_managed_workspace, ManagedWorkspaceCreateRequest};

#[tokio::test]
async fn create_managed_workspace_uses_origin_twin_of_configured_source_branch() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let origin = dir.path().join("origin.git");
    std::fs::create_dir(&origin).unwrap();
    run_git(&origin, &["init", "--bare"]);
    run_git(
        &repo,
        &["remote", "add", "origin", &origin.to_string_lossy()],
    );
    run_git(&repo, &["push", "origin", "main:develop"]);
    run_git(&repo, &["fetch", "origin"]);
    std::fs::write(
        repo.join("alera.toml"),
        "[new_workspace]\nsource_branch = \"develop\"\n",
    )
    .unwrap();
    let store = seed_project(dir.path(), &repo).await;
    let worktree_path = dir.path().join("workspaces").join("feature-from-develop");

    let result = create_managed_workspace(
        &store,
        ManagedWorkspaceCreateRequest {
            id: Some("workspace-from-develop".to_string()),
            project_id: "project-1".to_string(),
            name: Some("feature/from-develop".to_string()),
            branch: "feature/from-develop".to_string(),
            source_branch: None,
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            parent_workspace_id: None,
            host_id: None,
            defer_setup: false,
            skip_setup: true,
            setup_script_directory: None,
        },
    )
    .await
    .expect("create from origin/develop");

    assert_eq!(
        result.workspace.source_branch.as_deref(),
        Some("origin/develop")
    );
    assert!(worktree_path.exists());
}

fn request(id: Option<&str>, branch: &str, path: &Path) -> ManagedWorkspaceCreateRequest {
    ManagedWorkspaceCreateRequest {
        id: id.map(ToString::to_string),
        project_id: "project-1".to_string(),
        name: None,
        branch: branch.to_string(),
        source_branch: Some("main".to_string()),
        reuse_existing_branch: false,
        workspace_root: None,
        path: Some(path.to_string_lossy().into_owned()),
        parent_workspace_id: None,
        host_id: None,
        defer_setup: false,
        skip_setup: true,
        setup_script_directory: None,
    }
}

#[tokio::test]
async fn required_field_errors_read_as_sentences() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    let path = dir.path().join("workspaces").join("feature");

    let blank_id = create_managed_workspace(&store, request(Some(" "), "feature", &path))
        .await
        .unwrap_err();
    assert_eq!(blank_id.to_string(), "Workspace id is required");

    let blank_branch = create_managed_workspace(&store, request(None, "  ", &path))
        .await
        .unwrap_err();
    assert_eq!(blank_branch.to_string(), "New branch name is required");
}

#[tokio::test]
async fn a_failed_worktree_add_keeps_git_output_on_the_wire() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    let path = dir.path().join("workspaces").join("occupied");
    std::fs::create_dir_all(&path).unwrap();
    std::fs::write(path.join("keep.txt"), "not a worktree\n").unwrap();

    let error = create_managed_workspace(&store, request(None, "feature/occupied", &path))
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "git worktree add failed");
    let wire = crate::terminal_host::host_error::HostError::from_anyhow(&error).wire_message();
    assert!(
        wire.starts_with("git worktree add failed: ")
            && wire.len() > "git worktree add failed: ".len(),
        "the cause was dropped: {wire}"
    );
}

async fn seed_project(root: &Path, repo: &Path) -> RuntimeStore {
    let store = RuntimeStore::open(&root.join("runtime")).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project-1".to_string(),
            name: "Project".to_string(),
            repo_path: repo.to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
}

fn init_git_repo(repo: &Path) {
    run_git(repo, &["init"]);
    run_git(repo, &["config", "user.email", "test@example.com"]);
    run_git(repo, &["config", "user.name", "Test"]);
    std::fs::write(repo.join("README.md"), "hello\n").unwrap();
    run_git(repo, &["add", "README.md"]);
    run_git(repo, &["commit", "-m", "initial"]);
    run_git(repo, &["branch", "-M", "main"]);
}

#[allow(clippy::disallowed_methods)]
fn run_git(repo: &Path, args: &[&str]) {
    let output = StdCommand::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {} failed\nstdout:\n{}\nstderr:\n{}",
        args.join(" "),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
