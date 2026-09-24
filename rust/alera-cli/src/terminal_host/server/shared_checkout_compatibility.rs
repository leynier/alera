use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) fn require_shared_checkout_support(
        &self,
        client_id: u64,
        request_type: &str,
    ) -> HostResult<()> {
        if !requires_shared_checkout_support(request_type) {
            return Ok(());
        }
        self.require_auth(client_id)?;
        if self
            .clients
            .get(&client_id)
            .is_some_and(|client| client.shared_checkout_workspaces)
        {
            return Ok(());
        }
        Err(HostError::state(format!(
            "Update this Alera client before using {request_type}: this runtime uses independent shared-checkout workspaces. Existing terminal sessions remain available."
        )))
    }
}

pub(crate) fn requires_shared_checkout_support(request_type: &str) -> bool {
    request_type.starts_with("workspace.bufferGuard.")
        || matches!(
            request_type,
            "terminal.ownerLifecycle"
                | "workspace.upsert"
                | "workspace.sshRelocationRecovery"
                | "checkout.quickOpen.start"
                | "workspace.createShared"
                | "workspace.removeShared"
                | "workspace.handOff"
                | "workspace.handOn"
                | "workspace.runSetup"
                | "workspace.prepareRelocationSetup"
                | "workspace.recoverRelocationSetup"
                | "workspace.cancelRelocationSetup"
                | "workspace.remove"
                | "workspace.removeForProject"
                | "project.register"
                | "project.checkout.register"
                | "project.clone.start"
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn negotiation_is_per_client_and_does_not_disconnect_legacy_sessions() {
        use super::super::actor_test_harness::{local_client, test_actor};
        use crate::terminal_host::client::ClientHandle;
        use crate::terminal_host::protocol::PROTOCOL_VERSION;
        use std::collections::HashMap;
        use tokio::sync::mpsc;
        let dir = tempfile::tempdir().unwrap();
        let (control, _control_rx) = mpsc::unbounded_channel();
        let (terminal, _terminal_rx) = mpsc::channel(8);
        let mut actor = test_actor(
            &dir,
            HashMap::from([(1, local_client(ClientHandle::new(control, terminal)))]),
            HashMap::new(),
        )
        .await;
        actor
            .handle_hello(
                1,
                &serde_json::json!({"protocolVersion": PROTOCOL_VERSION, "token": "token"}),
            )
            .unwrap();
        assert!(actor.require_auth(1).is_ok());
        assert!(actor
            .require_shared_checkout_support(1, "workspace.upsert")
            .is_err());
        assert!(actor
            .require_shared_checkout_support(1, "workspace.listAll")
            .is_ok());
        assert!(actor
            .runtime_store
            .list_all_workspaces()
            .await
            .unwrap()
            .is_empty());
        actor.handle_hello(1, &serde_json::json!({"protocolVersion": PROTOCOL_VERSION, "token": "token", "sharedCheckoutWorkspacesV1": true})).unwrap();
        assert!(actor
            .require_shared_checkout_support(1, "workspace.upsert")
            .is_ok());
        assert_eq!(actor.clients.len(), 1);
    }

    #[test]
    fn terminal_and_read_operations_remain_independent() {
        for operation in [
            "hello",
            "mobile.hello",
            "spawn",
            "attach",
            "input",
            "status.get",
            "workspace.listAll",
        ] {
            assert!(!requires_shared_checkout_support(operation), "{operation}");
        }
        for operation in [
            "terminal.ownerLifecycle",
            "workspace.upsert",
            "workspace.handOn",
            "workspace.runSetup",
            "workspace.prepareRelocationSetup",
            "workspace.recoverRelocationSetup",
            "workspace.cancelRelocationSetup",
            "project.register",
            "project.checkout.register",
            "workspace.createShared",
        ] {
            assert!(requires_shared_checkout_support(operation), "{operation}");
        }
    }
}
