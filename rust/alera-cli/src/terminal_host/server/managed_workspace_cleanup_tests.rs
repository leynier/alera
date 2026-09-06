use std::collections::HashMap;
use std::time::Duration;

use alera_core::runtime::{Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::managed_workspace::{create_managed_workspace, ManagedWorkspaceCreateRequest};
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::session::Session;

use super::actor_test_harness::{local_client, test_actor};
use super::{ServerActor, ServerCommand};

#[path = "managed_workspace_shutdown_retry_tests.rs"]
mod shutdown_retry_tests;

struct Fixture {
    _root: tempfile::TempDir,
    actor: ServerActor,
    responses: UnboundedReceiver<ClientFrame>,
    commands: UnboundedReceiver<ServerCommand>,
    workspace: Workspace,
    events: Vec<Value>,
    fail_shutdown_waits: usize,
}

impl Fixture {
    async fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let repo_path = root.path().join("repo");
        let repo = git2::Repository::init(&repo_path).unwrap();
        let tree_id = repo.index().unwrap().write_tree().unwrap();
        let tree = repo.find_tree(tree_id).unwrap();
        let signature = git2::Signature::now("Test", "test@example.com").unwrap();
        repo.commit(
            Some("refs/heads/main"),
            &signature,
            &signature,
            "initial",
            &tree,
            &[],
        )
        .unwrap();
        repo.set_head("refs/heads/main").unwrap();
        let (handle, responses) = ClientHandle::test_channels();
        let mut actor = test_actor(
            &root,
            HashMap::from([(1, local_client(handle))]),
            HashMap::new(),
        )
        .await;
        let (inbox, commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox;
        let workspace_root = root.path().join("workspaces");
        std::fs::create_dir(&workspace_root).unwrap();
        actor
            .runtime_store
            .set_workspace_directory(Some(&workspace_root.to_string_lossy()))
            .await
            .unwrap();
        let now = Utc::now();
        actor
            .runtime_store
            .upsert_project(Project {
                id: "project".into(),
                name: "Test".into(),
                repo_path: repo_path.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        let workspace = create_managed_workspace(&actor.runtime_store, serde_json::from_value::<ManagedWorkspaceCreateRequest>(json!({
            "id": "workspace", "projectId": "project", "branch": "feature/remove", "sourceBranch": "main", "skipSetup": true,
        })).unwrap()).await.unwrap().workspace;
        for (id, kind) in [("tab-terminal", "terminal"), ("editor", "editor")] {
            actor
                .runtime_store
                .upsert_workspace_tab(WorkspaceTabRecord {
                    id: id.into(),
                    workspace_id: workspace.id.clone(),
                    kind: kind.into(),
                    title: id.into(),
                    created_at: now,
                    updated_at: now,
                    payload: json!({}),
                })
                .await
                .unwrap();
        }
        let mut terminal = Session::driver_test_stub("terminal", 80, 24);
        terminal.append_output(b"retained scrollback");
        actor.sessions.insert("terminal".into(), terminal);
        let mut other = Session::driver_test_stub("other", 80, 24);
        other.workspace_id = "another-workspace".into();
        actor.sessions.insert("other".into(), other);
        Self {
            _root: root,
            actor,
            responses,
            commands,
            workspace,
            events: Vec::new(),
            fail_shutdown_waits: 0,
        }
    }

    async fn request(&mut self, request_type: &str, payload: Value) -> Value {
        self.actor
            .handle_line(
                1,
                json!({"id": 1, "type": request_type, "payload": payload}).to_string(),
            )
            .await;
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                tokio::select! {
                    command = self.commands.recv() => {
                        match command.unwrap() {
                            ServerCommand::PrepareRuntimeMutation { request, completion }
                                if self.fail_shutdown_waits > 0 => {
                                    let mut result = self.actor.prepare_runtime_mutation(&request).await;
                                    if let Ok(shutdown) = &mut result {
                                        shutdown.fail_next_waits(std::mem::take(&mut self.fail_shutdown_waits));
                                    }
                                    let _ = completion.send(result);
                                }
                            command => self.actor.handle(command).await,
                        }
                    },
                    frame = self.responses.recv() => {
                        let response = frame.unwrap().as_json().unwrap();
                        if response["id"] == 1 { return response; }
                        self.events.push(response);
                    }
                }
            }
        })
        .await
        .expect("workspace request should finish")
    }
}

#[tokio::test]
async fn managed_workspace_git_failure_retires_stopped_tabs_and_notifies_clients() {
    let mut fixture = Fixture::new().await;
    let lock = fixture
        ._root
        .path()
        .join("repo/.git/refs/heads/feature/remove.lock");
    std::fs::write(&lock, b"").unwrap();
    let response = fixture
        .request(
            "workspace.removeManaged",
            json!({
                "id": "workspace", "closeSessions": true,
            }),
        )
        .await;
    assert_eq!(response["ok"], false, "{response}");
    assert!(fixture
        .actor
        .runtime_store
        .find_workspace("workspace")
        .await
        .unwrap()
        .is_some());
    let tabs = fixture
        .actor
        .runtime_store
        .list_workspace_tabs("workspace")
        .await
        .unwrap();
    assert_eq!(
        tabs.iter().map(|tab| tab.id.as_str()).collect::<Vec<_>>(),
        ["editor"]
    );
    assert!(!fixture.actor.sessions.contains_key("terminal"));
    assert!(fixture.actor.sessions["other"].running());
    assert!(fixture
        .events
        .iter()
        .any(|value| value["event"] == "workspaceTabsChanged"));
    assert!(!fixture.actor.mutation_queue.has_runtime_mutations());
}

#[tokio::test]
async fn managed_workspace_measurement_allows_confirmed_session_cleanup_without_stopping_work() {
    let mut fixture = Fixture::new().await;
    let response = fixture
        .request(
            "workspace.storageImpact",
            json!({"id": "workspace", "activeWorkspaceId": "workspace", "closeSessions": true}),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert_eq!(response["payload"]["safeToClean"], true, "{response}");
    assert!(fixture.actor.sessions["terminal"].running());
}

#[tokio::test]
async fn managed_workspace_removal_closes_only_owned_sessions_before_deleting_records() {
    let mut fixture = Fixture::new().await;
    let response = fixture
        .request(
            "workspace.removeManaged",
            json!({"id": "workspace", "activeWorkspaceId": "workspace", "closeSessions": true}),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert!(!std::path::Path::new(&fixture.workspace.path).exists());
    assert!(fixture
        .actor
        .runtime_store
        .find_workspace("workspace")
        .await
        .unwrap()
        .is_none());
    assert!(fixture
        .actor
        .runtime_store
        .list_workspace_tabs("workspace")
        .await
        .unwrap()
        .is_empty());
    assert!(!fixture.actor.sessions.contains_key("terminal"));
    assert!(fixture.actor.sessions["other"].running());
    assert!(!fixture.actor.mutation_queue.has_runtime_mutations());
}

#[tokio::test]
async fn managed_workspace_legacy_removal_keeps_live_sessions() {
    let mut fixture = Fixture::new().await;
    let response = fixture
        .request("workspace.removeManaged", json!({"id": "workspace"}))
        .await;
    assert_eq!(response["ok"], false);
    assert!(std::path::Path::new(&fixture.workspace.path).exists());
    assert!(fixture.actor.sessions["terminal"].running());
}

#[tokio::test]
async fn managed_workspace_cleanup_rejects_main_before_stopping_sessions() {
    let mut fixture = Fixture::new().await;
    fixture.workspace.kind = WorkspaceKind::Main;
    fixture
        .actor
        .runtime_store
        .upsert_workspace(fixture.workspace.clone())
        .await
        .unwrap();
    let response = fixture
        .request(
            "workspace.removeManaged",
            json!({"id": "workspace", "closeSessions": true}),
        )
        .await;
    assert_eq!(response["ok"], false);
    assert!(fixture.actor.sessions["terminal"].running());
}

#[tokio::test]
async fn managed_workspace_cleanup_holds_barrier_until_terminal_shutdown_and_deletion_finish() {
    let mut fixture = Fixture::new().await;
    fixture.actor.handle_line(1, json!({"id": 1, "type": "workspace.removeManaged", "payload": {"id": "workspace", "closeSessions": true}}).to_string()).await;
    assert!(fixture.actor.mutation_queue.has_runtime_mutations());
    let prepare = tokio::time::timeout(Duration::from_secs(5), fixture.commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        prepare,
        ServerCommand::PrepareRuntimeMutation { .. }
    ));
    fixture.actor.handle(prepare).await;
    assert!(!fixture.actor.sessions.contains_key("terminal"));
    assert!(fixture.actor.mutation_queue.has_runtime_mutations());
    let completion = tokio::time::timeout(Duration::from_secs(5), fixture.commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        completion,
        ServerCommand::RuntimeMutationFinished(_)
    ));
    fixture.actor.handle(completion).await;
    assert!(!fixture.actor.mutation_queue.has_runtime_mutations());
}
