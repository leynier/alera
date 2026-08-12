//! Per-client tab-kind projection for additive workbench tab types.

use alera_core::runtime::WorkspaceTabRecord;

use crate::terminal_host::protocol::{CODEX_TAB_KIND, MOBILE_EMULATOR_TAB_KIND};

use super::terminal_pulse::TERMINAL_PULSE_PAYLOAD_KEY;
use super::{ClientKind, ServerActor};

impl ServerActor {
    pub(super) fn workspace_tab_for_client(
        &self,
        client_id: u64,
        mut tab: WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let client = self.clients.get(&client_id);
        let supports_mobile_emulator = client.is_some_and(|client| {
            client.kind == ClientKind::Mobile || client.supports_mobile_emulator_tab_kind
        });
        if tab.kind == MOBILE_EMULATOR_TAB_KIND && !supports_mobile_emulator {
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
