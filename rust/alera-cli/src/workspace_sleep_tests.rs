use super::*;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
};
use alera_core::runtime::{Project, ProjectKind, WorkspaceKind};
use chrono::Utc;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

fn workspace(id: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: "p".to_string(),
        name: id.to_string(),
        branch: Some(format!("feat/{id}")),
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

fn tab(id: &str, workspace_id: &str, kind: &str) -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: id.to_string(),
        workspace_id: workspace_id.to_string(),
        kind: kind.to_string(),
        title: id.to_string(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({}),
    }
}

/// Two workspaces of one project: `a` with two terminals and an editor, `b`
/// with one terminal that a sleep of `a` must leave alone.
async fn seeded_store() -> (tempfile::TempDir, RuntimeStore) {
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
    for id in ["a", "b"] {
        store.upsert_workspace(workspace(id)).await.unwrap();
    }
    for record in [
        tab("a-term-1", "a", "terminal"),
        tab("a-term-2", "a", "terminal"),
        tab("a-editor", "a", "editor"),
        tab("b-term", "b", "terminal"),
    ] {
        store.upsert_workspace_tab(record).await.unwrap();
    }
    (dir, store)
}

#[tokio::test]
async fn store_fallback_records_only_the_target_terminals_and_keeps_everything_else() {
    let (dir, store) = seeded_store().await;

    let outcome = sleep(dir.path(), " a ", None).await.unwrap();

    assert!(!outcome.runtime_host);
    assert_eq!(outcome.workspace.id, "a");
    assert_eq!(outcome.slept_tab_ids, vec!["a-term-1", "a-term-2"]);
    let slept = store.list_slept_workspace_tabs().await.unwrap();
    assert_eq!(slept.len(), 1, "{slept:?}");
    assert_eq!(slept["a"], vec!["a-term-1", "a-term-2"]);
    // Sleep is neither archive nor remove: the record, branch, path, and every
    // tab stay, and the workspace stays visible.
    let stored = store.find_workspace("a").await.unwrap().unwrap();
    assert!(!stored.is_archived);
    assert_eq!(stored.status, WorkspaceStatus::Active);
    assert_eq!(stored.branch.as_deref(), Some("feat/a"));
    assert_eq!(stored.path, "/tmp/p/a");
    assert_eq!(store.list_workspace_tabs("a").await.unwrap().len(), 3);
    assert_eq!(store.list_workspace_tabs("b").await.unwrap().len(), 1);
    assert!(store
        .list_workspaces("p")
        .await
        .unwrap()
        .iter()
        .any(|workspace| workspace.id == "a"));
}

#[tokio::test]
async fn store_fallback_sleeps_a_workspace_without_terminals() {
    let (dir, store) = seeded_store().await;
    store.upsert_workspace(workspace("empty")).await.unwrap();

    let outcome = sleep(dir.path(), "empty", None).await.unwrap();

    assert!(outcome.slept_tab_ids.is_empty());
    assert!(!store
        .list_slept_workspace_tabs()
        .await
        .unwrap()
        .contains_key("empty"));
}

#[tokio::test]
async fn rejects_missing_unknown_archived_and_removed_workspaces() {
    let (dir, store) = seeded_store().await;
    let mut archived = workspace("archived");
    archived.is_archived = true;
    store.upsert_workspace(archived).await.unwrap();
    let mut removed = workspace("removed");
    removed.status = WorkspaceStatus::Removed;
    store.upsert_workspace(removed).await.unwrap();

    for (id, expected) in [
        ("  ", "--id cannot be empty"),
        ("missing", "Workspace not found: missing"),
        ("archived", "is archived"),
        ("removed", "Workspace is not active: removed"),
    ] {
        let error = sleep(dir.path(), id, None).await.unwrap_err();
        assert!(error.to_string().contains(expected), "{id}: {error}");
    }
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
}

#[tokio::test]
async fn refuses_to_sleep_the_workspace_of_the_calling_terminal() {
    let (dir, store) = seeded_store().await;

    let error = sleep(dir.path(), "a", Some("a")).await.unwrap_err();

    assert!(
        error.to_string().contains("from one of its own terminals"),
        "{error}"
    );
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
    let outcome = sleep(dir.path(), "b", Some("a")).await.unwrap();
    assert_eq!(outcome.slept_tab_ids, vec!["b-term"]);
}

#[tokio::test]
async fn a_live_host_that_does_not_answer_blocks_the_store_fallback() {
    let (dir, store) = seeded_store().await;
    // This test process stands in for a host that owns the directory but
    // whose control file is missing.
    let _owner =
        crate::terminal_host::runtime_owner::RuntimeOwnerGuard::acquire(dir.path()).unwrap();

    let error = sleep(dir.path(), "a", None).await.unwrap_err();

    assert!(error.to_string().contains("did not answer"), "{error}");
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
}

#[tokio::test]
async fn store_fallback_refuses_a_workspace_on_an_ssh_host() {
    let (dir, store) = seeded_store().await;
    let mut remote = workspace("remote");
    remote.host_id = "ssh-target-1".to_string();
    store.upsert_workspace(remote).await.unwrap();

    let error = sleep(dir.path(), "remote", None).await.unwrap_err();

    assert!(
        error.to_string().contains("SSH host ssh-target-1"),
        "{error}"
    );
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
}

fn write_control_file(dir: &Path, port: u16) {
    std::fs::write(
        dir.join("host.json"),
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
}

/// Answers each request with the payload `respond` returns and records the
/// verbs it saw, so a test can assert the exact host conversation.
async fn fake_host(
    dir: &Path,
    respond: impl Fn(&str, &Value) -> Value + Send + 'static,
) -> tokio::task::JoinHandle<Vec<String>> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    write_control_file(dir, listener.local_addr().unwrap().port());
    tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        let mut verbs = Vec::new();
        while let Ok(Some(line)) = lines.next_line().await {
            let request: Value = serde_json::from_str(&line).unwrap();
            let verb = request["type"].as_str().unwrap().to_string();
            let payload = respond(&verb, &request["payload"]);
            verbs.push(verb);
            let frame = json!({"id": request["id"], "ok": true, "payload": payload});
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
        verbs
    })
}

#[tokio::test]
async fn live_host_receives_workspace_sleep_and_reports_its_terminals() {
    let dir = tempfile::tempdir().unwrap();
    let server = fake_host(dir.path(), |verb, payload| match verb {
        "workspace.find" => {
            assert_eq!(payload, &json!({"id": "a"}));
            serde_json::to_value(workspace("a")).unwrap()
        }
        "tab.list" => {
            assert_eq!(payload, &json!({"workspaceId": "a"}));
            json!([
                tab("a-term", "a", "terminal"),
                tab("a-editor", "a", "editor")
            ])
        }
        "workspace.sleep" => {
            assert_eq!(payload, &json!({"workspaceId": "a"}));
            json!({})
        }
        // A terminal another client opened after `tab.list` was slept too.
        "workspace.sleptTabs" => json!({"a": ["a-term", "a-late"], "b": ["b-term"]}),
        _ => json!({}),
    })
    .await;

    let outcome = sleep(dir.path(), "a", None).await.unwrap();

    assert!(outcome.runtime_host);
    assert_eq!(outcome.slept_tab_ids, vec!["a-term", "a-late"]);
    assert_eq!(
        server.await.unwrap(),
        vec![
            "hello",
            "workspace.find",
            "tab.list",
            "workspace.sleep",
            "workspace.sleptTabs"
        ]
    );
}

#[tokio::test]
async fn live_host_never_receives_a_sleep_for_an_unknown_archived_or_remote_workspace() {
    for (id, expected) in [
        ("missing", "Workspace not found"),
        ("archived", "is archived"),
        ("remote", "SSH host ssh-target-1"),
    ] {
        let dir = tempfile::tempdir().unwrap();
        let server = fake_host(dir.path(), |verb, payload| match verb {
            "workspace.find" if payload["id"] == "archived" => {
                let mut archived = workspace("archived");
                archived.is_archived = true;
                serde_json::to_value(archived).unwrap()
            }
            "workspace.find" if payload["id"] == "remote" => {
                let mut remote = workspace("remote");
                remote.host_id = "ssh-target-1".to_string();
                serde_json::to_value(remote).unwrap()
            }
            "workspace.find" => Value::Null,
            _ => json!({}),
        })
        .await;

        let error = sleep(dir.path(), id, None).await.unwrap_err();

        assert!(error.to_string().contains(expected), "{id}: {error}");
        assert_eq!(server.await.unwrap(), vec!["hello", "workspace.find"]);
    }
}

#[tokio::test]
async fn a_host_that_stops_answering_after_the_sleep_still_completes() {
    let dir = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    write_control_file(dir.path(), listener.local_addr().unwrap().port());
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let request: Value = serde_json::from_str(&line).unwrap();
            let payload = match request["type"].as_str().unwrap() {
                "workspace.find" => serde_json::to_value(workspace("a")).unwrap(),
                "tab.list" => json!([tab("a-term", "a", "terminal")]),
                // Keeps the socket open without answering.
                "workspace.sleptTabs" => continue,
                _ => json!({}),
            };
            let frame = json!({"id": request["id"], "ok": true, "payload": payload});
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
    });

    let outcome = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        sleep(dir.path(), "a", None),
    )
    .await
    .expect("the follow-up must not block the command")
    .unwrap();

    assert_eq!(outcome.slept_tab_ids, vec!["a-term"]);
    server.abort();
}

#[tokio::test]
async fn a_host_that_stops_answering_before_the_sleep_fails_without_hanging() {
    let listener_dir = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    write_control_file(listener_dir.path(), listener.local_addr().unwrap().port());
    let silent = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let request: Value = serde_json::from_str(&line).unwrap();
            // Only the handshake is answered.
            if request["type"] != "hello" {
                continue;
            }
            let frame = json!({"id": request["id"], "ok": true, "payload": {}});
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
    });

    let error = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        sleep(listener_dir.path(), "a", None),
    )
    .await
    .expect("an unanswered lookup must not hang the command")
    .unwrap_err();

    assert!(error.to_string().contains("workspace.find"), "{error}");
    silent.abort();
}
