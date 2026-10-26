use crate::provider::PiProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    ApprovalPolicy, McpTransport, ProviderError, RuntimeMode, SessionStartInput,
};

impl<T: JsonTransport> PiProvider<T> {
    pub(crate) fn validate_policy(&self, input: &SessionStartInput) -> Result<(), ProviderError> {
        if input.sandbox_mode.is_some() || self.config.sandbox_mode.is_some() {
            return Err(ProviderError::Unsupported(
                "Pi sandbox policy is controlled by the user's own process configuration".into(),
            ));
        }
        if input.runtime_mode != RuntimeMode::ApprovalRequired
            || self.config.runtime_mode != RuntimeMode::ApprovalRequired
        {
            return Err(ProviderError::Unsupported(
                "Pi permission extension supports the approval-required runtime mode only".into(),
            ));
        }
        if matches!(
            input.approval_policy.or(self.config.approval_policy),
            Some(ApprovalPolicy::Untrusted | ApprovalPolicy::OnFailure | ApprovalPolicy::Never)
        ) {
            return Err(ProviderError::Unsupported(
                "Pi permission extension supports the on-request approval policy only".into(),
            ));
        }
        if !input.options.is_empty() {
            return Err(ProviderError::Unsupported(
                "Pi session options are not supported by the RPC adapter".into(),
            ));
        }
        Ok(())
    }

    pub(crate) fn validate_mcp_servers(
        &self,
        input: &SessionStartInput,
    ) -> Result<(), ProviderError> {
        for server in self.config.mcp_servers.iter().chain(&input.mcp_servers) {
            server.validate()?;
            if matches!(&server.transport, McpTransport::Http { .. }) {
                return Err(ProviderError::Unsupported(
                    "Pi MCP injection supports stdio servers only".into(),
                ));
            }
        }
        if input.mcp_servers.is_empty() {
            return Ok(());
        }
        if self.config.mcp_servers.is_empty() {
            return Err(ProviderError::Unsupported(
                "Pi MCP servers must be configured before the process is spawned".into(),
            ));
        }
        if input.mcp_servers != self.config.mcp_servers {
            return Err(ProviderError::Validation(
                "session MCP servers must match the Pi launch configuration".into(),
            ));
        }
        Ok(())
    }
}
