use std::collections::HashMap;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use super::super::actor_test_harness::{mobile_client, test_actor};
use super::super::{ClientFrame, ClientHandle, ClientState, ServerActor};
use super::WORKSPACE_FOCUS_REQUESTED_EVENT;
use crate::terminal_host::protocol::PROTOCOL_VERSION;

const CLI: u64 = 1;
const APP: u64 = 2;
const LEGACY_APP: u64 = 3;
const PHONE: u64 = 4;

fn workspace(id: &str, archived: bool) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: "project".to_string(),
        name: format!("Workspace {id}"),
        branch: Some("main".to_string()),
        path: format!("/tmp/project/{id}"),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: archived,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

async fn seed(actor: &ServerActor) {
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".to_string(),
            name: "project".to_string(),
            repo_path: "/tmp/project".to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    for record in [workspace("live", false), workspace("shelved", true)] {
        actor.runtime_store.upsert_workspace(record).await.unwrap();
    }
}

struct Fixture {
    _dir: tempfile::TempDir,
    actor: ServerActor,
    frames: HashMap<u64, UnboundedReceiver<ClientFrame>>,
}

/// One CLI plus whichever of the other clients a test names.
async fn fixture(with: &[u64]) -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let mut frames = HashMap::new();
    for id in std::iter::once(CLI).chain(with.iter().copied()) {
        let (handle, rx) = ClientHandle::test_channels();
        let client = match id {
            APP => ClientState::local(handle, true),
            LEGACY_APP => {
                let mut legacy = ClientState::local(handle, true);
                legacy.workspace_focus = false;
                legacy
            }
            PHONE => mobile_client(handle, "phone"),
            _ => ClientState::local(handle, false),
        };
        clients.insert(id, client);
        frames.insert(id, rx);
    }
    let actor = test_actor(&dir, clients, HashMap::new()).await;
    seed(&actor).await;
    Fixture {
        _dir: dir,
        actor,
        frames,
    }
}

fn events(frames: &mut UnboundedReceiver<ClientFrame>) -> Vec<Value> {
    let mut seen = Vec::new();
    while let Ok(frame) = frames.try_recv() {
        if let Some(value) = frame.as_json() {
            seen.push(value);
        }
    }
    seen
}

async fn focus(fixture: &mut Fixture, from: u64, workspace_id: &str) -> Result<Value, String> {
    fixture
        .actor
        .handle_request(
            from,
            "workspace.focus",
            &json!({ "workspaceId": workspace_id }),
        )
        .await
        .map_err(|error| error.to_string())
}

#[tokio::test]
async fn focus_reaches_only_desktop_apps_that_handle_it() {
    let mut fixture = fixture(&[APP, LEGACY_APP, PHONE]).await;

    let result = focus(&mut fixture, CLI, "live").await.unwrap();

    assert_eq!(
        result,
        json!({
            "workspaceId": "live",
            "projectId": "project",
            "name": "Workspace live",
            "appClients": 1,
        })
    );
    let app_events = events(fixture.frames.get_mut(&APP).unwrap());
    assert_eq!(
        app_events,
        vec![json!({
            "event": WORKSPACE_FOCUS_REQUESTED_EVENT,
            "payload": {"workspaceId": "live", "projectId": "project"},
        })]
    );
    for silent in [CLI, LEGACY_APP, PHONE] {
        assert!(
            events(fixture.frames.get_mut(&silent).unwrap()).is_empty(),
            "client {silent} must not receive the focus request"
        );
    }
}

#[tokio::test]
async fn focus_fails_when_no_desktop_app_is_connected() {
    let mut fixture = fixture(&[PHONE]).await;

    let error = focus(&mut fixture, CLI, "live").await.unwrap_err();

    assert!(
        error.contains("No Alera desktop app is connected"),
        "{error}"
    );
}

#[tokio::test]
async fn focus_asks_for_an_update_when_the_app_cannot_handle_it() {
    let mut fixture = fixture(&[LEGACY_APP]).await;

    let error = focus(&mut fixture, CLI, "live").await.unwrap_err();

    assert!(
        error.contains("does not support workspace focus"),
        "{error}"
    );
    assert!(events(fixture.frames.get_mut(&LEGACY_APP).unwrap()).is_empty());
}

#[tokio::test]
async fn focus_rejects_unknown_and_archived_workspaces_without_delivering() {
    let mut fixture = fixture(&[APP]).await;

    let missing = focus(&mut fixture, CLI, "missing").await.unwrap_err();
    let archived = focus(&mut fixture, CLI, "shelved").await.unwrap_err();
    let blank = fixture
        .actor
        .handle_request(CLI, "workspace.focus", &json!({}))
        .await
        .unwrap_err()
        .to_string();

    assert!(
        missing.contains("Workspace not found: missing"),
        "{missing}"
    );
    assert!(archived.contains("is archived"), "{archived}");
    assert!(blank.contains("workspaceId"), "{blank}");
    assert!(events(fixture.frames.get_mut(&APP).unwrap()).is_empty());
}

#[tokio::test]
async fn phones_cannot_focus_the_desktop() {
    let mut fixture = fixture(&[APP, PHONE]).await;

    let error = focus(&mut fixture, PHONE, "live").await.unwrap_err();

    assert!(error.contains("Mobile clients cannot call"), "{error}");
    assert!(events(fixture.frames.get_mut(&APP).unwrap()).is_empty());
}

#[tokio::test]
async fn hello_enables_focus_only_for_an_app_that_announces_it() {
    let mut fixture = fixture(&[]).await;
    let hello = |kind: &str, announces: bool| {
        json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": "token",
            "clientKind": kind,
            "sharedCheckoutWorkspacesV1": true,
            "workspaceFocusV1": announces,
        })
    };

    fixture
        .actor
        .handle_hello(CLI, &hello("cli", true))
        .unwrap();
    assert!(!fixture.actor.clients[&CLI].workspace_focus);
    fixture
        .actor
        .handle_hello(CLI, &hello("app", false))
        .unwrap();
    assert!(!fixture.actor.clients[&CLI].workspace_focus);
    fixture
        .actor
        .handle_hello(CLI, &hello("app", true))
        .unwrap();
    assert!(fixture.actor.clients[&CLI].workspace_focus);
}
