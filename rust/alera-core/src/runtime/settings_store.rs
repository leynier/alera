use anyhow::Result;

use super::{
    RuntimeAgentQuotaSettings, RuntimeAgentStatusHookSettings, RuntimeAiTextGenerationSettings,
    RuntimeMobilePushSettings, RuntimeSettings, RuntimeStore,
};

impl RuntimeStore {
    pub async fn runtime_settings(&self) -> Result<RuntimeSettings> {
        Ok(RuntimeSettings {
            workspace_directory: self.get_workspace_directory().await?,
            confirm_project_removal: self.confirm_project_removal().await?,
            confirm_workspace_removal: self.confirm_workspace_removal().await?,
            default_agent_profile_id: self.default_agent_profile_id().await?,
            agent_status_hooks: self.agent_status_hook_settings().await?,
            agent_quotas: self.agent_quota_settings().await?,
            mobile_push_notifications: self.mobile_push_settings().await?,
            ai_text_generation: self.ai_text_generation_settings().await?,
        })
    }

    pub async fn mobile_push_settings(&self) -> Result<RuntimeMobilePushSettings> {
        let Some(encoded) = self
            .get_metadata("settings.mobile.pushNotifications")
            .await?
        else {
            return Ok(RuntimeMobilePushSettings::default());
        };
        Ok(serde_json::from_str(&encoded).unwrap_or_default())
    }

    pub async fn set_mobile_push_settings(
        &self,
        settings: &RuntimeMobilePushSettings,
    ) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.mobile.pushNotifications",
            &serde_json::to_string(settings)?,
        )
        .await?;
        self.runtime_settings().await
    }

    pub async fn ai_text_generation_settings(
        &self,
    ) -> Result<Option<RuntimeAiTextGenerationSettings>> {
        let Some(encoded) = self.get_metadata("settings.aiTextGeneration").await? else {
            return Ok(None);
        };
        Ok(
            serde_json::from_str::<RuntimeAiTextGenerationSettings>(&encoded)
                .ok()
                .map(RuntimeAiTextGenerationSettings::normalized),
        )
    }

    pub async fn effective_ai_text_generation_settings(
        &self,
    ) -> Result<RuntimeAiTextGenerationSettings> {
        Ok(self
            .ai_text_generation_settings()
            .await?
            .unwrap_or_default())
    }

    pub async fn set_ai_text_generation_settings(
        &self,
        settings: RuntimeAiTextGenerationSettings,
    ) -> Result<RuntimeSettings> {
        self.set_metadata(
            "settings.aiTextGeneration",
            &serde_json::to_string(&settings.normalized())?,
        )
        .await?;
        self.runtime_settings().await
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

    pub async fn default_agent_profile_id(&self) -> Result<Option<String>> {
        Ok(self
            .get_metadata("settings.agents.defaultAgentProfileId")
            .await?
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()))
    }

    pub async fn set_default_agent_profile_id(
        &self,
        profile_id: Option<&str>,
    ) -> Result<RuntimeSettings> {
        match profile_id.map(str::trim).filter(|value| !value.is_empty()) {
            Some(value) => {
                self.set_metadata("settings.agents.defaultAgentProfileId", value)
                    .await?;
            }
            None => {
                sqlx::query("DELETE FROM runtimeMetadata WHERE key = ?")
                    .bind("settings.agents.defaultAgentProfileId")
                    .execute(self.pool())
                    .await?;
            }
        }
        self.runtime_settings().await
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
