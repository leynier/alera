use chrono::Utc;
use serde_json::{json, Value};

use super::{
    AgentChatCreateOutcome, AgentChatRecord, Project, ProjectKind, RuntimeStore, Workspace,
    WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord, AGENT_CHAT_TAB_KIND, LOCAL_HOST_ID,
};

pub(super) async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

pub(super) async fn store_with_workspace(workspace_id: &str) -> (tempfile::TempDir, RuntimeStore) {
    let (dir, store) = store().await;
    add_workspace(&store, workspace_id).await;
    (dir, store)
}

pub(super) async fn add_workspace(store: &RuntimeStore, workspace_id: &str) {
    let now = Utc::now();
    if store.find_project("project").await.unwrap().is_none() {
        store
            .upsert_project(Project {
                id: "project".into(),
                name: "project".into(),
                repo_path: "/tmp/project".into(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
    }
    store
        .upsert_workspace(Workspace {
            id: workspace_id.into(),
            instance_id: format!("inst-{workspace_id}"),
            host_id: LOCAL_HOST_ID.into(),
            project_id: "project".into(),
            name: workspace_id.into(),
            branch: Some("main".into()),
            path: format!("/tmp/project/{workspace_id}"),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
}

pub(super) fn new_chat_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

pub(super) fn session(status: &str) -> Value {
    json!({
        "status": status,
        "model": "gpt-5.5",
        "runtimeMode": "approval-required",
        "interactionMode": "default",
        "capabilities": {"steer": true},
    })
}

pub(super) fn item(item_id: &str, item_type: &str, text: &str) -> Value {
    json!({
        "itemId": item_id,
        "type": item_type,
        "status": "completed",
        "streaming": false,
        "createdAt": "2026-10-12T10:00:00.000Z",
        "updatedAt": "2026-10-12T10:00:00.000Z",
        "text": text,
        "normalized": {},
    })
}

pub(super) fn snapshot(chat_id: &str, workspace_id: &str, tab_id: &str, cursor: i64) -> Value {
    json!({
        "chatId": chat_id,
        "workspaceId": workspace_id,
        "tabId": tab_id,
        "providerInstanceId": "codex-default",
        "provider": "codex",
        "title": "New Chat",
        "cursor": cursor,
        "session": session("ready"),
        "turns": [],
        "items": [],
        "pendingRequests": [],
    })
}

pub(super) fn record(
    chat_id: &str,
    workspace_id: &str,
    tab_id: &str,
    snapshot: Value,
) -> AgentChatRecord {
    let now = Utc::now();
    AgentChatRecord {
        chat_id: chat_id.into(),
        tab_id: tab_id.into(),
        workspace_id: workspace_id.into(),
        provider_instance_id: "codex-default".into(),
        provider: "codex".into(),
        native_thread_id: Some("native-thread".into()),
        generation: 1,
        archived: false,
        archived_at: None,
        cursor: 0,
        created_at: now,
        updated_at: now,
        metadata: Some(json!({"creationSource": "desktop"})),
        snapshot,
    }
}

pub(super) fn tab(chat_id: &str, workspace_id: &str, tab_id: &str) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: tab_id.into(),
        workspace_id: workspace_id.into(),
        kind: AGENT_CHAT_TAB_KIND.into(),
        title: "New Chat".into(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "chatId": chat_id,
            "provider": "codex",
            "providerInstanceId": "codex-default",
        }),
    }
}

/// Creates a chat in `workspace_id` with tab `tab_id` and returns its id.
pub(super) async fn create_chat(store: &RuntimeStore, workspace_id: &str, tab_id: &str) -> String {
    let chat_id = new_chat_id();
    let outcome = store
        .create_agent_chat(
            &record(
                &chat_id,
                workspace_id,
                tab_id,
                snapshot(&chat_id, workspace_id, tab_id, 0),
            ),
            &tab(&chat_id, workspace_id, tab_id),
            None,
        )
        .await
        .unwrap();
    assert!(matches!(outcome, AgentChatCreateOutcome::Created(_)));
    chat_id
}

/// The chat's current snapshot header advanced to the next cursor.
pub(super) async fn next_snapshot(store: &RuntimeStore, chat_id: &str) -> (i64, Value) {
    let record = store.agent_chat(chat_id).await.unwrap().unwrap();
    let mut snapshot = record.snapshot;
    snapshot["cursor"] = json!(record.cursor + 1);
    snapshot["items"] = json!([]);
    snapshot.as_object_mut().unwrap().remove("historyBefore");
    (record.cursor, snapshot)
}
