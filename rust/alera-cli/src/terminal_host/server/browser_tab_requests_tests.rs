use std::collections::{BTreeSet, HashMap};

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use super::*;
use crate::terminal_host::server::actor_test_harness::test_actor;
use crate::terminal_host::server::browser_broker::BrowserDriver;

#[test]
fn page_id_accepts_the_tab_id_compatibility_alias() {
    assert_eq!(page_id(&json!({"tabId": "page-1"})).unwrap(), "page-1");
}

#[test]
fn a_browser_tab_error_is_machine_readable() {
    let value = not_browser_tab("terminal-1");
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "not_browser_tab");
    assert!(value["error"]["retryable"].is_boolean());
}

#[tokio::test]
async fn close_and_reopen_keep_catalog_layout_and_restore_payload_coherent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    seed_workspace(&actor).await;
    actor
        .runtime_store
        .ensure_default_browser_profile()
        .await
        .unwrap();

    let unavailable = actor
        .open_browser_tab(&json!({
            "workspaceId": "workspace-1",
            "pageId": "unavailable",
        }))
        .await
        .unwrap();
    assert_eq!(unavailable["error"]["code"], "browser_unavailable");
    actor.browser.register_driver(stable_driver());

    let opened = actor
        .open_browser_tab(&json!({
            "workspaceId": "workspace-1",
            "pageId": "page-1",
            "url": "https://example.com/docs",
        }))
        .await
        .unwrap();
    assert_eq!(opened["ok"], true);
    let mut tab = actor
        .runtime_store
        .find_workspace_tab("page-1")
        .await
        .unwrap()
        .unwrap();
    tab.payload["zoom"] = json!(1.25);
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();

    let closed = actor
        .close_browser_tab(&json!({"pageId": "page-1"}))
        .await
        .unwrap();
    assert_eq!(closed["ok"], true);
    assert!(actor
        .runtime_store
        .find_workspace_tab("page-1")
        .await
        .unwrap()
        .is_none());
    let recent = actor
        .runtime_store
        .list_closed_browser_tabs(None, 10)
        .await
        .unwrap();
    assert_eq!(recent.len(), 1);
    assert_eq!(recent[0].payload["zoom"], 1.25);
    let closed_id = recent[0].id.clone();

    let reopened = actor
        .reopen_browser_tab(&json!({"id": closed_id}))
        .await
        .unwrap();
    assert_eq!(reopened["ok"], true);
    let reopened_id = reopened["pageId"].as_str().unwrap();
    assert_ne!(reopened_id, "page-1");
    let reopened_tab = actor
        .runtime_store
        .find_workspace_tab(reopened_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(reopened_tab.payload["zoom"], 1.25);
    assert_eq!(reopened_tab.payload["browserProfileId"], "default");
    assert!(actor
        .runtime_store
        .list_closed_browser_tabs(None, 10)
        .await
        .unwrap()
        .is_empty());
    let layout = actor
        .runtime_store
        .find_workbench_layout("workspace-1")
        .await
        .unwrap()
        .unwrap();
    let tab_ids = layout.data["groups"]["workspace-1/main"]["tabIds"]
        .as_array()
        .unwrap();
    assert_eq!(tab_ids, &[json!(reopened_id)]);
}

#[tokio::test]
async fn reopen_rolls_back_the_created_tab_when_removing_the_closed_entry_fails() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    seed_workspace(&actor).await;
    actor
        .runtime_store
        .ensure_default_browser_profile()
        .await
        .unwrap();
    actor.browser.register_driver(stable_driver());

    actor
        .open_browser_tab(&json!({
            "workspaceId": "workspace-1",
            "pageId": "page-1",
        }))
        .await
        .unwrap();
    actor
        .close_browser_tab(&json!({"pageId": "page-1"}))
        .await
        .unwrap();
    let closed = actor
        .runtime_store
        .list_closed_browser_tabs(None, 10)
        .await
        .unwrap();
    let layout_before = actor
        .runtime_store
        .find_workbench_layout("workspace-1")
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER reject_closed_tab_delete BEFORE DELETE ON browserClosedTabs \
         BEGIN SELECT RAISE(FAIL, 'blocked closed tab delete'); END",
    )
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();

    let error = actor
        .reopen_browser_tab(&json!({"id": closed[0].id}))
        .await
        .unwrap_err();

    assert!(error.to_string().contains("blocked closed tab delete"));
    assert!(actor
        .runtime_store
        .list_workspace_tabs("workspace-1")
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        actor
            .runtime_store
            .find_workbench_layout("workspace-1")
            .await
            .unwrap(),
        layout_before,
    );
    assert_eq!(
        actor
            .runtime_store
            .list_closed_browser_tabs(None, 10)
            .await
            .unwrap()
            .len(),
        1,
    );
}

fn stable_driver() -> BrowserDriver {
    BrowserDriver {
        owner_client_id: 1,
        app_instance_id: "app".to_string(),
        driver_instance_id: "driver".to_string(),
        engine: "test".to_string(),
        platform: "test".to_string(),
        capabilities: BTreeSet::from(["stableGate".to_string()]),
    }
}

async fn seed_workspace(actor: &ServerActor) {
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project-1".to_string(),
            name: "Project".to_string(),
            repo_path: "/tmp/project-1".to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "workspace-1".to_string(),
            instance_id: "instance-1".to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: "project-1".to_string(),
            name: "Workspace".to_string(),
            branch: Some("main".to_string()),
            path: "/tmp/project-1".to_string(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
}
