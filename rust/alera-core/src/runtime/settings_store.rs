use anyhow::Result;

use super::{
    RuntimeAgentQuotaSettings, RuntimeAgentStatusHookSettings, RuntimeSettings, RuntimeStore,
};

impl RuntimeStore {
    pub async fn runtime_settings(&self) -> Result<RuntimeSettings> {
        Ok(RuntimeSettings {
            workspace_directory: self.get_workspace_directory().await?,
            confirm_project_removal: self.confirm_project_removal().await?,
            confirm_workspace_removal: self.confirm_workspace_removal().await?,
            agent_status_hooks: self.agent_status_hook_settings().await?,
            agent_quotas: self.agent_quota_settings().await?,
        })
    }

    pub async fn agent_quota_settings(&self) -> Result<RuntimeAgentQuotaSettings> {
        let Some(encoded) = self.get_metadata("settings.agents.quotas").await? else {
            return Ok(RuntimeAgentQuotaSettings::default());
        };
        Ok(serde_json::from_str::<RuntimeAgentQuotaSettings>(&encoded)
            .unwrap_or_default()
            .normalized())
    }

    pub async fn set_agent_quota_settings(
        &self,
        settings: RuntimeAgentQuotaSettings,
    ) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.agents.quotas",
            &serde_json::to_string(&settings.normalized())?,
        )
        .await?;
        self.runtime_settings().await
    }

    pub async fn agent_status_hook_settings(&self) -> Result<RuntimeAgentStatusHookSettings> {
        let Some(encoded) = self
            .get_metadata("settings.agents.agentStatusHooks")
            .await?
        else {
            return Ok(RuntimeAgentStatusHookSettings::default());
        };
        Ok(serde_json::from_str(&encoded).unwrap_or_default())
    }

    pub async fn set_agent_status_hook_settings(
        &self,
        settings: &RuntimeAgentStatusHookSettings,
    ) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.agents.agentStatusHooks",
            &serde_json::to_string(settings)?,
        )
        .await?;
        self.runtime_settings().await
    }

    pub async fn confirm_workspace_removal(&self) -> Result<bool> {
        Ok(self
            .get_metadata("settings.general.confirmWorkspaceRemoval")
            .await?
            .and_then(|value| value.parse::<bool>().ok())
            .unwrap_or(true))
    }

    pub async fn confirm_project_removal(&self) -> Result<bool> {
        Ok(self
            .get_metadata("settings.general.confirmProjectRemoval")
            .await?
            .and_then(|value| value.parse::<bool>().ok())
            .unwrap_or(true))
    }

    pub async fn set_confirm_project_removal(&self, value: bool) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.general.confirmProjectRemoval",
            if value { "true" } else { "false" },
        )
        .await?;
        self.runtime_settings().await
    }

    pub async fn set_confirm_workspace_removal(&self, value: bool) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.general.confirmWorkspaceRemoval",
            if value { "true" } else { "false" },
        )
        .await?;
        self.runtime_settings().await
    }
}
