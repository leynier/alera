use alera_core::runtime::WorkspaceTabRecord;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use uuid::Uuid;

pub(super) const PRIVATE_KEY: &str = "agentTitleStateV1";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct AgentTitleState {
    pub conversation_id: String,
    pub agent: Option<String>,
    pub native_id: Option<String>,
    pub retired: Vec<String>,
    #[serde(default)]
    pub retired_prompts: BTreeMap<String, String>,
    pub initial_prompt: String,
    pub cursor: Option<u64>,
    pub eligible: bool,
    pub attempted: bool,
    pub closed: bool,
}

impl AgentTitleState {
    pub fn new(eligible: bool) -> Self {
        Self {
            conversation_id: Uuid::new_v4().to_string(),
            agent: None,
            native_id: None,
            retired: Vec::new(),
            retired_prompts: BTreeMap::new(),
            initial_prompt: String::new(),
            cursor: None,
            eligible,
            attempted: false,
            closed: false,
        }
    }

    pub fn read(tab: &WorkspaceTabRecord) -> Option<Self> {
        serde_json::from_value(tab.payload.get(PRIVATE_KEY)?.clone()).ok()
    }

    pub fn write(&self, tab: &mut WorkspaceTabRecord) {
        if !tab.payload.is_object() {
            tab.payload = json!({});
        }
        tab.payload[PRIVATE_KEY] = serde_json::to_value(self).expect("serializable title state");
        tab.payload["agentTitleConversationId"] = json!(self.conversation_id);
        if tab.payload.get("agentTitleRevision").is_none() {
            tab.payload["agentTitleRevision"] = json!(Uuid::new_v4().to_string());
        }
    }

    /// Unknown identities bind once; activity alone never proves a new conversation.
    pub fn observe(
        &mut self,
        agent: &str,
        native_id: Option<&str>,
        prompt: &str,
        cursor: u64,
    ) -> bool {
        let incoming = native_id.map(|id| format!("{agent}:{id}"));
        if incoming
            .as_ref()
            .is_some_and(|id| self.retired.contains(id))
        {
            return false;
        }
        let changed = self.agent.as_deref().is_some_and(|old| old != agent)
            || matches!((self.native_id.as_deref(), native_id), (Some(old), Some(new)) if old != new)
            || (self.closed && native_id.is_some() && native_id != self.native_id.as_deref());
        if changed {
            let mut retired = std::mem::take(&mut self.retired);
            let mut prompts = std::mem::take(&mut self.retired_prompts);
            if let (Some(old_agent), Some(old_id)) = (&self.agent, &self.native_id) {
                let key = format!("{old_agent}:{old_id}");
                prompts.insert(key.clone(), self.initial_prompt.clone());
                retired.push(key);
            }
            // Keep recent first prompts, never terminal transcripts, in private recovery state.
            prompts.retain(|key, _| retired.iter().rev().take(16).any(|id| id == key));
            *self = Self::new(true);
            self.retired = retired;
            self.retired_prompts = prompts;
            self.cursor = Some(cursor);
        }
        if self.closed && !changed {
            return false;
        }
        self.agent = Some(agent.to_string());
        if let Some(id) = native_id {
            self.native_id = Some(id.to_string());
        }
        if self.eligible && self.initial_prompt.is_empty() && !prompt.trim().is_empty() {
            self.initial_prompt =
                super::agent_title_context::prefix(prompt.trim(), 4096).to_string();
        }
        true
    }

    pub fn resume(&mut self, agent: &str, native_id: Option<&str>, cursor: u64) {
        let Some(id) = native_id else { return };
        let key = format!("{agent}:{id}");
        let was_retired = self.retired.contains(&key);
        if !(was_retired
            || (self.closed
                && self.agent.as_deref() == Some(agent)
                && self.native_id.as_deref() == Some(id)))
        {
            return;
        }
        let prompt = if was_retired {
            self.retired_prompts.remove(&key).unwrap_or_default()
        } else {
            self.initial_prompt.clone()
        };
        self.retired.retain(|old| old != &key);
        self.closed = false;
        self.observe(agent, native_id, "", cursor);
        // A resume is not a new automatic attempt; use a new token to reject older jobs.
        self.conversation_id = Uuid::new_v4().to_string();
        self.eligible = false;
        self.attempted = true;
        self.initial_prompt = prompt;
        self.cursor = Some(cursor);
    }
}

pub(super) fn hook_starts_conversation(event: &crate::agent_status::AgentHookEvent) -> bool {
    event
        .event_name
        .as_deref()
        .or_else(|| {
            ["hook_event_name", "hookEventName", "hook_type", "hookType"]
                .iter()
                .find_map(|key| event.payload.get(key).and_then(Value::as_str))
        })
        .is_some_and(|name| {
            name.chars()
                .filter(char::is_ascii_alphanumeric)
                .collect::<String>()
                .eq_ignore_ascii_case("sessionstart")
        })
}

pub(super) fn is_manual(tab: &WorkspaceTabRecord) -> bool {
    tab.payload.get("manualTitle").and_then(Value::as_bool) == Some(true)
        && tab.payload.get("agentTitleSource").and_then(Value::as_str) != Some("generated")
}

pub(super) fn initialize(tab: &mut WorkspaceTabRecord, prompt: &str) {
    if !matches!(tab.kind.as_str(), "terminal" | "codex") || AgentTitleState::read(tab).is_some() {
        return;
    }
    let mut state = AgentTitleState::new(true);
    state.initial_prompt = super::agent_title_context::prefix(prompt, 4096).to_string();
    state.cursor = Some(0);
    state.write(tab);
}

pub(super) fn invalidate(tab: &mut WorkspaceTabRecord) {
    if !tab.payload.is_object() {
        tab.payload = json!({});
    }
    tab.payload["agentTitleRevision"] = json!(Uuid::new_v4().to_string());
    tab.payload["agentTitleSource"] = json!("manual");
    tab.payload["agentTitleStatus"] = json!("idle");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn turns_and_resume_do_not_change_identity_or_first_prompt() {
        let mut state = AgentTitleState::new(true);
        state.observe("codex", Some("one"), "First", 0);
        let id = state.conversation_id.clone();
        state.attempted = true;
        state.observe("codex", Some("one"), "Second", 42);
        assert_eq!(id, state.conversation_id);
        assert_eq!(state.initial_prompt, "First");
        assert!(state.attempted);
    }

    #[test]
    fn new_conversation_rearms_but_late_events_do_not_restore_old_identity() {
        let mut state = AgentTitleState::new(false);
        state.observe("codex", Some("one"), "Old", 0);
        state.observe("codex", Some("two"), "New", 42);
        assert!(state.eligible);
        assert_eq!(state.cursor, Some(42));
        assert!(!state.observe("codex", Some("one"), "Late", 80));
        assert_eq!(state.initial_prompt, "New");
    }

    #[test]
    fn legacy_and_unidentified_sessions_are_conservative() {
        let mut state = AgentTitleState::new(false);
        state.observe("pi", None, "First", 0);
        state.observe("pi", None, "Another task", 100);
        assert!(!state.eligible);
        state.observe("pi", Some("native"), "Bind", 120);
        assert!(!state.eligible);
    }
}
