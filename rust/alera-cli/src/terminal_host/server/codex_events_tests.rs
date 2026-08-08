use std::collections::HashMap;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord,
    LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

use super::*;
use crate::terminal_host::server::actor_test_harness::test_actor;
use crate::terminal_host::server::codex_state::set_thread_and_snapshot;

#[tokio::test]
async fn explicit_old_thread_does_not_fall_back_to_a_retained_turn() {
    let dir = tempfile::tempdir().unwrap();
    let actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    seed_workspace(&actor).await;
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "tab".to_string(),
        workspace_id: "workspace".to_string(),
        kind: "codex".to_string(),
        title: "Codex Chat".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    };
    set_thread_and_snapshot(
        &mut tab,
        "thread-new",
        json!({
            "activeTurnId": "turn-new",
            "events": [{
                "method": "turn/completed",
                "params": {
                    "threadId": "thread-old",
                    "turn": {"id": "turn-old"},
                },
            }],
            "timelineCells": [],
            "pendingRequests": [],
        }),
    );
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();

    let delayed = json!({
        "method": "turn/completed",
        "params": {
            "threadId": "thread-old",
            "turn": {"id": "turn-old"},
        },
    });
    assert!(actor
        .find_codex_tab_for_message(&delayed, Some("thread-old"))
        .await
        .unwrap()
        .is_none());

    let legacy_without_thread = json!({
        "method": "turn/completed",
        "params": {"turn": {"id": "turn-old"}},
    });
    assert_eq!(
        actor
            .find_codex_tab_for_message(&legacy_without_thread, None)
            .await
            .unwrap()
            .map(|tab| tab.id)
            .as_deref(),
        Some("tab"),
    );
}

#[test]
fn auto_resolution_stays_scoped_to_its_originating_thread() {
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "tab".to_string(),
        workspace_id: "workspace".to_string(),
        kind: "codex".to_string(),
        title: "Codex Chat".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    };
    set_thread_and_snapshot(
        &mut tab,
        "thread-new",
        json!({"pendingRequests": [{"id": 7, "method": "item/tool/request_user_input"}]}),
    );

    assert!(pending_auto_resolution_request(&tab, "thread-old", &json!(7)).is_none());
    assert_eq!(
        pending_auto_resolution_request(&tab, "thread-new", &json!(7))
            .and_then(|request| request.get("id").cloned()),
        Some(json!(7)),
    );
}

async fn seed_workspace(actor: &ServerActor) {
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".to_string(),
            name: "Project".to_string(),
            repo_path: dir_path(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "workspace".to_string(),
            instance_id: "instance".to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: "project".to_string(),
            name: "Workspace".to_string(),
            branch: Some("main".to_string()),
            path: dir_path(),
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
            child_count: 0,
        })
        .await
        .unwrap();
}

fn dir_path() -> String {
    std::env::temp_dir().to_string_lossy().into_owned()
}
