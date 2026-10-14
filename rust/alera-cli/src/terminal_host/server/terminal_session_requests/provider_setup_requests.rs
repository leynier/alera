use super::super::agent_chat_provider_settings::setup::{ProviderSetupContext, SETUP_WORKSPACE_ID};
use super::super::client_delivery::LocalClientRole;
use super::super::ClientKind;
use super::*;

impl ServerActor {
    fn require_provider_setup_client(&self, client_id: u64) -> HostResult<()> {
        let allowed = self.clients.get(&client_id).is_some_and(|client| {
            setup_caller_allowed(
                client.authenticated,
                client.kind,
                client.local_role,
                client.relay_client_id.is_some(),
                client.chat_orchestration_binding.is_some(),
            )
        });
        if allowed {
            Ok(())
        } else {
            Err(HostError::conflict(
                "notAllowed",
                "Provider setup requires an authenticated desktop app.",
                json!({}),
            ))
        }
    }

    pub(in crate::terminal_host::server) fn require_provider_setup_session_access(
        &self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<()> {
        if payload["sessionId"]
            .as_str()
            .and_then(|id| self.sessions.get(id))
            .is_some_and(|session| session.provider_setup.is_some())
        {
            self.require_provider_setup_client(client_id)?;
        }
        Ok(())
    }

    pub(super) async fn validate_provider_setup_request(
        &self,
        client_id: u64,
        payload: &Value,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
    ) -> HostResult<()> {
        let requested = payload["launch"]
            .get("providerSetup")
            .filter(|value| !value.is_null())
            .map(ProviderSetupContext::from_json)
            .transpose()?;
        let existing = self
            .sessions
            .get(session_id)
            .and_then(|session| session.provider_setup.as_ref());
        if requested.is_none() && existing.is_none() {
            return Ok(());
        }
        self.require_provider_setup_client(client_id)?;
        if workspace_id != SETUP_WORKSPACE_ID || payload["attachmentMode"] == "observe" {
            return Err(HostError::conflict(
                "notAllowed",
                "Provider setup requires an ephemeral local command terminal.",
                json!({}),
            ));
        }
        if self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .is_some()
        {
            return Err(HostError::conflict(
                "notAllowed",
                "Provider setup cannot use a persisted workspace tab.",
                json!({}),
            ));
        }
        if existing.is_some() && requested.as_ref() != existing {
            return Err(HostError::conflict(
                "notAllowed",
                "Provider setup selection does not match this terminal.",
                json!({}),
            ));
        }
        // Validation precedes attachment, restart history changes, and process teardown.
        self.agent_chat_provider_settings
            .as_ref()
            .ok_or_else(|| HostError::state("Providers Settings is unavailable."))?
            .validate_provider_setup(requested.as_ref().or(existing).expect("checked context"))
            .await
    }
}

fn setup_caller_allowed(
    authenticated: bool,
    kind: ClientKind,
    role: LocalClientRole,
    relay: bool,
    bound_chat: bool,
) -> bool {
    authenticated
        && kind == ClientKind::Local
        && role == LocalClientRole::App
        && !relay
        && !bound_chat
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn setup_requires_connection_derived_human_desktop_identity() {
        assert!(setup_caller_allowed(
            true,
            ClientKind::Local,
            LocalClientRole::App,
            false,
            false
        ));
        for (auth, kind, role, relay, bound) in [
            (false, ClientKind::Local, LocalClientRole::App, false, false),
            (true, ClientKind::Mobile, LocalClientRole::App, false, false),
            (true, ClientKind::Local, LocalClientRole::Cli, false, false),
            (true, ClientKind::Local, LocalClientRole::App, true, false),
            (true, ClientKind::Local, LocalClientRole::App, false, true),
        ] {
            assert!(!setup_caller_allowed(auth, kind, role, relay, bound));
        }
    }
}
