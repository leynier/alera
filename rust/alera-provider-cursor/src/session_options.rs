use super::*;

impl CursorProvider {
    pub(super) fn agent_options(
        &self,
        input: &SessionStartInput,
    ) -> Result<AgentOptions, ProviderError> {
        Ok(AgentOptions {
            model: self.model_selection(
                input.model.clone().or_else(|| self.config.model.clone()),
                alera_provider_protocol::reasoning_effort(&input.options)?,
            )?,
            api_key: self.config.api_key.clone(),
            name: None,
            local: Some(LocalAgentOptions {
                cwd: input
                    .cwd
                    .clone()
                    .or_else(|| self.config.cwd.clone())
                    .map(|path| vec![path.to_string_lossy().into_owned()])
                    .unwrap_or_default(),
                sandbox_options: Some(serde_json::json!({ "enabled": true })),
                auto_review: Some(true),
            }),
            mode: None,
            mcp_servers: native_mcp_servers(&input.mcp_servers)?,
        })
    }
}
