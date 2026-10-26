//! Production provider inspection stays independent of chat lifecycle.
use super::super::provider_factory::{
    ProviderFactory, ProviderInstanceConfig, ProviderLaunch, ProviderStatus,
};
use super::{
    build_config, executable_available, hydrated_environment, opencode_generation, ProductionConfig,
};
use crate::terminal_host::server::agent_chat_provider_settings::{
    credentials::{ProviderCredentialStore, ProviderSecrets},
    discovery,
    probe::WindowlessProviderProbe,
    status,
};
use alera_provider_protocol::ProviderError;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
pub(super) async fn status(
    factory: &super::ProductionProviderFactory,
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
) -> ProviderStatus {
    let setup_required = provider == "acpRegistry"
        && instance
            .and_then(|instance| instance.executable.as_ref())
            .is_none_or(|path| path.as_os_str().to_string_lossy().trim().is_empty());
    let availability = if setup_required {
        Err("Configure an executable in Providers Settings.".into())
    } else {
        factory
            .availability(provider, instance)
            .await
            .map_err(|_| "Provider is unavailable.".to_owned())
    };
    let mut result = ProviderStatus {
        available: availability.is_ok(),
        setup_required,
        installed: None,
        version: None,
        auth_status: "unknown".into(),
        unavailable_reason: availability.err(),
        setup: serde_json::json!([]),
    };
    if setup_required {
        return result;
    }
    let Ok(instance) = resolve_instance(instance).await else {
        result.available = false;
        result.unavailable_reason = Some("Provider credentials are unavailable.".into());
        return result;
    };
    let Ok(environment) = hydrated_environment(instance.as_ref(), &BTreeMap::new()).await else {
        result.available = false;
        result.unavailable_reason = Some("Provider environment is unavailable.".into());
        return result;
    };
    let launch = probe_launch(provider, instance.as_ref(), None);
    let Ok(config) = build_config(&launch, &environment) else {
        result.available = false;
        result.unavailable_reason = Some("Provider launch configuration is invalid.".into());
        return result;
    };
    let executable = config_executable(&config);
    if let Some(executable) = executable {
        result.installed = Some(executable_available(Some(executable), "", &environment).is_ok());
        if result.installed == Some(false) {
            result.available = false;
            result.unavailable_reason = Some("Provider executable is unavailable.".into());
        }
        if result.installed == Some(true)
            && matches!(
                provider,
                "codex" | "claudeAgent" | "opencode" | "grok" | "antigravity" | "pi"
            )
        {
            let (version, auth) =
                status::cli_status(provider, executable, &environment, &WindowlessProviderProbe)
                    .await;
            result.version = version;
            result.auth_status = auth;
            if result.auth_status == "signedOut" {
                result.available = false;
                result.unavailable_reason = Some("Sign in to use this agent.".into());
            }
        }
    } else if let ProductionConfig::Cursor(config, None) = &config {
        if let Some(key) = &config.api_key {
            if let Ok(client) = cursor_agent_sdk::CursorClient::connect(config.client_config()) {
                if matches!(
                    tokio::time::timeout(std::time::Duration::from_secs(8), client.me(key)).await,
                    Ok(Ok(_))
                ) {
                    result.auth_status = "signedIn".into();
                }
            }
        }
    }
    if !instance.as_ref().is_some_and(|instance| {
        instance.args.as_ref().is_some_and(|args| !args.is_empty()) || !instance.options.is_empty()
    }) {
        result.setup = status::setup(provider, executable, result.installed, &result.auth_status);
    }
    result
}

pub(super) async fn models(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
) -> Option<Result<Vec<serde_json::Value>, String>> {
    let cache_key = effort_cache_key(provider, instance);
    if !matches!(
        provider,
        "codex" | "pi" | "antigravity" | "opencode" | "cursor"
    ) {
        return None;
    }
    let instance = match resolve_instance(instance).await {
        Ok(instance) => instance,
        Err(_) => return Some(Err("Provider credentials are unavailable.".into())),
    };
    let environment = match hydrated_environment(instance.as_ref(), &BTreeMap::new()).await {
        Ok(env) => env,
        Err(_) => return Some(Err("Provider environment is unavailable.".into())),
    };
    let launch = probe_launch(provider, instance.as_ref(), cwd.clone());
    let config = match build_config(&launch, &environment) {
        Ok(config) => config,
        Err(_) => return Some(Err("Provider launch configuration is invalid.".into())),
    };
    let result = match config {
        ProductionConfig::Cursor(config, bridge) => {
            Some(discovery::cursor(*config, bridge.map(|bridge| *bridge)).await)
        }
        ProductionConfig::OpenCode(mut config) => {
            if opencode_generation::resolve(&launch, &mut config)
                .await
                .is_err()
            {
                Some(Err("OpenCode protocol discovery failed.".into()))
            } else {
                Some(discovery::opencode(*config).await)
            }
        }
        config => {
            discovery::cli_models(
                provider,
                config_executable(&config).expect("CLI provider"),
                &environment,
                cwd,
                &WindowlessProviderProbe,
            )
            .await
        }
    };
    if matches!(provider, "codex" | "cursor") {
        if let Some(Ok(models)) = &result {
            cache_effort_models(cache_key, models.clone()).await;
        } else {
            effort_cache().lock().await.remove(&cache_key);
        }
    }
    result
}

pub(super) async fn validate_effort(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
    model: Option<&str>,
    effort: &str,
) -> Result<(), String> {
    if !matches!(provider, "codex" | "cursor") {
        return Err("This agent does not support reasoning effort.".into());
    }
    let models = match cached_effort_models(provider, instance).await {
        Some(models) => models,
        None => models(provider, instance, cwd)
            .await
            .and_then(Result::ok)
            .ok_or("Reasoning effort metadata could not be verified.")?,
    };
    let selected =
        model.or_else(|| instance.and_then(|instance| instance.default_model.as_deref()));
    let model = models
        .iter()
        .find(|entry| match selected {
            Some(model) => entry["id"].as_str() == Some(model),
            None => entry["providerDefault"] == true,
        })
        .ok_or("Reasoning effort is unavailable for the selected model.")?;
    if model["reasoningEfforts"]
        .as_array()
        .is_some_and(|entries| entries.iter().any(|entry| entry.as_str() == Some(effort)))
    {
        Ok(())
    } else {
        Err("The selected model does not support this reasoning effort.".into())
    }
}
pub(super) fn probe_launch(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
) -> ProviderLaunch {
    ProviderLaunch {
        chat_id: "provider-catalog".into(),
        generation: 0,
        provider: provider.into(),
        provider_instance_id: instance
            .map(|instance| instance.provider_instance_id.clone())
            .unwrap_or_else(|| provider.into()),
        cwd,
        model: None,
        runtime_mode: Default::default(),
        instance: instance.cloned(),
        mcp_servers: Vec::new(),
        env: BTreeMap::new(),
    }
}

fn config_executable(config: &ProductionConfig) -> Option<&Path> {
    match config {
        ProductionConfig::Codex(config) => Some(&config.executable),
        ProductionConfig::Claude(config) => Some(
            config
                .options
                .cli_path
                .as_deref()
                .unwrap_or_else(|| Path::new("claude")),
        ),
        ProductionConfig::Cursor(_, Some(bridge)) => Some(&bridge.process.executable),
        ProductionConfig::Grok(config) => Some(&config.executable),
        ProductionConfig::Antigravity(config) => Some(&config.executable),
        ProductionConfig::Registry(config) => config.executable.as_deref(),
        ProductionConfig::Pi(config) => Some(&config.executable),
        ProductionConfig::Muse(config) => Some(&config.options.executable),
        ProductionConfig::OpenCode(config) if config.server_url.is_none() => {
            Some(&config.executable)
        }
        _ => None,
    }
}

pub(super) async fn resolve_instance(
    instance: Option<&ProviderInstanceConfig>,
) -> Result<Option<ProviderInstanceConfig>, ProviderError> {
    let Some(instance) = instance else {
        return Ok(None);
    };
    let mut resolved = instance.clone();
    if !instance.enabled {
        return Err(ProviderError::InvalidState(
            "This agent is turned off.".into(),
        ));
    }
    if !instance.secret_refs.is_empty() {
        let (directory, runtime) = instance.credential_scope.as_ref().ok_or_else(|| {
            ProviderError::Validation("Provider credential scope is unavailable.".into())
        })?;
        let store = ProviderCredentialStore::new(directory, runtime);
        for (name, reference) in &instance.secret_refs {
            let value = store
                .load(reference)
                .await
                .map_err(|_| {
                    ProviderError::Validation("Provider credentials are unavailable.".into())
                })?
                .ok_or_else(|| {
                    ProviderError::Validation(
                        "A saved provider credential is missing. Replace it in Providers Settings."
                            .into(),
                    )
                })?;
            if let Some(key) = name.strip_prefix("option:") {
                resolved
                    .options
                    .insert(key.into(), serde_json::Value::String(value));
            } else {
                resolved.env.insert(name.clone(), value);
            }
        }
    }
    Ok(Some(resolved))
}

type EffortCache = std::collections::HashMap<String, (std::time::Instant, Vec<serde_json::Value>)>;
fn effort_cache() -> &'static tokio::sync::Mutex<EffortCache> {
    static CACHE: std::sync::OnceLock<tokio::sync::Mutex<EffortCache>> = std::sync::OnceLock::new();
    CACHE.get_or_init(Default::default)
}
fn effort_cache_key(provider: &str, instance: Option<&ProviderInstanceConfig>) -> String {
    alera_core::runtime::agent_chat_command_digest(
        &serde_json::json!({"provider":provider,"instance":instance,"scope":instance.and_then(|instance| instance.credential_scope.as_ref()),"secretRefs":instance.map(|instance| &instance.secret_refs)}),
    )
}
async fn cache_effort_models(cache_key: String, models: Vec<serde_json::Value>) {
    let mut cache = effort_cache().lock().await;
    cache.retain(|_, (time, _)| time.elapsed() < std::time::Duration::from_secs(120));
    if cache.len() >= 500 {
        cache.clear();
    }
    cache.insert(cache_key, (std::time::Instant::now(), models));
}
pub(super) async fn cached_effort_models(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
) -> Option<Vec<serde_json::Value>> {
    effort_cache()
        .lock()
        .await
        .get(&effort_cache_key(provider, instance))
        .filter(|(time, _)| time.elapsed() < std::time::Duration::from_secs(120))
        .map(|(_, models)| models.clone())
}

pub(super) async fn cached_auth_evidence(
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
) -> Option<(String, String)> {
    if provider != "cursor" {
        return None;
    }
    let cache = effort_cache().lock().await;
    let (checked, _) = cache.get(&effort_cache_key(provider, instance))?;
    let age = checked.elapsed();
    if age >= std::time::Duration::from_secs(120) {
        return None;
    }
    let timestamp = chrono::Utc::now() - chrono::Duration::from_std(age).ok()?;
    Some(("signedIn".into(), timestamp.to_rfc3339()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn effort_validation_uses_exact_provider_instance_and_model_metadata() {
        let instance = ProviderInstanceConfig {
            provider_instance_id: uuid::Uuid::new_v4().to_string(),
            provider: "codex".into(),
            ..Default::default()
        };
        cache_effort_models(
            effort_cache_key("codex", Some(&instance)),
            vec![json!({"id":"exact-model","reasoningEfforts":["medium","high"]})],
        )
        .await;
        assert!(
            validate_effort("codex", Some(&instance), None, Some("exact-model"), "high")
                .await
                .is_ok()
        );
        assert!(
            validate_effort("codex", Some(&instance), None, Some("exact-model"), "xhigh")
                .await
                .is_err()
        );
        assert!(
            validate_effort("codex", Some(&instance), None, Some("custom-model"), "high")
                .await
                .is_err()
        );
        assert!(
            validate_effort("codex", Some(&instance), None, None, "high")
                .await
                .is_err()
        );
        assert!(
            validate_effort("pi", Some(&instance), None, Some("exact-model"), "high")
                .await
                .is_err()
        );
        assert!(cached_effort_models("cursor", Some(&instance))
            .await
            .is_none());
        assert!(cached_auth_evidence("codex", Some(&instance))
            .await
            .is_none());
    }

    #[tokio::test]
    async fn cursor_auth_proof_preserves_check_time_and_expires_with_metadata() {
        let instance = ProviderInstanceConfig {
            provider_instance_id: uuid::Uuid::new_v4().to_string(),
            provider: "cursor".into(),
            ..Default::default()
        };
        let key = effort_cache_key("cursor", Some(&instance));
        cache_effort_models(
            key.clone(),
            vec![json!({"id":"exact-cursor-model","reasoningEfforts":["low"]})],
        )
        .await;
        let (auth, timestamp) = cached_auth_evidence("cursor", Some(&instance))
            .await
            .unwrap();
        assert_eq!(auth, "signedIn");
        assert!(chrono::DateTime::parse_from_rfc3339(&timestamp).is_ok());
        assert!(validate_effort(
            "cursor",
            Some(&instance),
            None,
            Some("exact-cursor-model"),
            "low"
        )
        .await
        .is_ok());
        effort_cache().lock().await.get_mut(&key).unwrap().0 =
            std::time::Instant::now() - std::time::Duration::from_secs(121);
        assert!(cached_effort_models("cursor", Some(&instance))
            .await
            .is_none());
        assert!(cached_auth_evidence("cursor", Some(&instance))
            .await
            .is_none());
    }
}
