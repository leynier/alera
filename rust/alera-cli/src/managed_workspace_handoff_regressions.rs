use super::*;
use alera_core::runtime::{WorkbenchLayoutRecord, WorkspaceTabRecord};
use serde_json::{json, Value};

async fn handoff(fixture: &Fixture, branch: &str) -> Workspace {
    hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".into(),
            branch: branch.into(),
            name: None,
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(fixture.child_path("child").to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap()
    .workspace
}

fn tab(id: &str, owner: &str, payload: Value) -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: id.into(),
        workspace_id: owner.into(),
        title: id.into(),
        kind: "terminal".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload,
    }
}

fn layout(owner: &str, tabs: &[&str]) -> WorkbenchLayoutRecord {
    WorkbenchLayoutRecord {
        workspace_id: owner.into(),
        data: json!({"workspaceId":owner,
        "root":{"type":"leaf","groupId":"main/main"}, "groups":{"main/main":{"id":"main/main","tabIds":tabs,"activeTabId":tabs.last()}},
        "activeGroupId":"main/main"}),
    }
}

#[tokio::test]
async fn handoff_round_trip_persists_ids_paths_layout_and_existing_destination_tabs() {
    let fixture = Fixture::new().await;
    fixture
        .store
        .upsert_workspace_tab(tab(
            "agent",
            "main",
            json!({"terminalSessionId":"pty-1","agentNativeSessionId":"native-1"}),
        ))
        .await
        .unwrap();
    fixture
        .store
        .upsert_workspace_tab(tab(
            "editor",
            "main",
            json!({"filePath":fixture.repo.join("tracked.txt").to_str().unwrap()}),
        ))
        .await
        .unwrap();
    fixture
        .store
        .upsert_workbench_layout(layout("main", &["agent", "editor"]))
        .await
        .unwrap();
    let child = handoff(&fixture, "feat/roundtrip").await;
    assert!(!child.reuses_existing_branch);
    assert!(fixture
        .store
        .list_workspace_tabs("main")
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        fixture
            .store
            .find_workspace_tab("editor")
            .await
            .unwrap()
            .unwrap()
            .payload["filePath"],
        json!(Path::new(&child.path).join("tracked.txt"))
    );
    fixture
        .store
        .upsert_workspace_tab(tab(
            "existing",
            "main",
            json!({"terminalSessionId":"main-pty"}),
        ))
        .await
        .unwrap();
    fixture
        .store
        .upsert_workbench_layout(layout("main", &["existing"]))
        .await
        .unwrap();
    hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: child.id.clone(),
            close_sessions: false,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap();
    let reopened = RuntimeStore::open(&fixture._dir.path().join("runtime"))
        .await
        .unwrap();
    let tabs = reopened.list_workspace_tabs("main").await.unwrap();
    assert_eq!(tabs.len(), 3);
    let agent = reopened.find_workspace_tab("agent").await.unwrap().unwrap();
    assert_eq!(agent.payload["terminalSessionId"], "pty-1");
    assert_eq!(agent.payload["agentNativeSessionId"], "native-1");
    assert_eq!(
        reopened
            .find_workspace_tab("editor")
            .await
            .unwrap()
            .unwrap()
            .payload["filePath"],
        json!(fixture.repo.join("tracked.txt"))
    );
    let layout = reopened
        .find_workbench_layout("main")
        .await
        .unwrap()
        .unwrap()
        .data;
    assert_eq!(layout["groups"]["main/main"]["tabIds"], json!(["existing"]));
    assert_eq!(
        layout["groups"]["main/main/handoff/1"]["tabIds"],
        json!(["agent", "editor"])
    );
    assert_eq!(layout["activeGroupId"], "main/main/handoff/1");
    assert!(reopened.find_workspace(&child.id).await.unwrap().is_none());
}

#[tokio::test]
async fn handon_refuses_ignored_child_files_before_mutation() {
    let fixture = Fixture::new().await;
    let child = handoff(&fixture, "feat/ignored").await;
    std::fs::write(fixture.repo.join(".git/info/exclude"), "secret\n").unwrap();
    std::fs::write(Path::new(&child.path).join("secret"), "private").unwrap();
    let error = hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: child.id.clone(),
            close_sessions: true,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("ignored"), "{error}");
    assert_eq!(git::current_branch(&child.path).unwrap(), "feat/ignored");
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "main"
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&child.path).join("secret")).unwrap(),
        "private"
    );
}

#[tokio::test]
async fn handon_refuses_main_operation_before_stashing_child() {
    let fixture = Fixture::new().await;
    let child = handoff(&fixture, "feat/conflict").await;
    std::fs::write(
        fixture.repo.join(".git/MERGE_HEAD"),
        "0000000000000000000000000000000000000000\n",
    )
    .unwrap();
    std::fs::write(Path::new(&child.path).join("scratch"), "keep").unwrap();
    assert!(hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: child.id.clone(),
            close_sessions: true,
            active_workspace_id: None
        }
    )
    .await
    .is_err());
    assert!(Path::new(&child.path).join("scratch").exists());
    assert_eq!(git::current_branch(&child.path).unwrap(), "feat/conflict");
}

#[tokio::test]
async fn reuse_custom_default_preserves_branch_ownership_and_returns_main_to_trunk() {
    let fixture = Fixture::new().await;
    fixture.run_git(&["branch", "trunk"]);
    fixture.run_git(&[
        "symbolic-ref",
        "refs/remotes/origin/HEAD",
        "refs/remotes/origin/trunk",
    ]);
    fixture.run_git(&["checkout", "-b", "feat/current"]);
    let child = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".into(),
            branch: "feat/current".into(),
            name: None,
            reuse_existing_branch: true,
            workspace_root: None,
            path: Some(fixture.child_path("custom").to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap()
    .workspace;
    assert!(child.reuses_existing_branch);
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "trunk"
    );
    assert_eq!(
        fixture
            .store
            .find_workspace("main")
            .await
            .unwrap()
            .unwrap()
            .branch
            .as_deref(),
        Some("trunk")
    );
}

#[tokio::test]
async fn handoff_refuses_occupied_default_before_stashing() {
    let fixture = Fixture::new().await;
    fixture.run_git(&["checkout", "-b", "feat/current"]);
    let occupied = fixture.child_path("occupied-main");
    fixture.run_git(&["worktree", "add", occupied.to_str().unwrap(), "main"]);
    std::fs::write(fixture.repo.join("scratch"), "keep").unwrap();
    let error = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".into(),
            branch: "feat/current".into(),
            name: None,
            reuse_existing_branch: true,
            workspace_root: None,
            path: Some(fixture.child_path("blocked").to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("checked out"));
    assert!(fixture.repo.join("scratch").exists());
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "feat/current"
    );
}

#[tokio::test]
async fn handoff_and_handon_preserve_partial_staging() {
    let fixture = Fixture::new().await;
    std::fs::write(fixture.repo.join("tracked.txt"), "staged\n").unwrap();
    fixture.run_git(&["add", "tracked.txt"]);
    std::fs::write(fixture.repo.join("tracked.txt"), "unstaged\n").unwrap();
    std::fs::write(fixture.repo.join("scratch"), "untracked").unwrap();
    let child = handoff(&fixture, "feat/index").await;
    let index = |path: &str| {
        alera_core::git_cli::git_in_dir(Path::new(path), &["show", ":tracked.txt"]).unwrap()
    };
    assert_eq!(index(&child.path), "staged\n");
    assert_eq!(
        std::fs::read_to_string(Path::new(&child.path).join("tracked.txt")).unwrap(),
        "unstaged\n"
    );
    let result = hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: child.id,
            close_sessions: false,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap();
    assert!(result.recovery_stash_oid.is_some());
    assert_eq!(index(fixture.repo.to_str().unwrap()), "staged\n");
    assert_eq!(
        std::fs::read_to_string(fixture.repo.join("tracked.txt")).unwrap(),
        "unstaged\n"
    );
    assert!(fixture.repo.join("scratch").exists());
}
