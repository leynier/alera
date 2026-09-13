use std::collections::HashMap;
use std::time::Duration;

use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_prompt_injection::{
    build_agent_prompt_paste_bytes, AGENT_PROMPT_SUBMIT,
};
use crate::terminal_host::session::Session;

use super::super::actor_test_harness::{local_client, test_actor};
use super::{
    handoff_chdir_bytes, handoff_notify_message, path_is_same_or_within, WorkspaceHandoffDirection,
};

fn recv_write(
    rx: &std::sync::mpsc::Receiver<crate::terminal_host::session::TestQueuedWrite>,
) -> crate::terminal_host::session::TestQueuedWrite {
    rx.recv_timeout(Duration::from_secs(1))
        .expect("expected a queued terminal write")
}

#[test]
fn notify_message_names_both_directions_with_paths() {
    assert_eq!(
        handoff_notify_message(
            WorkspaceHandoffDirection::HandOff,
            "/repo",
            "/worktrees/feat",
        ),
        "hand off happened: /repo → /worktrees/feat"
    );
    assert_eq!(
        handoff_notify_message(
            WorkspaceHandoffDirection::HandOn,
            "/worktrees/feat",
            "/repo",
        ),
        "hand on happened: /worktrees/feat → /repo"
    );
}

#[test]
fn chdir_bytes_target_the_destination_path() {
    let bytes = handoff_chdir_bytes("/repo's root");
    let text = String::from_utf8(bytes).unwrap();
    #[cfg(windows)]
    {
        assert!(text.starts_with("cd /d "), "{text}");
        assert!(
            text.contains("/repo's root") || text.contains("repo's root"),
            "{text}"
        );
        assert!(text.ends_with('\r'), "{text}");
    }
    #[cfg(not(windows))]
    {
        assert_eq!(text, "cd '/repo'\\''s root' || true\r");
    }
}

#[test]
fn path_is_same_or_within_matches_the_workspace_root_and_children() {
    assert!(path_is_same_or_within("/repo", "/repo"));
    assert!(path_is_same_or_within("/repo/src", "/repo"));
    assert!(!path_is_same_or_within("/repo-other", "/repo"));
    assert!(!path_is_same_or_within("/elsewhere", "/repo"));
}

#[tokio::test]
async fn hand_off_chdirs_a_live_shell_and_skips_a_dead_pty() {
    let dir = tempfile::tempdir().unwrap();
    let mut live = Session::driver_test_stub("live", 80, 24);
    live.workspace_id = "main".into();
    live.working_directory = "/repo".into();
    let live_rx = live.attach_test_input();
    let mut dead = Session::driver_test_stub("dead", 80, 24);
    dead.workspace_id = "main".into();
    dead.working_directory = "/repo".into();
    dead.mark_exited_for_test();
    let mut other = Session::driver_test_stub("other", 80, 24);
    other.workspace_id = "elsewhere".into();
    other.working_directory = "/elsewhere".into();
    let other_rx = other.attach_test_input();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([
            ("live".into(), live),
            ("dead".into(), dead),
            ("other".into(), other),
        ]),
    )
    .await;

    actor.relocate_sessions_after_handoff(
        WorkspaceHandoffDirection::HandOff,
        "main",
        "child",
        "/repo",
        "/worktrees/feat",
    );

    let write = recv_write(&live_rx);
    assert_eq!(write.bytes, handoff_chdir_bytes("/worktrees/feat"));
    assert!(write.deferred_bytes.is_none());
    assert!(other_rx.try_recv().is_err());
    assert_eq!(
        actor.sessions.get("live").unwrap().working_directory,
        "/worktrees/feat"
    );
    assert_eq!(
        actor.sessions.get("dead").unwrap().working_directory,
        "/worktrees/feat"
    );
}

#[tokio::test]
async fn hand_off_notifies_an_awake_agent_instead_of_sending_cd() {
    let dir = tempfile::tempdir().unwrap();
    let mut agent = Session::driver_test_stub("agent", 80, 24);
    agent.workspace_id = "main".into();
    agent.working_directory = "/repo".into();
    let agent_rx = agent.attach_test_input();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("agent".into(), agent)]),
    )
    .await;
    actor
        .agent_presence
        .update("agent", "claude".into(), AgentPresenceState::Working);

    actor.relocate_sessions_after_handoff(
        WorkspaceHandoffDirection::HandOff,
        "main",
        "child",
        "/repo",
        "/worktrees/feat",
    );

    let write = recv_write(&agent_rx);
    let expected = handoff_notify_message(
        WorkspaceHandoffDirection::HandOff,
        "/repo",
        "/worktrees/feat",
    );
    assert_eq!(write.bytes, build_agent_prompt_paste_bytes(&expected));
    assert!(write.deferred_bytes.is_none());
    assert_eq!(
        actor.sessions.get("agent").unwrap().working_directory,
        "/worktrees/feat"
    );
}

#[tokio::test]
async fn hand_on_moves_only_source_owned_sessions() {
    let dir = tempfile::tempdir().unwrap();
    let mut child_shell = Session::driver_test_stub("child-shell", 80, 24);
    child_shell.workspace_id = "child".into();
    child_shell.working_directory = "/worktrees/feat".into();
    let child_rx = child_shell.attach_test_input();
    let mut main_after_hand_off = Session::driver_test_stub("main-shell", 80, 24);
    main_after_hand_off.workspace_id = "main".into();
    main_after_hand_off.working_directory = "/worktrees/feat".into();
    let main_rx = main_after_hand_off.attach_test_input();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([
            ("child-shell".into(), child_shell),
            ("main-shell".into(), main_after_hand_off),
        ]),
    )
    .await;

    actor.relocate_sessions_after_hand_on("child", "main", "/worktrees/feat", "/repo");

    assert_eq!(recv_write(&child_rx).bytes, handoff_chdir_bytes("/repo"));
    assert!(main_rx.try_recv().is_err());
    assert_eq!(actor.sessions["child-shell"].workspace_id, "main");
}

#[tokio::test]
async fn hand_on_notifies_an_idle_agent_with_deferred_enter() {
    let dir = tempfile::tempdir().unwrap();
    let mut agent = Session::driver_test_stub("agent", 80, 24);
    agent.workspace_id = "child".into();
    agent.working_directory = "/worktrees/feat".into();
    let agent_rx = agent.attach_test_input();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("agent".into(), agent)]),
    )
    .await;
    actor
        .agent_presence
        .update("agent", "codex".into(), AgentPresenceState::Done);

    actor.relocate_sessions_after_hand_on("child", "main", "/worktrees/feat", "/repo");

    let write = recv_write(&agent_rx);
    let expected = handoff_notify_message(
        WorkspaceHandoffDirection::HandOn,
        "/worktrees/feat",
        "/repo",
    );
    assert_eq!(write.bytes, build_agent_prompt_paste_bytes(&expected));
    assert_eq!(write.deferred_bytes.as_deref(), Some(AGENT_PROMPT_SUBMIT));
}

#[tokio::test]
async fn relocate_does_not_fail_when_every_session_must_be_skipped() {
    let dir = tempfile::tempdir().unwrap();
    let mut dead = Session::driver_test_stub("dead", 80, 24);
    dead.workspace_id = "main".into();
    dead.mark_exited_for_test();
    let mut no_writer = Session::driver_test_stub("no-writer", 80, 24);
    no_writer.workspace_id = "main".into();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("dead".into(), dead), ("no-writer".into(), no_writer)]),
    )
    .await;

    actor.relocate_sessions_after_handoff(
        WorkspaceHandoffDirection::HandOff,
        "main",
        "child",
        "/repo",
        "/worktrees/feat",
    );

    assert_eq!(
        actor.sessions.get("no-writer").unwrap().working_directory,
        "/worktrees/feat"
    );
}

/// The worktree transfer moves the linked issue row, and every watcher listens
/// only to `linkedIssuesChanged`, so a missing broadcast leaves the glyph on the
/// workspace the work came from until the app reconnects.
#[tokio::test]
async fn hand_off_and_hand_on_publish_a_wildcard_linked_issues_change() {
    let dir = tempfile::tempdir().unwrap();
    let (client, mut events) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(client))]),
        HashMap::new(),
    )
    .await;

    actor
        .relocate_sessions_after_hand_off(
            "main",
            &serde_json::json!({"workspace": {"id": "child", "path": "/worktrees/feat"}}),
        )
        .await;
    assert_eq!(next_linked_issues_event(&mut events), serde_json::json!({}));

    actor.relocate_sessions_after_hand_on("child", "main", "/worktrees/feat", "/repo");
    assert_eq!(next_linked_issues_event(&mut events), serde_json::json!({}));
}

/// The payload of the next `linkedIssuesChanged` event, skipping the tab and
/// workspace events the same paths emit.
fn next_linked_issues_event(
    events: &mut tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) -> serde_json::Value {
    while let Ok(message) = events.try_recv() {
        let Some(value) = message.as_json() else {
            continue;
        };
        if value["event"] == serde_json::json!("linkedIssuesChanged") {
            return value["payload"].clone();
        }
    }
    panic!("no linkedIssuesChanged event was published");
}
