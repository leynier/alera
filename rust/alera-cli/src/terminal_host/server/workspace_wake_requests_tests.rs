use std::collections::HashMap;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::orchestration::agent_session_resume::{
    AGENT_NATIVE_SESSION_AGENT_KEY, AGENT_NATIVE_SESSION_ID_KEY,
};
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::server::terminal_launch_defaults::default_terminal_launch;
use crate::terminal_host::server::terminal_spawn_command::resumed_initial_command;
use crate::terminal_host::server::{ServerActor, ServerCommand, ServerInboxReceiver};
use crate::terminal_host::session::Session;

async fn actor_with_workspace(dir: &tempfile::TempDir, host_id: &str) -> ServerActor {
    let (handle, _) = ClientHandle::test_channels();
    let actor = test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    let path = dir.path().to_string_lossy().to_string();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: path.clone(),
            kind: ProjectKind::Folder,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "w".into(),
            instance_id: "w-instance".into(),
            host_id: host_id.into(),
            project_id: "project".into(),
            name: "Task".into(),
            branch: None,
            path,
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: vec![],
            tag_names: vec![],
            section_id: None,
            parent_workspace_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    for (tab, session) in [("tab-1", "s-1"), ("tab-2", "s-2")] {
        actor
            .runtime_store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: tab.into(),
                workspace_id: "w".into(),
                kind: "terminal".into(),
                title: tab.into(),
                created_at: now,
                updated_at: now,
                payload: json!({ "terminalSessionId": session }),
            })
            .await
            .unwrap();
    }
    actor
}

fn live_session(id: &str, tab_id: &str) -> Session {
    let mut session = Session::driver_test_stub(id, 80, 24);
    session.workspace_id = "w".into();
    session.tab_id = tab_id.into();
    session
}

#[tokio::test]
async fn waking_attaches_every_slept_terminal_and_clears_the_sleep() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;
    actor
        .runtime_store
        .record_workspace_sleep("w")
        .await
        .unwrap();
    // A terminal closed after the sleep has nothing to start.
    actor
        .runtime_store
        .remove_workspace_tab("tab-2")
        .await
        .unwrap();
    actor
        .sessions
        .insert("s-1".into(), live_session("s-1", "tab-1"));

    let woken = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();

    assert_eq!(woken["wasAsleep"], true);
    assert_eq!(
        woken["woken"],
        json!([{ "tabId": "tab-1", "sessionId": "s-1" }])
    );
    assert_eq!(woken["failed"], json!([]));
    assert!(
        !actor.sessions["s-1"].clients.contains(&1),
        "the waking client does not stay attached"
    );
    assert!(actor
        .runtime_store
        .list_slept_workspace_tabs()
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn an_awake_workspace_has_nothing_to_wake() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;

    let woken = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();

    assert_eq!(woken["wasAsleep"], false);
    assert_eq!(woken["woken"], json!([]));
    assert!(actor.sessions.is_empty());
}

#[tokio::test]
async fn unknown_and_remote_workspaces_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "ssh-lab").await;

    let remote = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap_err();
    assert!(remote.to_string().contains("SSH host"), "{remote}");
    let missing = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "nope" }))
        .await
        .unwrap_err();
    assert!(missing.to_string().contains("not found"), "{missing}");
}

async fn set_tab_payload(actor: &ServerActor, tab_id: &str, payload: serde_json::Value) {
    let mut tab = actor
        .runtime_store
        .find_workspace_tab(tab_id)
        .await
        .unwrap()
        .unwrap();
    tab.payload = payload;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
}

/// The startup line the host types into a session, or `None` when nothing
/// is typed within the wait.
async fn startup_input(
    actor: &mut ServerActor,
    events: &mut ServerInboxReceiver,
    session_id: &str,
) -> Option<String> {
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(5);
    while let Ok(Some(event)) = tokio::time::timeout_at(deadline, events.recv()).await {
        if let ServerCommand::TerminalStartupInput {
            session_id: target,
            command,
            ..
        } = &event
        {
            if target == session_id {
                return Some(command.clone());
            }
        }
        actor.handle(event).await;
    }
    None
}

/// Sleeps the workspace with only `tab-1` left, wakes it and returns the line
/// typed into its new session.
async fn wake_and_capture_startup(actor: &mut ServerActor) -> Option<String> {
    actor
        .runtime_store
        .record_workspace_sleep("w")
        .await
        .unwrap();
    actor
        .runtime_store
        .remove_workspace_tab("tab-2")
        .await
        .unwrap();
    let (inbox, mut events) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;

    let woken = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();
    assert_eq!(
        woken["woken"],
        json!([{ "tabId": "tab-1", "sessionId": "s-1" }])
    );
    assert!(actor.sessions["s-1"].running());
    let typed = startup_input(actor, &mut events, "s-1").await;
    stop_session(actor, "s-1").await;
    typed
}

#[tokio::test]
async fn waking_a_slept_command_tab_types_its_command() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;
    set_tab_payload(
        &actor,
        "tab-1",
        json!({ "terminalSessionId": "s-1", "initialCommand": "echo woken-command" }),
    )
    .await;

    let typed = wake_and_capture_startup(&mut actor).await;

    assert_eq!(typed.as_deref(), Some("echo woken-command"));
}

#[tokio::test]
async fn waking_a_slept_agent_tab_resumes_its_reported_conversation() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;
    set_tab_payload(
        &actor,
        "tab-1",
        json!({
            "terminalSessionId": "s-1",
            "initialCommand": "claude",
            AGENT_NATIVE_SESSION_ID_KEY: "sess-1",
            AGENT_NATIVE_SESSION_AGENT_KEY: "claude",
        }),
    )
    .await;
    let tab = actor
        .runtime_store
        .find_workspace_tab("tab-1")
        .await
        .unwrap()
        .unwrap();
    let path = dir.path().to_string_lossy().to_string();
    let shell = default_terminal_launch(&path, actor.config.login_shell)
        .await
        .interactive_shell;
    // The resume form an app types when it attaches the slept tab.
    let app_line = resumed_initial_command(&tab, &shell).unwrap().unwrap();

    let typed = wake_and_capture_startup(&mut actor).await;

    assert_eq!(typed.as_deref(), Some(app_line.as_str()));
    assert!(app_line.contains("sess-1"));
}

#[tokio::test]
async fn waking_does_not_retype_into_a_terminal_still_running() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;
    set_tab_payload(
        &actor,
        "tab-1",
        json!({ "terminalSessionId": "s-1", "initialCommand": "echo again" }),
    )
    .await;
    actor
        .runtime_store
        .record_workspace_sleep("w")
        .await
        .unwrap();
    actor
        .sessions
        .insert("s-1".into(), live_session("s-1", "tab-1"));
    let (inbox, mut events) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;

    actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();

    assert!(actor.sessions.contains_key("s-2"), "the plain tab started");
    assert_eq!(startup_input(&mut actor, &mut events, "s-1").await, None);
    stop_session(&mut actor, "s-2").await;
}

/// Kills a PTY a test started. The test owns the inbox and stops draining
/// it, so the history flush of a full termination would wait forever.
async fn stop_session(actor: &mut ServerActor, session_id: &str) {
    if let Some(mut session) = actor.sessions.remove(session_id) {
        session.terminate(true, &actor.store).await;
    }
}
