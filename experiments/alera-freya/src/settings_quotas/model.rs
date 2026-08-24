use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub(super) const PROVIDERS: [(&str, &str, &str); 8] = [
    (
        "claude",
        "Claude Code",
        "Read default and CCS profile usage.",
    ),
    ("codex", "Codex", "Read official app-server rate limits."),
    ("kimi", "Kimi", "Read Coding Plan usage with an API key."),
    (
        "grok",
        "Grok Build",
        "Read usage through the official interactive CLI.",
    ),
    (
        "cursor",
        "Cursor",
        "Read plan usage from the local CLI session.",
    ),
    (
        "antigravity",
        "Antigravity",
        "Read usage through the official Agy CLI.",
    ),
    (
        "minimax",
        "MiniMax",
        "Read token plan usage with an API key.",
    ),
    ("zai", "Z.ai", "Read limits with an API key."),
];

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(crate) struct ClaudeProfile {
    pub(super) alias: String,
    pub(crate) profile: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct QuotaEnvironment {
    pub(super) kimi_api_key: String,
    pub(super) zai_api_key: String,
    pub(super) zai_base_url: String,
    pub(super) minimax_api_key: String,
    pub(super) minimax_api_host: String,
}

impl Default for QuotaEnvironment {
    fn default() -> Self {
        Self {
            kimi_api_key: "KIMI_API_KEY".to_string(),
            zai_api_key: "ZAI_API_KEY".to_string(),
            zai_base_url: "ZAI_BASE_URL".to_string(),
            minimax_api_key: "MINIMAX_API_KEY".to_string(),
            minimax_api_host: "MINIMAX_API_HOST".to_string(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub(crate) struct QuotaSettings {
    pub(crate) enabled_providers: Vec<String>,
    pub(crate) claude_default_enabled: bool,
    pub(crate) claude_profiles: Vec<ClaudeProfile>,
    pub(super) selected_claude_profile: String,
    pub(super) environment: QuotaEnvironment,
    pub(super) unpinned_quota_keys: Vec<String>,
}

impl Default for QuotaSettings {
    fn default() -> Self {
        Self {
            enabled_providers: PROVIDERS
                .iter()
                .map(|(provider, _, _)| (*provider).to_string())
                .collect(),
            claude_default_enabled: true,
            claude_profiles: Vec::new(),
            selected_claude_profile: "default".to_string(),
            environment: QuotaEnvironment::default(),
            unpinned_quota_keys: Vec::new(),
        }
    }
}

impl QuotaSettings {
    pub(super) fn from_runtime(value: &Value) -> Self {
        value
            .get("agentQuotas")
            .cloned()
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default()
    }

    pub(crate) fn payload(&self) -> Value {
        json!({"agentQuotas": self})
    }

    pub(super) fn toggle_provider(&mut self, provider: &str) {
        if let Some(index) = self
            .enabled_providers
            .iter()
            .position(|candidate| candidate == provider)
        {
            self.enabled_providers.remove(index);
        } else {
            self.enabled_providers.push(provider.to_string());
        }
    }

    pub(super) fn move_provider(&mut self, provider: &str, delta: isize) {
        let Some(index) = self
            .enabled_providers
            .iter()
            .position(|candidate| candidate == provider)
        else {
            return;
        };
        let next = index.saturating_add_signed(delta);
        if next < self.enabled_providers.len() {
            self.enabled_providers.swap(index, next);
        }
    }

    pub(crate) fn is_pinned(&self, key: &str) -> bool {
        !self
            .unpinned_quota_keys
            .iter()
            .any(|candidate| candidate == key)
    }

    pub(crate) fn toggle_pin(&mut self, key: &str) {
        if let Some(index) = self
            .unpinned_quota_keys
            .iter()
            .position(|candidate| candidate == key)
        {
            self.unpinned_quota_keys.remove(index);
        } else {
            self.unpinned_quota_keys.push(key.to_string());
        }
    }

    pub(super) fn normalize_profiles(&mut self) {
        let valid = self.selected_claude_profile == "default"
            || self
                .claude_profiles
                .iter()
                .any(|profile| profile.profile == self.selected_claude_profile);
        if !valid {
            self.selected_claude_profile = "default".to_string();
        }
        self.unpinned_quota_keys.retain(|key| {
            !key.starts_with("claude:")
                || key == "claude:default"
                || self
                    .claude_profiles
                    .iter()
                    .any(|profile| key == &format!("claude:{}", profile.profile))
        });
    }
}

pub(super) fn parse_environment_presence(value: &Value) -> BTreeMap<String, bool> {
    value
        .get("environment")
        .and_then(Value::as_object)
        .into_iter()
        .flatten()
        .filter_map(|(name, present)| present.as_bool().map(|value| (name.clone(), value)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_order_and_toggle_preserve_enabled_sources() {
        let mut settings = QuotaSettings::default();
        settings.move_provider("codex", 1);
        assert_eq!(settings.enabled_providers[2], "codex");
        settings.toggle_provider("codex");
        assert!(!settings.enabled_providers.contains(&"codex".to_string()));
        settings.toggle_provider("codex");
        assert_eq!(
            settings.enabled_providers.last().map(String::as_str),
            Some("codex")
        );
    }

    #[test]
    fn removing_a_profile_cleans_selection_and_only_its_pin() {
        let mut settings = QuotaSettings {
            claude_profiles: vec![ClaudeProfile {
                alias: "Work".to_string(),
                profile: "work".to_string(),
            }],
            selected_claude_profile: "missing".to_string(),
            unpinned_quota_keys: vec![
                "claude:missing".to_string(),
                "claude:default".to_string(),
                "codex".to_string(),
            ],
            ..QuotaSettings::default()
        };
        settings.normalize_profiles();
        assert_eq!(settings.selected_claude_profile, "default");
        assert_eq!(
            settings.unpinned_quota_keys,
            vec!["claude:default".to_string(), "codex".to_string()]
        );
    }

    #[test]
    fn environment_presence_never_exposes_secret_values() {
        let presence = parse_environment_presence(&json!({
            "environment": {"KIMI_API_KEY": true, "ZAI_API_KEY": false}
        }));
        assert_eq!(presence.get("KIMI_API_KEY"), Some(&true));
        assert_eq!(presence.get("ZAI_API_KEY"), Some(&false));
    }
}
