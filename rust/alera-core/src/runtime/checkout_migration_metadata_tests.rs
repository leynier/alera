use chrono::Utc;
use serde_json::json;

use super::{fixture, workspace};
use crate::runtime::{
    RuntimeStore, WorkbenchLayoutRecord, WorkspaceKind, WorkspaceTabRecord, WorkspaceTag,
};

#[tokio::test]
async fn checkout_backfill_keeps_shared_tasks_tabs_layouts_and_organization() {
    let (directory, store, _) = fixture().await;
    for id in ["first", "second"] {
        store
            .insert_workspace(workspace(id, "local", "/repo", WorkspaceKind::Main))
            .await
            .unwrap();
        for kind in ["editor", "terminal"] {
            let now = Utc::now();
            store.upsert_workspace_tab(WorkspaceTabRecord {
                id: format!("{id}-{kind}"), workspace_id: id.into(), kind: kind.into(),
                title: format!("Existing {kind}"), created_at: now, updated_at: now,
                payload: json!({"filePath": "/repo/task.md", "terminalSessionId": format!("session-{id}"), "cwd": "/repo"}),
            }).await.unwrap();
        }
        store.upsert_workbench_layout(WorkbenchLayoutRecord {
            workspace_id: id.into(),
            data: json!({"tabIds": [format!("{id}-terminal"), format!("{id}-editor")], "activeTabId": format!("{id}-editor")}),
        }).await.unwrap();
    }
    store.set_workspace_pinned("second", true).await.unwrap();
    store
        .create_workspace_section("Existing Section", "first")
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_tag(WorkspaceTag {
            id: "tag".into(),
            name: "Existing Tag".into(),
            color: None,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    store.assign_tag("first", "tag").await.unwrap();
    store.link_workspaces("first", "second").await.unwrap();
    let tasks = store.list_all_workspaces().await.unwrap();
    let relations = store.list_relations().await.unwrap();
    let sections = store.list_workspace_sections().await.unwrap();
    let tags = store.list_tags().await.unwrap();
    let mut content = Vec::new();
    for id in ["first", "second"] {
        content.push((
            id,
            store.list_workspace_tabs(id).await.unwrap(),
            store.find_workbench_layout(id).await.unwrap(),
        ));
    }
    sqlx::query("DELETE FROM workspaceCheckoutBindings")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("DELETE FROM repositoryCheckouts")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(reopened.list_all_workspaces().await.unwrap(), tasks);
    assert_eq!(reopened.list_relations().await.unwrap(), relations);
    assert_eq!(reopened.list_workspace_sections().await.unwrap(), sections);
    assert_eq!(reopened.list_tags().await.unwrap(), tags);
    for (id, tabs, layout) in content {
        assert_eq!(reopened.list_workspace_tabs(id).await.unwrap(), tabs);
        assert_eq!(reopened.find_workbench_layout(id).await.unwrap(), layout);
    }
    let first = reopened
        .find_workspace_checkout("first")
        .await
        .unwrap()
        .unwrap();
    let second = reopened
        .find_workspace_checkout("second")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first.id, second.id);
    assert_eq!(reopened.list_all_workspaces().await.unwrap().len(), 2);
}
