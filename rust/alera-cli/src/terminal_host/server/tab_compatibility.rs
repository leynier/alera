//! Per-client tab-kind projection for additive workbench tab types.

use alera_core::runtime::WorkspaceTabRecord;

use crate::terminal_host::protocol::CODEX_TAB_KIND;

use super::terminal_pulse::TERMINAL_PULSE_PAYLOAD_KEY;
use super::{ClientKind, ServerActor};

const HOST_OWNED_TAB_PAYLOAD_KEYS: [&str; 8] = [
    "agentProfileLaunchV1",
    "initialPrompt",
    "pendingAgentPrompt",
    super::agent_title_state::PRIVATE_KEY,
    "agentTitleConversationId",
    "agentTitleRevision",
    "agentTitleStatus",
    "agentTitleSource",
];

/// Removes host-owned bootstrap text from a tab before it crosses the runtime
/// protocol. The persisted copy is recovery state, not workbench UI state.
pub(super) fn redact_private_tab_payload(tab: &mut WorkspaceTabRecord) {
    if let Some(payload) = tab.payload.as_object_mut() {
        for key in [
            "initialPrompt",
            "pendingAgentPrompt",
            super::agent_title_state::PRIVATE_KEY,
        ] {
            payload.remove(key);
        }
    }
}

/// Client tab updates operate on projected records. Carry host-owned launch
/// state across that replacement so a rename cannot erase recovery data or
/// rewrite the immutable profile snapshot.
pub(super) fn preserve_host_owned_tab_payload(
    stored: &WorkspaceTabRecord,
    incoming: &mut WorkspaceTabRecord,
) {
    let manual_rename = incoming.payload["manualTitle"] == true
        && (incoming.title != stored.title
            || (incoming.payload["agentTitleSource"] == "manual"
                && stored.payload["agentTitleSource"] != "manual"));
    let Some(stored_payload) = stored.payload.as_object() else {
        return;
    };
    if !HOST_OWNED_TAB_PAYLOAD_KEYS
        .iter()
        .any(|key| stored_payload.contains_key(*key))
    {
        return;
    }
    if !incoming.payload.is_object() {
        incoming.payload = serde_json::Value::Object(Default::default());
    }
    let incoming_payload = incoming
        .payload
        .as_object_mut()
        .expect("payload was normalized to an object");
    for key in HOST_OWNED_TAB_PAYLOAD_KEYS {
        match stored_payload.get(key) {
            Some(value) => {
                incoming_payload.insert(key.to_string(), value.clone());
            }
            None => {
                incoming_payload.remove(key);
            }
        }
    }
    if manual_rename {
        super::agent_title_state::invalidate(incoming);
    }
}

impl ServerActor {
    pub(super) fn workspace_tab_for_client(
        &self,
        client_id: u64,
        mut tab: WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let client = self.clients.get(&client_id);
        if tab.kind == "mobileEmulator" {
            return None;
        }
        let supports_codex = client.is_some_and(|client| client.supports_codex_tab_kind);
        if tab.kind == CODEX_TAB_KIND && !supports_codex {
            return None;
        }
        if client.is_some_and(|client| client.kind == ClientKind::Mobile) {
            tab.payload
                .as_object_mut()
                .map(|payload| payload.remove(TERMINAL_PULSE_PAYLOAD_KEY));
        }
        if tab.payload["agentTitleStatus"] == "generating"
            && !self.agent_title_jobs.contains_key(&tab.id)
        {
            tab.payload["agentTitleStatus"] = serde_json::json!("failed");
        }
        redact_private_tab_payload(&mut tab);
        Some(tab)
    }

    pub(super) fn workspace_tabs_for_client(
        &self,
        client_id: u64,
        tabs: Vec<WorkspaceTabRecord>,
    ) -> Vec<WorkspaceTabRecord> {
        tabs.into_iter()
            .filter_map(|tab| self.workspace_tab_for_client(client_id, tab))
            .collect()
    }
}
