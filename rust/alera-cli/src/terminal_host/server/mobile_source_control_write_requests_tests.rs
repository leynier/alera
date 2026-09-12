use std::fs;
use std::path::Path;

use alera_core::runtime::{Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus};
use chrono::Utc;

use super::super::mobile_source_control_snapshot::tests::{init_repo, run_git};
use super::*;

struct Fixture {
    _runtime_dir: tempfile::TempDir,
    repo: tempfile::TempDir,
    store: RuntimeStore,
    workspace_id: String,
}

impl Fixture {
    async fn new() -> Self {
        Self::with_host(LOCAL_HOST_ID).await
    }

    async fn with_host(host_id: &str) -> Self {
        let runtime_dir = tempfile::tempdir().unwrap();
        let repo = tempfile::tempdir().unwrap();
        init_repo(repo.path());
        let store = RuntimeStore::open(runtime_dir.path()).await.unwrap();
        let now = Utc::now();
        let path = repo.path().to_string_lossy().into_owned();
        // The write guard is process-wide and tests run in parallel.
        let workspace_id = format!(
            "workspace-{}",
            repo.path().file_name().unwrap().to_string_lossy()
        );
        store
            .upsert_project(Project {
                id: "project-1".into(),
                name: "Project".into(),
                repo_path: path.clone(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: workspace_id.clone(),
                instance_id: "instance-1".into(),
                host_id: host_id.into(),
                project_id: "project-1".into(),
                name: "Workspace".into(),
                branch: Some("main".into()),
                path,
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Main,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: true,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                section_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
        Self {
            _runtime_dir: runtime_dir,
            repo,
            store,
            workspace_id,
        }
    }

    fn path(&self) -> &Path {
        self.repo.path()
    }

    async fn write(&self, request_type: &str, mut payload: Value) -> HostResult<Value> {
        payload["workspaceId"] = json!(self.workspace_id);
        mobile_git_write(&self.store, request_type, &payload).await
    }

    fn add_bare_origin(&self) -> tempfile::TempDir {
        let remote = tempfile::tempdir().unwrap();
        run_git(remote.path(), &["init", "-q", "--bare", "-b", "main"]);
        run_git(
            self.path(),
            &["remote", "add", "origin", &remote.path().to_string_lossy()],
        );
        remote
    }
}

fn entry<'a>(snapshot: &'a Value, path: &str, area: &str) -> Option<&'a Value> {
    snapshot["entries"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["path"] == path && entry["area"] == area)
}

fn error_code(result: HostResult<Value>) -> String {
    result.unwrap_err().wire_response(1)["errorCode"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

#[tokio::test]
async fn stage_commit_and_push_publishes_the_branch() {
    let fixture = Fixture::new().await;
    let _remote = fixture.add_bare_origin();
    fs::write(fixture.path().join("tracked.txt"), "two\n").unwrap();

    let staged = fixture
        .write("mobile.git.stage", json!({ "path": "tracked.txt" }))
        .await
        .unwrap();
    let entry = entry(&staged, "tracked.txt", "staged").unwrap();
    assert_eq!(entry["canUnstage"], true);
    assert_eq!(staged["actions"]["commit"], true);

    let committed = fixture
        .write(
            "mobile.git.commit",
            json!({ "message": "  update tracked  ", "then": "push" }),
        )
        .await
        .unwrap();
    assert!(committed["commitOid"]
        .as_str()
        .is_some_and(|oid| oid.len() == 40));
    assert_eq!(committed["entries"], json!([]));
    assert_eq!(committed["repository"]["upstream"], "origin/main");
    assert_eq!(committed["repository"]["headMessage"], "update tracked");
    assert_eq!(
        run_git(fixture.path(), &["rev-parse", "origin/main"]),
        committed["commitOid"]
    );
}

#[tokio::test]
async fn unstage_and_discard_all_restore_the_tree() {
    let fixture = Fixture::new().await;
    fs::write(fixture.path().join("tracked.txt"), "two\n").unwrap();
    fs::write(fixture.path().join("new.txt"), "fresh\n").unwrap();
    fixture.write("mobile.git.stage", json!({})).await.unwrap();

    let unstaged = fixture
        .write("mobile.git.unstage", json!({ "area": "staged" }))
        .await
        .unwrap();
    assert!(entry(&unstaged, "tracked.txt", "unstaged").is_some());
    assert!(entry(&unstaged, "new.txt", "untracked").is_some());

    let discarded = fixture
        .write("mobile.git.discard", json!({}))
        .await
        .unwrap();
    assert_eq!(discarded["entries"], json!([]));
    assert!(!fixture.path().join("new.txt").exists());
    assert_eq!(
        fs::read_to_string(fixture.path().join("tracked.txt")).unwrap(),
        "one\n"
    );
}

#[tokio::test]
async fn amend_keeps_the_original_author() {
    let fixture = Fixture::new().await;
    run_git(fixture.path(), &["config", "user.name", "Someone Else"]);
    fs::write(fixture.path().join("tracked.txt"), "two\n").unwrap();
    fixture
        .write("mobile.git.stage", json!({ "path": "tracked.txt" }))
        .await
        .unwrap();

    let amended = fixture
        .write(
            "mobile.git.commit",
            json!({ "message": "init, amended", "amend": true }),
        )
        .await
        .unwrap();

    assert_eq!(amended["repository"]["headMessage"], "init, amended");
    assert_eq!(
        run_git(fixture.path(), &["log", "-1", "--format=%an"]),
        "Alera"
    );
    assert_eq!(
        run_git(fixture.path(), &["rev-list", "--count", "HEAD"]),
        "1"
    );
}

#[tokio::test]
async fn commit_without_staged_changes_uses_the_desktop_message() {
    let fixture = Fixture::new().await;

    let error = fixture
        .write("mobile.git.commit", json!({ "message": "empty" }))
        .await
        .unwrap_err();

    let response = error.wire_response(1);
    assert_eq!(response["error"], "Nothing to commit.");
    assert_eq!(response["errorCode"], "gitNothingToCommit");
}

#[tokio::test]
async fn sync_without_an_upstream_is_refused() {
    let fixture = Fixture::new().await;

    let result = fixture.write("mobile.git.sync", json!({})).await;

    assert_eq!(error_code(result), "gitNoUpstream");
}

#[tokio::test]
async fn stash_and_pop_by_index() {
    let fixture = Fixture::new().await;
    fs::write(fixture.path().join("tracked.txt"), "two\n").unwrap();

    let stashed = fixture.write("mobile.git.stash", json!({})).await.unwrap();
    assert_eq!(stashed["entries"], json!([]));
    assert_eq!(stashed["stashes"].as_array().unwrap().len(), 1);
    assert_eq!(stashed["actions"]["stashPop"], true);

    let popped = fixture
        .write("mobile.git.stashPop", json!({ "stashIndex": 0 }))
        .await
        .unwrap();
    assert!(entry(&popped, "tracked.txt", "unstaged").is_some());
    assert_eq!(popped["stashes"], json!([]));
}

#[tokio::test]
async fn branches_checkout_and_create() {
    let fixture = Fixture::new().await;
    run_git(fixture.path(), &["branch", "feature"]);

    let created = fixture
        .write("mobile.git.createBranch", json!({ "branch": " topic " }))
        .await
        .unwrap();
    assert_eq!(created["branch"], "topic");

    let branches = mobile_git_branches(
        &fixture.store,
        &json!({ "workspaceId": fixture.workspace_id }),
    )
    .await
    .unwrap();
    assert_eq!(branches["current"], "topic");
    assert_eq!(
        branches["localBranches"],
        json!(["feature", "main", "topic"])
    );

    let switched = fixture
        .write("mobile.git.checkout", json!({ "branch": "feature" }))
        .await
        .unwrap();
    assert_eq!(switched["branch"], "feature");

    let result = fixture
        .write("mobile.git.createBranch", json!({ "branch": "main" }))
        .await;
    assert_eq!(error_code(result), "gitBranchAlreadyExists");
}

#[tokio::test]
async fn a_second_write_on_the_same_workspace_is_refused() {
    let fixture = Fixture::new().await;
    let _held = WorkspaceWriteGuard::acquire(&fixture.workspace_id).unwrap();

    let result = fixture.write("mobile.git.fetch", json!({})).await;

    assert_eq!(error_code(result), "sourceControlBusy");
}

#[tokio::test]
async fn remote_host_workspaces_are_refused() {
    let fixture = Fixture::with_host("ssh-devbox").await;
    fs::write(fixture.path().join("tracked.txt"), "two\n").unwrap();

    let error = fixture
        .write("mobile.git.stage", json!({}))
        .await
        .unwrap_err();

    assert!(error
        .wire_message()
        .contains("only available for workspaces on this runtime"));
    assert_eq!(
        run_git(fixture.path(), &["diff", "--cached", "--name-only"]),
        ""
    );
}

#[tokio::test]
async fn paths_outside_the_workspace_are_rejected() {
    let fixture = Fixture::new().await;

    for path in ["../outside.txt", "/etc/passwd"] {
        let result = fixture
            .write("mobile.git.discard", json!({ "path": path }))
            .await;
        assert!(result.is_err(), "{path}");
    }
}

#[test]
fn malformed_payloads_are_format_errors() {
    for (request, payload) in [
        ("mobile.git.stage", json!({ "area": "elsewhere" })),
        (
            "mobile.git.commit",
            json!({ "message": "x", "then": "deploy" }),
        ),
        ("mobile.git.commit", json!({})),
        ("mobile.git.stashPop", json!({})),
        ("mobile.git.checkout", json!({ "branch": "" })),
    ] {
        let error = parse_write(request, &payload).unwrap_err();
        assert!(
            error.wire_message().starts_with("FormatException"),
            "{request}: {}",
            error.wire_message()
        );
    }
}
