use std::collections::BTreeSet;
use std::path::Path;

use chrono::Utc;
use serde_json::{json, Value};

use crate::runtime::{
    Project, ProjectKind, RuntimeStore, WorkbenchLayoutRecord, Workspace, WorkspaceKind,
    WorkspaceStatus, WorkspaceTabRecord, LOCAL_HOST_ID,
};

async fn fixture() -> (tempfile::TempDir, RuntimeStore, Workspace, Workspace) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: dir.path().join("main").to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let main = store
        .upsert_workspace(workspace(dir.path(), "main"))
        .await
        .unwrap();
    let child = store
        .upsert_workspace(workspace(dir.path(), "child"))
        .await
        .unwrap();
    (dir, store, main, child)
}

fn workspace(root: &Path, id: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.into(),
        instance_id: format!("instance-{id}"),
        host_id: LOCAL_HOST_ID.into(),
        project_id: "project".into(),
        name: id.into(),
        branch: Some(if id == "main" { "main" } else { "feature/task" }.into()),
        path: root.join(id).to_string_lossy().into_owned(),
        created_at: now,
        updated_at: now,
        kind: if id == "main" {
            WorkspaceKind::Main
        } else {
            WorkspaceKind::Linked
        },
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: vec![],
        tag_names: vec![],
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

fn tab(id: &str, workspace: &Workspace, payload: Value) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: id.into(),
        workspace_id: workspace.id.clone(),
        kind: "terminal".into(),
        title: format!("Title {id}"),
        created_at: now,
        updated_at: now,
        payload,
    }
}

fn layout(workspace_id: &str, ids: &[&str], active: &str) -> WorkbenchLayoutRecord {
    let group = format!("{workspace_id}/main");
    WorkbenchLayoutRecord {
        workspace_id: workspace_id.into(),
        data: json!({"workspaceId": workspace_id,
            "root": {"type": "leaf", "groupId": group}, "activeGroupId": group,
            "groups": {group.clone(): {"id": group, "tabIds": ids, "activeTabId": active}}}),
    }
}

#[tokio::test]
async fn persisted_roundtrip_retains_tabs_identity_paths_layout_and_restart_state() {
    let (dir, store, main, child) = fixture().await;
    let outside_path = dir.path().join("outside.md").to_string_lossy().into_owned();
    let original = tab(
        "agent",
        &main,
        json!({
            "terminalSessionId": "terminal-717", "agentNativeSessionId": "native-717",
            "agentType": "codex", "initialPrompt": "Continue this task",
            "workingDirectory": Path::new(&main.path).join("src").to_string_lossy(),
        }),
    );
    store.upsert_workspace_tab(original.clone()).await.unwrap();
    store
        .upsert_workspace_tab(tab("outside", &main, json!({"filePath": outside_path})))
        .await
        .unwrap();
    store
        .upsert_workbench_layout(layout(&main.id, &["agent", "outside"], "agent"))
        .await
        .unwrap();
    let original = store.find_workspace_tab("agent").await.unwrap().unwrap();

    store
        .transfer_workspace_contents(&main, &child)
        .await
        .unwrap();

    assert!(store
        .list_workspace_tabs(&main.id)
        .await
        .unwrap()
        .is_empty());
    assert!(store
        .find_workbench_layout(&main.id)
        .await
        .unwrap()
        .is_none());
    let moved = store.find_workspace_tab("agent").await.unwrap().unwrap();
    assert_eq!(moved.workspace_id, child.id);
    assert_eq!(moved.title, original.title);
    assert_eq!(moved.updated_at, original.updated_at);
    assert_eq!(moved.payload["terminalSessionId"], "terminal-717");
    assert_eq!(moved.payload["agentNativeSessionId"], "native-717");
    assert_eq!(moved.payload["initialPrompt"], "Continue this task");
    assert_eq!(
        moved.payload["workingDirectory"],
        Path::new(&child.path)
            .join("src")
            .to_string_lossy()
            .as_ref()
    );
    assert_eq!(
        store
            .find_workspace_tab("outside")
            .await
            .unwrap()
            .unwrap()
            .payload["filePath"],
        outside_path
    );

    // Main has new workbench content before the child returns. Both layouts
    // deliberately own a main/main group, reproducing the roundtrip collision.
    store
        .upsert_workspace_tab(tab("new-main-tab", &main, json!({})))
        .await
        .unwrap();
    store
        .upsert_workbench_layout(layout(&main.id, &["new-main-tab"], "new-main-tab"))
        .await
        .unwrap();
    store
        .transfer_workspace_contents(&child, &main)
        .await
        .unwrap();
    store.remove_workspace(&child.id, false).await.unwrap();
    store.pool().close().await;
    drop(store);

    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let tabs = reopened.list_workspace_tabs(&main.id).await.unwrap();
    assert_eq!(
        tabs.iter()
            .map(|tab| tab.id.as_str())
            .collect::<BTreeSet<_>>(),
        BTreeSet::from(["agent", "outside", "new-main-tab"])
    );
    let agent = reopened.find_workspace_tab("agent").await.unwrap().unwrap();
    assert_eq!(
        agent.payload["workingDirectory"],
        original.payload["workingDirectory"]
    );
    assert_eq!(
        agent.payload["handoffSourceWorkspaceIds"],
        json!(["main", "child"])
    );
    assert_eq!(agent.payload["terminalSessionId"], "terminal-717");
    assert!(reopened.find_workspace(&child.id).await.unwrap().is_none());
    let saved = reopened
        .find_workbench_layout(&main.id)
        .await
        .unwrap()
        .unwrap()
        .data;
    let active = saved["activeGroupId"].as_str().unwrap();
    assert_eq!(saved["groups"][active]["activeTabId"], "agent");
    assert_ne!(
        saved["root"]["first"]["groupId"],
        saved["root"]["second"]["groupId"]
    );
    let layout_tabs: Vec<_> = saved["groups"]
        .as_object()
        .unwrap()
        .values()
        .flat_map(|group| group["tabIds"].as_array().unwrap())
        .filter_map(Value::as_str)
        .collect();
    assert_eq!(layout_tabs.len(), 3);
    assert_eq!(
        layout_tabs.into_iter().collect::<BTreeSet<_>>(),
        BTreeSet::from(["agent", "outside", "new-main-tab"])
    );
}

#[tokio::test]
async fn invalid_payload_rolls_back_all_prior_tab_moves_and_layout_changes() {
    let (_dir, store, main, child) = fixture().await;
    store
        .upsert_workspace_tab(tab("first", &main, json!({})))
        .await
        .unwrap();
    store
        .upsert_workspace_tab(tab("invalid", &main, json!([])))
        .await
        .unwrap();
    let original_layout = layout(&main.id, &["first", "invalid"], "first");
    store
        .upsert_workbench_layout(original_layout.clone())
        .await
        .unwrap();

    let error = store
        .transfer_workspace_contents(&main, &child)
        .await
        .unwrap_err();

    assert!(error.to_string().contains("invalid payload"));
    assert_eq!(
        store
            .find_workspace_tab("first")
            .await
            .unwrap()
            .unwrap()
            .workspace_id,
        main.id
    );
    assert!(store
        .list_workspace_tabs(&child.id)
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        store
            .find_workbench_layout(&main.id)
            .await
            .unwrap()
            .unwrap(),
        original_layout
    );
    assert!(store
        .find_workbench_layout(&child.id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn linked_issue_follows_the_transferred_work() {
    let (_dir, store, main, child) = fixture().await;
    let linked = crate::runtime::LinkedIssue {
        workspace_id: main.id.clone(),
        url: "https://github.com/leynier/alera/issues/758".into(),
        provider: Some("github".into()),
        repository: Some("leynier/alera".into()),
        number: Some(758),
        title: Some("Link an issue".into()),
        state: Some("open".into()),
        state_label: Some("Open".into()),
        fetched_at: None,
        fetch_error: None,
        linked_at: Utc::now(),
    };
    store.upsert_linked_issue(linked.clone()).await.unwrap();

    store
        .transfer_workspace_contents(&main, &child)
        .await
        .unwrap();

    assert!(store.find_linked_issue(&main.id).await.unwrap().is_none());
    let moved = store.find_linked_issue(&child.id).await.unwrap().unwrap();
    assert_eq!(moved.url, linked.url);
    assert_eq!(moved.number, Some(758));
}
