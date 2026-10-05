use std::collections::HashMap;

use alera_core::runtime::{RuntimeAgentStatusHookSettings, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};

use super::super::actor_test_harness::test_actor;
use super::super::ServerActor;
use crate::agent_status::AgentHookEvent;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_session_resume::{
    AGENT_NATIVE_CCS_PROFILE_KEY, AGENT_NATIVE_SESSION_AGENT_KEY, AGENT_NATIVE_SESSION_ID_KEY,
};
use crate::terminal_host::session::Session;

fn hook(terminal: &str, tab: &str, agent: &str, name: &str, payload: Value) -> AgentHookEvent {
    AgentHookEvent {
        terminal_session_id: terminal.into(),
        workspace_id: "workspace".into(),
        tab_id: tab.into(),
        agent_type: agent.into(),
        event_name: Some(name.into()),
        payload,
    }
}

async fn actor(dir: &tempfile::TempDir) -> ServerActor {
    let mut session = Session::driver_test_stub("session", 80, 24);
    session.workspace_id = "workspace".into();
    session.tab_id = "tab".into();
    let actor = test_actor(
        dir,
        HashMap::new(),
        HashMap::from([("session".to_string(), session)]),
    )
    .await;
    actor
        .runtime_store
        .set_agent_status_hook_settings(&RuntimeAgentStatusHookSettings {
            claude: true,
            codex: true,
            ..Default::default()
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: "workspace".into(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({}),
        })
        .await
        .unwrap();
    actor
}

fn state(actor: &ServerActor) -> Option<AgentPresenceState> {
    actor.agent_presence.get("session").map(|entry| entry.state)
}

async fn tab_payload(actor: &ServerActor) -> Value {
    actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap()
        .payload
}

#[cfg(unix)]
#[tokio::test]
async fn linking_replaces_the_process_that_made_the_tab_ignore_its_agent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let first_pid = std::process::id();
    let relaunched_pid = std::os::unix::process::parent_id();
    let first = json!({"session_id": "old", "aleraAgentPid": first_pid});
    actor
        .handle_agent_hook_event(
            hook("session", "tab", "claude", "UserPromptSubmit", first),
            false,
        )
        .await;
    let relaunched = json!({"session_id": "new", "aleraAgentPid": relaunched_pid});
    actor
        .handle_agent_hook_event(
            hook("session", "tab", "claude", "Stop", relaunched.clone()),
            false,
        )
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));

    let linked = actor
        .link_agent_presence(&json!({
            "tabId": "tab",
            "agentType": "claude",
            "nativeSessionId": "new",
            "agentPid": relaunched_pid,
            "sourceTerminalSessionId": "session",
            "claudeConfigDir": "/home/me/.ccs/instances/work",
        }))
        .await
        .unwrap();
    assert_eq!(linked["terminalSessionId"], "session");
    assert_eq!(linked["reroutedFrom"], Value::Null);
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.agent_pid, Some(relaunched_pid));
    assert_eq!(presence.native_session_id.as_deref(), Some("new"));
    let payload = tab_payload(&actor).await;
    assert_eq!(payload[AGENT_NATIVE_SESSION_ID_KEY], "new");
    assert_eq!(payload[AGENT_NATIVE_SESSION_AGENT_KEY], "claude");
    assert_eq!(payload[AGENT_NATIVE_CCS_PROFILE_KEY], "work");

    actor
        .handle_agent_hook_event(hook("session", "tab", "claude", "Stop", relaunched), false)
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
}

#[tokio::test]
async fn hooks_from_a_stale_terminal_identity_reach_the_linked_tab() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let stale = |name: &str, conversation: &str| {
        hook(
            "gone",
            "old-tab",
            "codex",
            name,
            json!({"session_id": conversation}),
        )
    };
    actor
        .handle_agent_hook_event(stale("UserPromptSubmit", "thread"), false)
        .await;
    assert_eq!(state(&actor), None);

    let linked = actor
        .link_agent_presence(&json!({
            "tabId": "tab",
            "agentType": "codex",
            "nativeSessionId": "thread",
            "sourceTerminalSessionId": "gone",
        }))
        .await
        .unwrap();
    assert_eq!(linked["reroutedFrom"], "gone");
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));

    actor
        .handle_agent_hook_event(stale("Stop", "thread"), false)
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));

    // Another agent that inherited the same stale environment stays out.
    actor
        .handle_agent_hook_event(stale("UserPromptSubmit", "other-thread"), false)
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));

    // Relayed hooks keep the identity the satellite reported.
    actor
        .handle_agent_hook_event(stale("UserPromptSubmit", "thread"), true)
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
}

#[tokio::test]
async fn linking_from_inside_the_tab_drops_routes_into_it() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let link = |source: &str| {
        json!({
            "tabId": "tab",
            "agentType": "codex",
            "nativeSessionId": "thread",
            "sourceTerminalSessionId": source,
        })
    };
    actor.link_agent_presence(&link("gone")).await.unwrap();
    actor.link_agent_presence(&link("session")).await.unwrap();
    actor
        .handle_agent_hook_event(
            hook(
                "gone",
                "old-tab",
                "codex",
                "Stop",
                json!({"session_id": "thread"}),
            ),
            false,
        )
        .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));
}

#[tokio::test]
async fn linking_another_agent_type_starts_a_clean_presence() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    actor
        .handle_agent_hook_event(
            hook(
                "session",
                "tab",
                "codex",
                "UserPromptSubmit",
                json!({"session_id": "thread", "prompt": "Old"}),
            ),
            false,
        )
        .await;

    actor
        .link_agent_presence(&json!({"tabId": "tab", "agentType": "claude", "state": "done"}))
        .await
        .unwrap();

    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.agent_type, "claude");
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert_eq!(presence.prompt, "");
    assert_eq!(presence.native_session_id, None);
}

#[tokio::test]
async fn linking_rejects_unknown_tabs_agents_and_values() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    for payload in [
        json!({"tabId": "missing", "agentType": "claude"}),
        json!({"tabId": "tab", "agentType": "vim"}),
        json!({"tabId": "tab", "agentType": "claude", "state": "sleeping"}),
        json!({"tabId": "tab", "agentType": "claude", "agentPid": 0}),
        json!({"tabId": "tab", "agentType": "claude", "nativeSessionId": "a;b"}),
        json!({"agentType": "claude"}),
    ] {
        assert!(
            actor.link_agent_presence(&payload).await.is_err(),
            "{payload}"
        );
    }
    assert_eq!(state(&actor), None);
}
