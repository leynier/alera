use std::collections::HashMap;

use alera_core::runtime::{RuntimeAgentStatusHookSettings, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};

use super::super::actor_test_harness::test_actor;
use super::super::ServerActor;
use crate::agent_status::AgentHookEvent;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_session_resume::AGENT_NATIVE_SESSION_ID_KEY;
use crate::terminal_host::session::Session;

/// Far above any real pid, so `kill(pid, 0)` answers that it does not exist.
const DEAD_PID: u32 = 4_000_000;

fn event(agent: &str, name: &str, payload: Value) -> AgentHookEvent {
    AgentHookEvent {
        terminal_session_id: "session".into(),
        workspace_id: "workspace".into(),
        tab_id: "tab".into(),
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
            grok: true,
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

async fn send(actor: &mut ServerActor, agent: &str, name: &str, payload: Value) {
    actor
        .handle_agent_hook_event(event(agent, name, payload), false)
        .await;
}

fn state(actor: &ServerActor) -> Option<AgentPresenceState> {
    actor.agent_presence.get("session").map(|entry| entry.state)
}

async fn bound_session(actor: &ServerActor) -> Value {
    actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap()
        .payload[AGENT_NATIVE_SESSION_ID_KEY]
        .clone()
}

#[tokio::test]
async fn a_nested_agent_cannot_finish_or_rebind_the_tabs_running_turn() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let parent = json!({"session_id": "parent", "prompt": "Review this"});
    send(&mut actor, "claude", "UserPromptSubmit", parent).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));

    for name in ["SessionStart", "UserPromptSubmit", "Stop"] {
        send(&mut actor, "codex", name, json!({"session_id": "child"})).await;
    }
    for name in ["SessionStart", "Stop", "SessionEnd"] {
        let payload = json!({"session_id": "nested-claude", "source": "startup"});
        send(&mut actor, "claude", name, payload).await;
    }

    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Working);
    assert_eq!(presence.agent_type, "claude");
    assert_eq!(presence.native_session_id.as_deref(), Some("parent"));
    assert_eq!(bound_session(&actor).await, json!("parent"));

    send(
        &mut actor,
        "claude",
        "Stop",
        json!({"session_id": "parent"}),
    )
    .await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
}

#[tokio::test]
async fn a_finished_turn_lets_the_next_conversation_take_over() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    for name in ["UserPromptSubmit", "Stop"] {
        send(&mut actor, "claude", name, json!({"session_id": "first"})).await;
    }
    send(
        &mut actor,
        "codex",
        "UserPromptSubmit",
        json!({"session_id": "second"}),
    )
    .await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.agent_type, "codex");
    assert_eq!(presence.native_session_id.as_deref(), Some("second"));
    assert_eq!(bound_session(&actor).await, json!("second"));
}

#[tokio::test]
async fn claude_interrupts_errors_and_idle_prompts_end_the_turn() {
    for (name, payload, interrupted) in [
        (
            "PostToolUseFailure",
            json!({"session_id": "s", "is_interrupt": true, "tool_name": "Bash"}),
            Some(true),
        ),
        (
            "StopFailure",
            json!({"session_id": "s", "error": "rate_limit"}),
            Some(true),
        ),
        (
            "Notification",
            json!({"session_id": "s", "notification_type": "idle_prompt", "message": "Claude is waiting for your input"}),
            None,
        ),
    ] {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = actor(&dir).await;
        let prompt = json!({"session_id": "s", "prompt": "Do it"});
        send(&mut actor, "claude", "UserPromptSubmit", prompt).await;
        send(&mut actor, "claude", name, payload).await;
        let presence = actor.agent_presence.get("session").unwrap();
        assert_eq!(presence.state, AgentPresenceState::Done, "{name}");
        assert_eq!(presence.interrupted, interrupted, "{name}");
        assert_eq!(presence.prompt, "Do it", "{name}");
        assert!(!presence.inferred_idle, "{name}");
    }
}

#[tokio::test]
async fn an_idle_prompt_never_creates_presence_for_an_unused_agent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let idle = json!({"session_id": "s", "notification_type": "idle_prompt"});
    send(&mut actor, "claude", "Notification", idle).await;
    assert_eq!(state(&actor), None);
}

#[tokio::test]
async fn an_idle_prompt_after_a_dialog_is_not_injection_ready_but_confirms_an_inferred_idle() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    send(
        &mut actor,
        "claude",
        "PermissionRequest",
        json!({"session_id": "s"}),
    )
    .await;
    let idle = json!({"session_id": "s", "notification_type": "idle_prompt"});
    send(&mut actor, "claude", "Notification", idle.clone()).await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert!(presence.inferred_idle);
    assert!(!actor.agent_presence.is_injection_ready("session"));

    send(&mut actor, "claude", "Notification", idle).await;
    assert!(actor.agent_presence.is_injection_ready("session"));
}

#[tokio::test]
async fn codex_interrupt_ends_the_turn_and_session_end_clears_it() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    for name in ["UserPromptSubmit", "Interrupt"] {
        send(&mut actor, "codex", name, json!({"session_id": "s"})).await;
    }
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert_eq!(presence.interrupted, Some(true));
    let end = json!({"session_id": "s", "reason": "other"});
    send(&mut actor, "codex", "SessionEnd", end).await;
    assert_eq!(state(&actor), None);
}

#[tokio::test]
async fn a_late_session_end_for_a_replaced_thread_is_ignored() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    for id in ["a", "b"] {
        for name in ["UserPromptSubmit", "Stop"] {
            send(&mut actor, "codex", name, json!({"session_id": id})).await;
        }
    }
    let late = json!({"session_id": "a", "reason": "other"});
    send(&mut actor, "codex", "SessionEnd", late).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
    let current = json!({"session_id": "b", "reason": "other"});
    send(&mut actor, "codex", "SessionEnd", current).await;
    assert_eq!(state(&actor), None);
}

#[tokio::test]
async fn claude_clear_and_resume_keep_the_running_agent_present() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    // Esc mid-stream leaves `working` without any hook; /clear follows.
    let old = json!({"session_id": "old", "prompt": "Old"});
    send(&mut actor, "claude", "UserPromptSubmit", old).await;
    let end = json!({"session_id": "old", "reason": "clear"});
    send(&mut actor, "claude", "SessionEnd", end).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
    let start = json!({"session_id": "fresh", "source": "clear"});
    send(&mut actor, "claude", "SessionStart", start).await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert_eq!(presence.prompt, "");
    assert!(presence.accepts_injection());
    assert_eq!(bound_session(&actor).await, json!("old"));

    let prompt = json!({"session_id": "fresh", "prompt": "New"});
    send(&mut actor, "claude", "UserPromptSubmit", prompt).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));
    assert_eq!(bound_session(&actor).await, json!("fresh"));

    let switch = json!({"session_id": "fresh", "reason": "resume"});
    send(&mut actor, "claude", "SessionEnd", switch).await;
    let resumed = json!({"session_id": "resumed", "source": "resume"});
    send(&mut actor, "claude", "SessionStart", resumed).await;
    assert_eq!(bound_session(&actor).await, json!("resumed"));
    let compact = json!({"session_id": "resumed", "source": "compact"});
    send(&mut actor, "claude", "SessionStart", compact).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
}

#[tokio::test]
async fn a_fresh_claude_start_creates_no_presence_and_no_binding() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let start = json!({"session_id": "s", "source": "startup"});
    send(&mut actor, "claude", "SessionStart", start).await;
    assert_eq!(state(&actor), None);
    assert_eq!(bound_session(&actor).await, Value::Null);
}

#[tokio::test]
async fn claude_exit_clears_presence() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    send(
        &mut actor,
        "claude",
        "UserPromptSubmit",
        json!({"session_id": "s"}),
    )
    .await;
    let end = json!({"session_id": "s", "reason": "prompt_input_exit"});
    send(&mut actor, "claude", "SessionEnd", end).await;
    assert_eq!(state(&actor), None);
}

#[tokio::test]
async fn a_live_agent_process_owns_the_tab_even_after_its_turn() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let own = std::process::id();
    for name in ["UserPromptSubmit", "Stop"] {
        let payload = json!({"session_id": "tab", "aleraAgentPid": own});
        send(&mut actor, "claude", name, payload).await;
    }
    // A background `claude -p` left running by the finished turn.
    for name in ["SessionStart", "UserPromptSubmit", "SessionEnd"] {
        let payload = json!({"session_id": "bg", "aleraAgentPid": 4_000_001, "source": "startup"});
        send(&mut actor, "claude", name, payload).await;
    }
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert_eq!(presence.native_session_id.as_deref(), Some("tab"));
    assert_eq!(bound_session(&actor).await, json!("tab"));
}

#[tokio::test]
async fn a_relaunched_agent_takes_over_a_turn_its_predecessor_never_ended() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let crashed = json!({"session_id": "old", "aleraAgentPid": DEAD_PID});
    send(&mut actor, "claude", "UserPromptSubmit", crashed).await;
    let relaunched = json!({"session_id": "new", "aleraAgentPid": std::process::id()});
    send(&mut actor, "claude", "UserPromptSubmit", relaunched).await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.native_session_id.as_deref(), Some("new"));
    assert_eq!(bound_session(&actor).await, json!("new"));
}

#[tokio::test]
async fn sub_agents_ask_for_attention_but_never_end_or_reopen_the_turn() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let prompt = json!({"session_id": "s"});
    send(&mut actor, "claude", "UserPromptSubmit", prompt).await;
    let interrupted = json!({"session_id": "s", "agent_id": "a1", "is_interrupt": true});
    send(&mut actor, "claude", "PostToolUseFailure", interrupted).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));

    send(&mut actor, "claude", "Stop", json!({"session_id": "s"})).await;
    let sub = json!({"session_id": "s", "agent_id": "a1", "tool_name": "Bash"});
    send(&mut actor, "claude", "PreToolUse", sub.clone()).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
    // A late hook from the interrupted child cannot reopen the turn either.
    send(&mut actor, "claude", "PermissionRequest", sub).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
    let live = json!({"session_id": "s", "agent_id": "a2", "tool_name": "Bash"});
    send(&mut actor, "claude", "PermissionRequest", live).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Waiting));

    let grok_child = json!({"sessionId": "child", "subagentType": "explore"});
    send(&mut actor, "grok", "SessionEnd", grok_child).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Waiting));
}

#[tokio::test]
async fn claude_stays_working_while_background_sub_agents_run() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    send(
        &mut actor,
        "claude",
        "UserPromptSubmit",
        json!({"session_id": "s"}),
    )
    .await;
    let child = json!({"session_id": "s", "agent_id": "a1", "agent_type": "Explore"});
    send(&mut actor, "claude", "SubagentStart", child.clone()).await;
    send(&mut actor, "claude", "Stop", json!({"session_id": "s"})).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));
    assert!(!actor.agent_presence.is_injection_ready("session"));

    let question = json!({"session_id": "s", "agent_id": "a1", "tool_name": "AskUserQuestion"});
    send(&mut actor, "claude", "PreToolUse", question).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Waiting));
    let answered = json!({"session_id": "s", "agent_id": "a1", "tool_name": "AskUserQuestion"});
    send(&mut actor, "claude", "PostToolUse", answered).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));

    send(&mut actor, "claude", "SubagentStop", child).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Done));
    assert!(actor.agent_presence.is_injection_ready("session"));
}

#[tokio::test]
async fn grok_cancelled_turns_end_and_late_reports_for_older_turns_are_dropped() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    for turn in ["p1", "p2"] {
        let prompt = json!({"sessionId": "g", "promptId": turn});
        send(&mut actor, "grok", "UserPromptSubmit", prompt).await;
    }
    let late = json!({"sessionId": "g", "promptId": "p1"});
    send(&mut actor, "grok", "StopCancelled", late).await;
    assert_eq!(state(&actor), Some(AgentPresenceState::Working));
    let current = json!({"sessionId": "g", "promptId": "p2"});
    send(&mut actor, "grok", "StopCancelled", current).await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert_eq!(presence.state, AgentPresenceState::Done);
    assert_eq!(presence.interrupted, Some(true));
}

#[tokio::test]
async fn relayed_hooks_leave_liveness_to_the_satellite() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let payload = json!({"session_id": "s", "aleraAgentPid": DEAD_PID});
    actor
        .handle_agent_hook_event(event("claude", "UserPromptSubmit", payload), true)
        .await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert!(!presence.local_hook);
    assert_eq!(presence.agent_pid, None);
}

#[tokio::test]
async fn an_agent_inside_a_multiplexer_is_left_to_its_own_hooks() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let payload = json!({"session_id": "s", "aleraMultiplexer": "tmux"});
    send(&mut actor, "claude", "UserPromptSubmit", payload).await;
    let presence = actor.agent_presence.get("session").unwrap();
    assert!(!presence.local_hook);
    assert_eq!(presence.process_group, None);
}
