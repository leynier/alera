//! Provider instances: one default per provider plus the ones configured in
//! `<runtimeDir>/agent-chat-providers.json`.

use std::path::{Path, PathBuf};
use std::sync::RwLock;

use serde::Deserialize;
use serde_json::Value;

use super::provider_factory::ProviderInstanceConfig;
use super::provider_traits::PROVIDERS;

pub(crate) const INSTANCES_FILE_NAME: &str = "agent-chat-providers.json";

#[derive(Deserialize)]
#[serde(untagged)]
enum InstancesFile {
    List(Vec<ProviderInstanceConfig>),
    Wrapped {
        instances: Vec<ProviderInstanceConfig>,
    },
}

#[derive(Default)]
pub(crate) struct InstanceDirectory {
    path: Option<PathBuf>,
    instances: RwLock<Vec<ProviderInstanceConfig>>,
    pub(crate) catalog_cache: tokio::sync::Mutex<CatalogCache>,
    pub(crate) catalog_refresh: tokio::sync::Mutex<()>,
}

#[derive(Default)]
pub(crate) struct CatalogCache {
    pub(crate) value: Option<Value>,
    pub(crate) checked: Option<std::time::Instant>,
    pub(crate) revision: u64,
}

impl InstanceDirectory {
    pub(crate) fn from_runtime_dir(runtime_dir: &Path) -> Self {
        let directory = Self {
            path: Some(runtime_dir.join(INSTANCES_FILE_NAME)),
            instances: RwLock::new(Vec::new()),
            ..Default::default()
        };
        directory.reload();
        directory
    }

    #[cfg(test)]
    pub(crate) fn with_instances(instances: Vec<ProviderInstanceConfig>) -> Self {
        Self {
            path: None,
            instances: RwLock::new(instances),
            ..Default::default()
        }
    }

    /// Re-reads the file. A missing or invalid file leaves only the defaults;
    /// the error is logged without the file's contents, which may hold keys.
    pub(crate) fn reload(&self) {
        let Some(path) = &self.path else {
            return;
        };
        let loaded = match std::fs::read(path) {
            Ok(bytes) => match serde_json::from_slice::<InstancesFile>(&bytes) {
                Ok(InstancesFile::List(list) | InstancesFile::Wrapped { instances: list }) => list,
                Err(error) => {
                    tracing::warn!(
                        line = error.line(),
                        "agent chat provider instances file is invalid"
                    );
                    return;
                }
            },
            Err(_) => return,
        };
        let valid = loaded
            .into_iter()
            .filter(|instance| {
                PROVIDERS.contains(&instance.provider.as_str())
                    && !instance.provider_instance_id.trim().is_empty()
                    && !PROVIDERS.contains(&instance.provider_instance_id.as_str())
            })
            .collect();
        if let Ok(mut instances) = self.instances.write() {
            *instances = valid;
        }
    }

    pub(crate) fn configured(&self) -> Vec<ProviderInstanceConfig> {
        self.instances
            .read()
            .map(|list| list.clone())
            .unwrap_or_default()
    }

    pub(crate) fn find(&self, instance_id: &str) -> Option<ProviderInstanceConfig> {
        self.configured()
            .into_iter()
            .find(|instance| instance.provider_instance_id == instance_id)
    }

    pub(crate) async fn replace(&self, configured: Vec<ProviderInstanceConfig>) {
        if let Ok(mut instances) = self.instances.write() {
            *instances = configured;
        }
        let mut cache = self.catalog_cache.lock().await;
        cache.value = None;
        cache.checked = None;
        cache.revision = cache.revision.wrapping_add(1);
    }

    pub(crate) fn enabled(&self, instance_id: &str) -> bool {
        self.find(instance_id)
            .map(|instance| instance.enabled)
            .unwrap_or_else(|| PROVIDERS.contains(&instance_id))
    }

    /// The provider an instance runs. A default instance's id is its
    /// provider's id. A `provider` hint must agree with the instance.
    pub(crate) fn provider_of(&self, instance_id: &str, hint: Option<&str>) -> Option<String> {
        if !self.enabled(instance_id) {
            return None;
        }
        let provider = if PROVIDERS.contains(&instance_id) {
            instance_id.to_string()
        } else {
            self.find(instance_id)?.provider
        };
        match hint {
            Some(hint) if hint != provider => None,
            _ => Some(provider),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_resolve_and_hints_must_agree() {
        let directory = InstanceDirectory::with_instances(vec![ProviderInstanceConfig {
            provider_instance_id: "work-claude".into(),
            provider: "claudeAgent".into(),
            ..Default::default()
        }]);
        assert_eq!(
            directory.provider_of("codex", None).as_deref(),
            Some("codex")
        );
        assert_eq!(
            directory
                .provider_of("work-claude", Some("claudeAgent"))
                .as_deref(),
            Some("claudeAgent")
        );
        assert!(directory
            .provider_of("work-claude", Some("codex"))
            .is_none());
        assert!(directory.provider_of("missing", None).is_none());
    }

    #[test]
    fn file_entries_for_unknown_providers_are_ignored() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join(INSTANCES_FILE_NAME),
            r#"{"instances": [
                {"providerInstanceId": "a", "provider": "nope"},
                {"providerInstanceId": "codex", "provider": "codex"},
                {"providerInstanceId": "local-acp", "provider": "acpRegistry",
                 "executable": "/opt/agent", "env": {"KEY": "secret"}}
            ]}"#,
        )
        .unwrap();
        let directory = InstanceDirectory::from_runtime_dir(dir.path());
        let configured = directory.configured();
        assert_eq!(configured.len(), 1);
        assert_eq!(configured[0].provider_instance_id, "local-acp");
    }
}
