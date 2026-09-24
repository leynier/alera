use super::ServerActor;
use alera_core::runtime::{TerminalLifecycleAction, TerminalLifecycleOperation, LOCAL_HOST_ID};

pub(super) fn natural_exit_epoch() -> &'static str {
    static EPOCH: std::sync::LazyLock<String> =
        std::sync::LazyLock::new(|| format!("natural-exit:{}", uuid::Uuid::new_v4()));
    EPOCH.as_str()
}

impl ServerActor {
    pub(super) async fn is_ssh_owner_terminal(&self, session_id: &str) -> bool {
        let Some(session) = self.sessions.get(session_id) else {
            return false;
        };
        match self.runtime_store.find_workspace_tab(&session.tab_id).await {
            Ok(Some(tab)) => tab.payload["sshOwnerTerminal"] == true,
            Err(_) => true,
            _ => false,
        }
    }

    pub(super) async fn capture_owner_natural_exit(&mut self, session_id: &str) {
        if !self.is_ssh_owner_terminal(session_id).await {
            return;
        }
        let result = async {
            let session = self
                .sessions
                .get(session_id)
                .ok_or_else(|| anyhow::anyhow!("Owner terminal disappeared"))?;
            let workspace = self
                .runtime_store
                .find_workspace(&session.workspace_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("Owner workspace disappeared"))?;
            if workspace.host_id != LOCAL_HOST_ID {
                anyhow::bail!("Owner terminal workspace is not local");
            }
            let shutdown =
                crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown::capture(
                    std::iter::once(session),
                )
                .await
                .map_err(|error| anyhow::anyhow!(error.wire_message()))?;
            let operation = TerminalLifecycleOperation {
                id: uuid::Uuid::new_v4().to_string(),
                workspace,
                tab_id: session.tab_id.clone(),
                session_id: session_id.into(),
                session_generation: session.instance_id(),
                initiator_epoch: Some(natural_exit_epoch().into()),
                action: TerminalLifecycleAction::Restart,
                closure_verified: false,
            };
            self.runtime_store
                .begin_terminal_lifecycle_operation(&operation)
                .await?;
            self.wait_owner_terminal_lifecycle(0, 0, operation, shutdown);
            Ok::<(), anyhow::Error>(())
        }
        .await;
        if let Err(error) = result {
            tracing::warn!("Owner natural exit remains unverified: {error}");
        }
    }
}
