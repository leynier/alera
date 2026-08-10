use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentQuotaSettings {
    #[serde(default = "default_quota_providers")]
    pub enabled_providers: Vec<String>,
    #[serde(default = "default_true")]
    pub claude_default_enabled: bool,
    #[serde(default = "default_true")]
    pub claude_default_show_in_usage: bool,
    #[serde(default)]
    pub claude_profiles: Vec<RuntimeClaudeQuotaProfile>,
    #[serde(default)]
    pub environment: RuntimeAgentQuotaEnvironment,
}

impl Default for RuntimeAgentQuotaSettings {
    fn default() -> Self {
        Self {
            enabled_providers: default_quota_providers(),
            claude_default_enabled: true,
            claude_default_show_in_usage: true,
            claude_profiles: Vec::new(),
            environment: RuntimeAgentQuotaEnvironment::default(),
        }
    }
}

impl RuntimeAgentQuotaSettings {
    pub fn normalized(mut self) -> Self {
        const SUPPORTED: [&str; 9] = [
            "claude",
            "codex",
            "kimi",
            "grok",
            "cursor",
            "antigravity",
            "minimax",
            "zai",
            "opencode",
        ];
        let mut seen = std::collections::HashSet::new();
        self.enabled_providers.retain(|provider| {
            SUPPORTED.contains(&provider.as_str()) && seen.insert(provider.clone())
        });
        for profile in &mut self.claude_profiles {
            profile.alias = profile.alias.trim().to_string();
            profile.profile = profile.profile.trim().to_string();
            profile.usage_display_name = profile
                .usage_display_name
                .take()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty());
        }
        self.claude_profiles
            .retain(|profile| !profile.alias.is_empty() && !profile.profile.is_empty());
        self.environment.normalize();
        self
    }

    pub fn claude_profiles_for_usage(&self) -> Vec<RuntimeClaudeQuotaProfile> {
        self.claude_profiles
            .iter()
            .filter(|profile| profile.show_in_usage)
            .cloned()
            .map(|mut profile| {
                profile.alias = profile.usage_label().to_string();
                profile
            })
            .collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeClaudeQuotaProfile {
    pub alias: String,
    pub profile: String,
    #[serde(default = "default_true")]
    pub show_in_usage: bool,
    #[serde(default)]
    pub usage_display_name: Option<String>,
}

impl RuntimeClaudeQuotaProfile {
    pub fn usage_label(&self) -> &str {
        self.usage_display_name.as_deref().unwrap_or(&self.alias)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentQuotaEnvironment {
    #[serde(default = "default_kimi_api_key")]
    pub kimi_api_key: String,
    #[serde(default = "default_zai_api_key")]
    pub zai_api_key: String,
    #[serde(default = "default_zai_base_url")]
    pub zai_base_url: String,
    #[serde(default = "default_minimax_api_key")]
    pub minimax_api_key: String,
    #[serde(default = "default_minimax_api_host")]
    pub minimax_api_host: String,
}

impl Default for RuntimeAgentQuotaEnvironment {
    fn default() -> Self {
        Self {
            kimi_api_key: default_kimi_api_key(),
            zai_api_key: default_zai_api_key(),
            zai_base_url: default_zai_base_url(),
            minimax_api_key: default_minimax_api_key(),
            minimax_api_host: default_minimax_api_host(),
        }
    }
}

impl RuntimeAgentQuotaEnvironment {
    fn normalize(&mut self) {
        self.kimi_api_key = non_blank_or(&self.kimi_api_key, default_kimi_api_key);
        self.zai_api_key = non_blank_or(&self.zai_api_key, default_zai_api_key);
        self.zai_base_url = non_blank_or(&self.zai_base_url, default_zai_base_url);
        self.minimax_api_key = non_blank_or(&self.minimax_api_key, default_minimax_api_key);
        self.minimax_api_host = non_blank_or(&self.minimax_api_host, default_minimax_api_host);
    }
}

fn default_quota_providers() -> Vec<String> {
    [
        "claude",
        "codex",
        "kimi",
        "grok",
        "cursor",
        "antigravity",
        "minimax",
        "zai",
        "opencode",
    ]
    .into_iter()
    .map(str::to_string)
    .collect()
}

fn non_blank_or(value: &str, fallback: fn() -> String) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback()
    } else {
        value.to_string()
    }
}

fn default_kimi_api_key() -> String {
    "KIMI_API_KEY".to_string()
}

fn default_zai_api_key() -> String {
    "ZAI_API_KEY".to_string()
}

fn default_zai_base_url() -> String {
    "ZAI_BASE_URL".to_string()
}

fn default_minimax_api_key() -> String {
    "MINIMAX_API_KEY".to_string()
}

fn default_minimax_api_host() -> String {
    "MINIMAX_API_HOST".to_string()
}

fn default_true() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_claude_profiles_are_visible_in_usage_by_default() {
        let profile: RuntimeClaudeQuotaProfile = serde_json::from_value(serde_json::json!({
            "alias": "ccdev",
            "profile": "dev"
        }))
        .expect("legacy profile");

        assert!(profile.show_in_usage);
        assert_eq!(profile.usage_label(), "ccdev");

        let settings: RuntimeAgentQuotaSettings =
            serde_json::from_value(serde_json::json!({ "claudeDefaultEnabled": false }))
                .expect("legacy settings");
        assert!(!settings.claude_default_enabled);
        assert!(settings.claude_default_show_in_usage);
    }

    #[test]
    fn usage_profiles_are_filtered_renamed_and_normalized() {
        let settings = RuntimeAgentQuotaSettings {
            claude_profiles: vec![
                RuntimeClaudeQuotaProfile {
                    alias: " ccdev ".to_string(),
                    profile: " dev ".to_string(),
                    show_in_usage: true,
                    usage_display_name: Some(" Engineering ".to_string()),
                },
                RuntimeClaudeQuotaProfile {
                    alias: "ccshared".to_string(),
                    profile: "shared".to_string(),
                    show_in_usage: false,
                    usage_display_name: Some("Shared".to_string()),
                },
            ],
            ..RuntimeAgentQuotaSettings::default()
        }
        .normalized();

        let profiles = settings.claude_profiles_for_usage();
        assert_eq!(profiles.len(), 1);
        assert_eq!(profiles[0].profile, "dev");
        assert_eq!(profiles[0].alias, "Engineering");
    }
}
