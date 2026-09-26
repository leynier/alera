use super::*;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
};
use alera_core::runtime::{Project, ProjectKind, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID};
use chrono::Utc;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

fn workspace(id: &str, name: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: "p".to_string(),
        name: name.to_string(),
        branch: Some("main".to_string()),
        path: format!("/tmp/p/{id}"),
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
    }
}

async fn seeded_store() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "p".to_string(),
            name: "p".to_string(),
            repo_path: "/tmp/p".to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(workspace("a", "Old name"))
        .await
        .unwrap();
    dir
}

#[tokio::test]
async fn store_fallback_renames_and_trims_without_a_host() {
    let dir = seeded_store().await;
    let renamed = rename(dir.path(), "a", "  New name  ").await.unwrap();
    assert_eq!(renamed.name, "New name");
    assert_eq!(renamed.branch.as_deref(), Some("main"));
    assert_eq!(renamed.path, "/tmp/p/a");
    let stored = RuntimeStore::open(dir.path())
        .await
        .unwrap()
        .find_workspace("a")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stored.name, "New name");
}

#[tokio::test]
async fn rejects_empty_names_and_unknown_workspaces() {
    let dir = seeded_store().await;
    let error = rename(dir.path(), "a", "   ").await.unwrap_err();
    assert!(error.to_string().contains("cannot be empty"), "{error}");
    let error = rename(dir.path(), "missing", "Name").await.unwrap_err();
    assert!(
        error.to_string().contains("Workspace not found: missing"),
        "{error}"
    );
}

#[tokio::test]
async fn live_host_receives_workspace_rename_with_trimmed_name() {
    let dir = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::write(
        dir.path().join("host.json"),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "fixture-token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY
            ]
        }))
        .unwrap(),
    )
    .unwrap();
    let response = serde_json::to_value(workspace("w", "Renamed")).unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        for expected in ["hello", "workspace.rename"] {
            let line = lines.next_line().await.unwrap().unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(request["type"], expected);
            let payload = if expected == "hello" {
                json!({})
            } else {
                assert_eq!(
                    request["payload"],
                    json!({ "workspaceId": "w", "name": "Renamed" })
                );
                response.clone()
            };
            let frame = json!({"id": request["id"], "ok": true, "payload": payload});
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
    });
    let renamed = rename(dir.path(), "w", " Renamed ").await.unwrap();
    assert_eq!(renamed.name, "Renamed");
    server.await.unwrap();
}
