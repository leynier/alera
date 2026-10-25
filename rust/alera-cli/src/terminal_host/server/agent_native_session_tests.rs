use std::collections::HashMap;

use super::super::actor_test_harness::test_actor;
use super::super::tab_compatibility::{
    preserve_host_owned_tab_payload, redact_private_tab_payload,
};
use super::*;
use crate::agent_status::AgentHookEvent;
use chrono::Utc;
use serde_json::json;

fn tab() -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: "tab".into(),
        workspace_id: "workspace".into(),
        kind: "terminal".into(),
        title: "Codex".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({"agentType": "codex"}),
    }
}

fn event(id: Option<&str>, extra: Value) -> AgentHookEvent {
    let mut payload = extra;
    if let Some(id) = id {
        payload["session_id"] = json!(id);
    }
    AgentHookEvent {
        terminal_session_id: "session".into(),
        workspace_id: "workspace".into(),
        tab_id: "tab".into(),
        agent_type: "codex".into(),
        event_name: Some("SessionStart".into()),
        payload,
    }
}

#[tokio::test]
async fn explicit_binding_survives_child_hooks_and_is_confirmed_by_the_parent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut record = tab();
    record.payload[AGENT_NATIVE_SESSION_ID_KEY] = json!("requested-session");
    record.payload[AGENT_NATIVE_SESSION_AGENT_KEY] = json!("codex");
    actor
        .runtime_store
        .upsert_workspace_tab(record)
        .await
        .unwrap();
    actor
        .observe_hook_native_session(&event(
            Some("child-session"),
            json!({"parent_session_id": "requested-session"}),
        ))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        native_session_resume(&saved).unwrap().session_id,
        "requested-session"
    );
    actor
        .observe_hook_native_session(&event(Some("requested-session"), json!({})))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        native_session_resume(&saved).unwrap().session_id,
        "requested-session"
    );
}

#[tokio::test]
async fn store_path_persists_a_hook_session_id_on_the_tab() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor
        .runtime_store
        .upsert_workspace_tab(tab())
        .await
        .unwrap();
    actor
        .observe_hook_native_session(&event(Some("sess-1"), json!({})))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(saved.payload[AGENT_NATIVE_SESSION_ID_KEY], json!("sess-1"));
    assert_eq!(
        saved.payload[AGENT_NATIVE_SESSION_AGENT_KEY],
        json!("codex")
    );
    let resume = native_session_resume(&saved).unwrap();
    assert_eq!(resume.session_id, "sess-1");
    assert_eq!(resume.agent_type, "codex");
    let mut projected = saved.clone();
    redact_private_tab_payload(&mut projected);
    assert_eq!(
        projected.payload[AGENT_NATIVE_SESSION_ID_KEY],
        json!("sess-1")
    );
    let mut incoming = projected;
    incoming.payload[AGENT_NATIVE_SESSION_ID_KEY] = json!("forged");
    incoming.payload[AGENT_NATIVE_SESSION_AGENT_KEY] = json!("claude");
    preserve_host_owned_tab_payload(&saved, &mut incoming);
    assert_eq!(
        incoming.payload[AGENT_NATIVE_SESSION_ID_KEY],
        json!("sess-1")
    );
    assert_eq!(
        incoming.payload[AGENT_NATIVE_SESSION_AGENT_KEY],
        json!("codex")
    );
}

#[tokio::test]
async fn missing_id_path_leaves_the_tab_unchanged() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor
        .runtime_store
        .upsert_workspace_tab(tab())
        .await
        .unwrap();
    actor
        .observe_hook_native_session(&event(None, json!({"prompt": "hello"})))
        .await;
    actor
        .observe_hook_native_session(&event(
            Some("child"),
            json!({"parent_session_id": "parent"}),
        ))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert!(saved.payload.get(AGENT_NATIVE_SESSION_ID_KEY).is_none());
    assert!(native_session_resume(&saved).is_none());
    assert!(native_session_resume(&tab()).is_none());
}

#[tokio::test]
async fn store_path_associates_a_hook_session_with_a_plain_terminal_tab() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut record = tab();
    record.payload = json!({});
    actor
        .runtime_store
        .upsert_workspace_tab(record)
        .await
        .unwrap();
    actor
        .observe_hook_native_session(&event(Some("sess-1"), json!({})))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(saved.payload[AGENT_NATIVE_SESSION_ID_KEY], json!("sess-1"));
    assert_eq!(
        saved.payload[AGENT_NATIVE_SESSION_AGENT_KEY],
        json!("codex")
    );
    let resume = native_session_resume(&saved).unwrap();
    assert_eq!(resume.agent_type, "codex");
    assert_eq!(resume.session_id, "sess-1");
}

#[tokio::test]
async fn store_path_keeps_the_ccs_instance_from_claude_config_dir() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut record = tab();
    record.payload = json!({});
    actor
        .runtime_store
        .upsert_workspace_tab(record)
        .await
        .unwrap();
    actor
        .observe_hook_native_session(&AgentHookEvent {
            terminal_session_id: "session".into(),
            workspace_id: "workspace".into(),
            tab_id: "tab".into(),
            agent_type: "claude".into(),
            event_name: Some("UserPromptSubmit".into()),
            payload: json!({
                "session_id": "sess-1",
                "claudeConfigDir": "/home/user/.ccs/instances/leynier41"
            }),
        })
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(saved.payload[AGENT_NATIVE_SESSION_ID_KEY], json!("sess-1"));
    assert_eq!(
        saved.payload[AGENT_NATIVE_SESSION_AGENT_KEY],
        json!("claude")
    );
    assert_eq!(
        saved.payload[AGENT_NATIVE_CCS_PROFILE_KEY],
        json!("leynier41")
    );
    assert_eq!(native_ccs_profile(&saved), Some("leynier41"));
    let resume = native_session_resume(&saved).unwrap();
    assert_eq!(resume.agent_type, "claude");
}

#[tokio::test]
async fn settings_accumulate_per_conversation_and_reach_the_ledger() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let mut record = tab();
    record.payload = json!({"agentType": "claude"});
    actor
        .runtime_store
        .upsert_workspace_tab(record)
        .await
        .unwrap();
    let hook = |name: &str, payload: Value| AgentHookEvent {
        terminal_session_id: "session".into(),
        workspace_id: "workspace".into(),
        tab_id: "tab".into(),
        agent_type: "claude".into(),
        event_name: Some(name.into()),
        payload,
    };
    actor
        .observe_hook_native_session(&hook(
            "SessionStart",
            json!({"session_id": "sess-1", "source": "resume", "model": "opus", "cwd": "/repo/feature"}),
        ))
        .await;
    actor
        .observe_hook_native_session(&hook(
            "UserPromptSubmit",
            json!({"session_id": "sess-1", "permission_mode": "plan"}),
        ))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        saved.payload[AGENT_NATIVE_SESSION_SETTINGS_KEY],
        json!({"model": "opus", "permissionMode": "plan"})
    );
    actor
        .observe_hook_native_session(&hook(
            "UserPromptSubmit",
            json!({"session_id": "sess-2", "permission_mode": "acceptEdits"}),
        ))
        .await;
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        saved.payload[AGENT_NATIVE_SESSION_SETTINGS_KEY],
        json!({"permissionMode": "acceptEdits"})
    );
    let ledger = actor
        .runtime_store
        .list_agent_native_sessions("workspace")
        .await
        .unwrap();
    let ids = ledger
        .iter()
        .map(|row| row.session_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(ids, ["sess-1", "sess-2"]);
    assert_eq!(ledger[0].cwd.as_deref(), Some("/repo/feature"));
    assert_eq!(
        ledger[0].settings,
        Some(json!({"model": "opus", "permissionMode": "plan"}))
    );
}

#[tokio::test]
async fn store_path_persists_native_ids_for_every_spawnable_agent() {
    let cases = [
        ("codex", "session_id", "sess-codex"),
        ("claude", "session_id", "sess-claude"),
        ("copilot", "session_id", "sess-copilot"),
        ("cursor", "conversation_id", "conv-cursor"),
        ("agy", "conversationId", "conv-agy"),
        ("opencode", "sessionId", "sess-opencode"),
        ("opencode", "sessionID", "sess-opencode-v2"),
        ("pi", "sessionId", "sess-pi"),
        ("amp", "threadId", "thread-amp"),
        ("grok", "session_id", "sess-grok"),
        ("fx", "session_id", "sess-fx"),
    ];
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    for (index, (agent, key, id)) in cases.into_iter().enumerate() {
        let tab_id = format!("tab-{index}");
        let mut record = tab();
        record.id = tab_id.clone();
        record.payload = json!({ "agentType": agent });
        actor
            .runtime_store
            .upsert_workspace_tab(record)
            .await
            .unwrap();
        actor
            .observe_hook_native_session(&AgentHookEvent {
                terminal_session_id: "session".into(),
                workspace_id: "workspace".into(),
                tab_id: tab_id.clone(),
                agent_type: agent.into(),
                event_name: Some("UserPromptSubmit".into()),
                payload: json!({ key: id }),
            })
            .await;
        let saved = actor
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(saved.payload[AGENT_NATIVE_SESSION_ID_KEY], json!(id));
        assert_eq!(saved.payload[AGENT_NATIVE_SESSION_AGENT_KEY], json!(agent));
        let resume = native_session_resume(&saved).expect(agent);
        assert_eq!(resume.session_id, id);
        assert_eq!(resume.agent_type, agent);
    }
}
