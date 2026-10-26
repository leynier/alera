use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Map, Value};

use crate::agent_status::{
    resolve_agent_status_identity, AgentHookEvent, AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_registry::{adapter_for, canonical_agent_type};
use crate::terminal_host::orchestration::agent_session_resume::{
    ccs_profile_from_config_dir, native_session_id, usable_native_session_id,
    AgentSessionResumeShape, AGENT_NATIVE_CCS_PROFILE_KEY, AGENT_NATIVE_SESSION_AGENT_KEY,
    AGENT_NATIVE_SESSION_ID_KEY,
};

use crate::terminal_host::orchestration::agent_session_settings::AGENT_NATIVE_SESSION_SETTINGS_KEY;

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
        .filter(|agent| !agent.is_empty())
        .map(canonical_agent_type)?;
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

/// The model and modes the tab's conversation last reported, if any.
pub(super) fn native_session_settings(tab: &WorkspaceTabRecord) -> Option<&Map<String, Value>> {
    tab.payload
        .get(AGENT_NATIVE_SESSION_SETTINGS_KEY)
        .and_then(Value::as_object)
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
        if crate::agent_status::hook_identifies_child_agent(event)
            || crate::agent_status::hook_event_starts_unsaved_session(event)
        {
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
        let ccs_profile = (event.agent_type == "claude")
            .then(|| {
                event
                    .payload
                    .get("claudeConfigDir")
                    .and_then(Value::as_str)
                    .and_then(ccs_profile_from_config_dir)
            })
            .flatten();
        let settings = self.observed_session_settings(event).await;
        self.store_tab_native_session(
            &event.tab_id,
            ObservedNativeSession {
                agent_type: &event.agent_type,
                session_id,
                ccs_profile,
                cwd: event.payload.get("cwd").and_then(Value::as_str),
                settings,
            },
        )
        .await;
    }

    /// Binds the conversation a tab resumes and records it in the workspace's
    /// session ledger. `alera tab link-agent` writes the same fields the
    /// agent's own hooks do.
    pub(super) async fn store_tab_native_session(
        &mut self,
        tab_id: &str,
        observed: ObservedNativeSession<'_>,
    ) {
        let Ok(Some(mut tab)) = self.runtime_store.find_workspace_tab(tab_id).await else {
            return;
        };
        let ObservedNativeSession {
            agent_type,
            session_id,
            ccs_profile,
            cwd,
            settings,
        } = observed;
        let same_session = tab
            .payload
            .get(AGENT_NATIVE_SESSION_ID_KEY)
            .and_then(Value::as_str)
            == Some(session_id)
            && tab
                .payload
                .get(AGENT_NATIVE_SESSION_AGENT_KEY)
                .and_then(Value::as_str)
                == Some(agent_type);
        // Hooks report settings unevenly (Claude names its model only when
        // the session starts), so a later event refines the stored set rather
        // than replacing it. A different conversation starts from scratch.
        let mut merged = same_session
            .then(|| {
                tab.payload
                    .get(AGENT_NATIVE_SESSION_SETTINGS_KEY)
                    .and_then(Value::as_object)
                    .cloned()
            })
            .flatten()
            .unwrap_or_default();
        merged.extend(settings);
        let already_stored = same_session
            && tab
                .payload
                .get(AGENT_NATIVE_CCS_PROFILE_KEY)
                .and_then(Value::as_str)
                == ccs_profile
            && tab
                .payload
                .get(AGENT_NATIVE_SESSION_SETTINGS_KEY)
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default()
                == merged;
        self.record_workspace_native_session(
            &tab.workspace_id,
            tab_id,
            agent_type,
            session_id,
            ccs_profile,
            cwd,
            &merged,
        )
        .await;
        if already_stored {
            return;
        }
        if !tab.payload.is_object() {
            tab.payload = json!({});
        }
        tab.payload[AGENT_NATIVE_SESSION_ID_KEY] = json!(session_id);
        tab.payload[AGENT_NATIVE_SESSION_AGENT_KEY] = json!(agent_type);
        if let Some(payload) = tab.payload.as_object_mut() {
            match ccs_profile {
                Some(profile) => {
                    payload.insert(AGENT_NATIVE_CCS_PROFILE_KEY.into(), json!(profile));
                }
                None => {
                    payload.remove(AGENT_NATIVE_CCS_PROFILE_KEY);
                }
            }
            if merged.is_empty() {
                payload.remove(AGENT_NATIVE_SESSION_SETTINGS_KEY);
            } else {
                payload.insert(
                    AGENT_NATIVE_SESSION_SETTINGS_KEY.into(),
                    Value::Object(merged),
                );
            }
        }
        tab.updated_at = chrono::Utc::now();
        let workspace_id = tab.workspace_id.clone();
        if self.runtime_store.upsert_workspace_tab(tab).await.is_ok() {
            self.broadcast_workspace_tabs_changed(Some(&workspace_id));
        }
    }
}

/// What a hook or `alera tab link-agent` reported about a tab's conversation.
pub(super) struct ObservedNativeSession<'a> {
    pub agent_type: &'a str,
    pub session_id: &'a str,
    pub ccs_profile: Option<&'a str>,
    pub cwd: Option<&'a str>,
    pub settings: Map<String, Value>,
}

#[cfg(test)]
#[path = "agent_native_session_tests.rs"]
mod tests;
