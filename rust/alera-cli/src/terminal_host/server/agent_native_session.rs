use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};

use crate::agent_status::{
    resolve_agent_status_identity, AgentHookEvent, AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::agent_session_resume::{
    ccs_profile_from_config_dir, hook_identifies_parent_session, native_session_id,
    usable_native_session_id, AgentSessionResumeShape, AGENT_NATIVE_CCS_PROFILE_KEY,
    AGENT_NATIVE_SESSION_AGENT_KEY, AGENT_NATIVE_SESSION_ID_KEY,
};

use super::terminal_startup_commands::tab_agent_type;
use super::ServerActor;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct NativeSessionResume<'a> {
    pub agent_type: &'a str,
    pub session_id: &'a str,
    pub shape: AgentSessionResumeShape,
}

pub(super) fn native_session_resume(tab: &WorkspaceTabRecord) -> Option<NativeSessionResume<'_>> {
    let session_id = tab
        .payload
        .get(AGENT_NATIVE_SESSION_ID_KEY)
        .and_then(Value::as_str)
        .and_then(usable_native_session_id)?;
    let stored_agent = tab
        .payload
        .get(AGENT_NATIVE_SESSION_AGENT_KEY)
        .and_then(Value::as_str)
        .filter(|agent| !agent.is_empty())?;
    if let Some(tab_agent) = tab_agent_type(tab) {
        if stored_agent != tab_agent {
            return None;
        }
    }
    let shape = adapter_for(stored_agent)?.session_resume?;
    Some(NativeSessionResume {
        agent_type: stored_agent,
        session_id,
        shape,
    })
}

pub(super) fn native_ccs_profile(tab: &WorkspaceTabRecord) -> Option<&str> {
    tab.payload
        .get(AGENT_NATIVE_CCS_PROFILE_KEY)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|profile| {
            !profile.is_empty()
                && !profile.starts_with('-')
                && profile.split_whitespace().count() == 1
        })
}

impl ServerActor {
    pub(super) async fn observe_hook_native_session(&mut self, event: &AgentHookEvent) {
        if hook_identifies_parent_session(&event.payload) {
            return;
        }
        let Some(session_id) = native_session_id(&event.payload) else {
            return;
        };
        let identity = resolve_agent_status_identity(
            self.agent_presence.get(&event.terminal_session_id),
            &event.agent_type,
            crate::agent_status::normalize_hook_event(event, None)
                .map(|status| status.state)
                .unwrap_or(AgentPresenceState::Done),
            chrono::Utc::now(),
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        if identity.should_ignore_event || identity.effective_agent_type != event.agent_type {
            return;
        }
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(&event.tab_id).await else {
            return;
        };
        let ccs_profile = (event.agent_type == "claude")
            .then(|| {
                event
                    .payload
                    .get("claudeConfigDir")
                    .and_then(Value::as_str)
                    .and_then(ccs_profile_from_config_dir)
            })
            .flatten();
        let already_stored = tab
            .payload
            .get(AGENT_NATIVE_SESSION_ID_KEY)
            .and_then(Value::as_str)
            == Some(session_id)
            && tab
                .payload
                .get(AGENT_NATIVE_SESSION_AGENT_KEY)
                .and_then(Value::as_str)
                == Some(event.agent_type.as_str())
            && tab
                .payload
                .get(AGENT_NATIVE_CCS_PROFILE_KEY)
                .and_then(Value::as_str)
                == ccs_profile;
        if already_stored {
            return;
        }
        if !tab.payload.is_object() {
            tab.payload = json!({});
        }
        tab.payload[AGENT_NATIVE_SESSION_ID_KEY] = json!(session_id);
        tab.payload[AGENT_NATIVE_SESSION_AGENT_KEY] = json!(event.agent_type);
        if let Some(profile) = ccs_profile {
            tab.payload[AGENT_NATIVE_CCS_PROFILE_KEY] = json!(profile);
        } else if let Some(payload) = tab.payload.as_object_mut() {
            payload.remove(AGENT_NATIVE_CCS_PROFILE_KEY);
        }
        tab.updated_at = chrono::Utc::now();
        let workspace_id = tab.workspace_id.clone();
        if self.runtime_store.upsert_workspace_tab(tab).await.is_ok() {
            self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        }
    }
}

#[cfg(test)]
mod tests {
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
    async fn store_path_persists_native_ids_for_every_spawnable_agent() {
        let cases = [
            ("codex", "session_id", "sess-codex"),
            ("claude", "session_id", "sess-claude"),
            ("copilot", "session_id", "sess-copilot"),
            ("cursor", "conversation_id", "conv-cursor"),
            ("agy", "conversationId", "conv-agy"),
            ("opencode", "sessionId", "sess-opencode"),
            ("opencode2", "sessionID", "sess-opencode2"),
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
}
