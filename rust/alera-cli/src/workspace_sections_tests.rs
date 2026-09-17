use super::*;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY,
};
use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::{TimeZone, Utc};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

fn section(id: &str, name: &str) -> WorkspaceSection {
    let now = Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap();
    WorkspaceSection {
        id: id.to_string(),
        name: name.to_string(),
        created_at: now,
        updated_at: now,
    }
}

#[test]
fn resolve_section_id_matches_unique_names_case_insensitively() {
    let sections = vec![section("a", "Alera"), section("b", "Mobile")];
    assert_eq!(resolve_section_id(&sections, "alera").unwrap(), "a");
    assert_eq!(resolve_section_id(&sections, " Alera ").unwrap(), "a");
    assert_eq!(resolve_section_id(&sections, "MOBILE").unwrap(), "b");
}

#[test]
fn resolve_section_id_fails_closed_for_missing_empty_and_ambiguous_names() {
    let sections = vec![section("a", "Alera"), section("b", "alera")];
    assert!(resolve_section_id(&sections, "missing")
        .unwrap_err()
        .to_string()
        .contains("No workspace section named missing"));
    assert!(resolve_section_id(&sections, "  ")
        .unwrap_err()
        .to_string()
        .contains("cannot be empty"));
    assert!(resolve_section_id(&sections, "ALERA")
        .unwrap_err()
        .to_string()
        .contains("ambiguous"));
}

#[test]
fn require_section_id_fails_closed_for_missing_and_empty_ids() {
    let sections = vec![section("sec-alera", "Alera")];
    assert_eq!(
        require_section_id(&sections, "sec-alera").unwrap(),
        "sec-alera"
    );
    assert!(require_section_id(&sections, "missing")
        .unwrap_err()
        .to_string()
        .contains("No workspace section with id missing"));
    assert!(require_section_id(&sections, "  ")
        .unwrap_err()
        .to_string()
        .contains("cannot be empty"));
}

#[test]
fn clear_payload_sends_null_section_id() {
    assert_eq!(
        set_for_workspace_payload("workspace-1", None),
        json!({ "workspaceId": "workspace-1", "sectionId": null })
    );
    assert_eq!(
        set_for_workspace_payload("workspace-1", Some("section-1")),
        json!({ "workspaceId": "workspace-1", "sectionId": "section-1" })
    );
}

fn project(id: &str) -> Project {
    let now = Utc::now();
    Project {
        id: id.to_string(),
        name: id.to_string(),
        repo_path: format!("/tmp/{id}"),
        created_at: now,
        updated_at: now,
        kind: ProjectKind::GitRepository,
    }
}

fn workspace(id: &str, project_id: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: project_id.to_string(),
        name: id.to_string(),
        branch: Some("main".to_string()),
        path: format!("/tmp/{project_id}/{id}"),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
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
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    store.upsert_workspace(workspace("b", "p")).await.unwrap();
    dir
}

async fn host_server(
    sequence: Vec<(&'static str, Value, Value)>,
) -> (tempfile::TempDir, tokio::task::JoinHandle<()>) {
    let directory = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::write(
        directory.path().join("host.json"),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "fixture-token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                RUNTIME_HOST_WORKSPACE_SECTIONS_CAPABILITY
            ]
        }))
        .unwrap(),
    )
    .unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        for (expected, payload, response) in
            std::iter::once(("hello", json!({}), json!({}))).chain(sequence)
        {
            let line = lines.next_line().await.unwrap().unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(request["type"], expected);
            if expected != "hello" {
                assert_eq!(request["payload"], payload);
            }
            let frame = json!({"id": request["id"], "ok": true, "payload": response});
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
    });
    (directory, server)
}

#[tokio::test]
async fn store_backend_is_used_when_no_host_is_connected() {
    let dir = seeded_store().await;
    let mut backend = Backend::open(dir.path()).await.unwrap();
    assert!(matches!(backend, Backend::Store(_)));
    let created = backend.create("Alera", "a").await.unwrap();
    assert_eq!(created.name, "Alera");
    backend.set("b", Some(&created.id)).await.unwrap();
    backend.set("a", None).await.unwrap();
    let listed = backend.list().await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, created.id);
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(store.workspace_section_id("a").await.unwrap(), None);
    assert_eq!(
        store.workspace_section_id("b").await.unwrap(),
        Some(created.id)
    );
}

#[tokio::test]
async fn host_backend_prefers_live_rpc_and_sends_null_on_clear() {
    let listed = json!([{
        "id": "sec-alera",
        "name": "Alera",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
    }]);
    let (dir, server) = host_server(vec![
        ("workspaceSection.list", json!({}), listed),
        (
            "workspaceSection.setForWorkspace",
            json!({"workspaceId": "w", "sectionId": "sec-alera"}),
            json!({}),
        ),
        (
            "workspaceSection.setForWorkspace",
            json!({"workspaceId": "w", "sectionId": null}),
            json!({}),
        ),
    ])
    .await;
    let mut backend = Backend::open(dir.path()).await.unwrap();
    assert!(matches!(backend, Backend::Host(_)));
    let sections = backend.list().await.unwrap();
    let section_id = resolve_section_id(&sections, "alera").unwrap();
    assert_eq!(section_id, "sec-alera");
    backend.set("w", Some(&section_id)).await.unwrap();
    backend.set("w", None).await.unwrap();
    drop(backend);
    server.await.unwrap();
}

#[tokio::test]
async fn resolve_optional_section_id_checks_ids_against_the_live_list() {
    let listed = json!([{
        "id": "sec-alera",
        "name": "Alera",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z"
    }]);
    let (dir, server) = host_server(vec![
        ("workspaceSection.list", json!({}), listed.clone()),
        ("workspaceSection.list", json!({}), listed),
    ])
    .await;
    let mut client = RuntimeHostRpcClient::connect(dir.path())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        resolve_optional_section_id(&mut client, None, Some("sec-alera"))
            .await
            .unwrap()
            .as_deref(),
        Some("sec-alera")
    );
    let error = resolve_optional_section_id(&mut client, None, Some("missing"))
        .await
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("No workspace section with id missing"),
        "{error}"
    );
    drop(client);
    server.await.unwrap();
}
