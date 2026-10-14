//! One bounded, cached host catalog shared by Settings and chat composers.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use futures_util::{stream, StreamExt};
use serde_json::{json, Value};

use super::provider_factory::{ProviderFactory, ProviderInstanceConfig};
use super::provider_traits::{capabilities_json, mcp_injection_source, provider_traits, PROVIDERS};
use super::InstanceDirectory;

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(15);
const CACHE_TTL: Duration = Duration::from_secs(120);
const MAX_CONCURRENT_PROBES: usize = 4;

#[cfg(test)]
#[path = "provider_catalog_tests.rs"]
mod tests;

pub(crate) async fn provider_catalog(
    factory: Arc<dyn ProviderFactory>,
    instances: Arc<InstanceDirectory>,
    cwd: Option<PathBuf>,
    refresh: bool,
) -> Value {
    if !refresh {
        let cache = instances.catalog_cache.lock().await;
        if let Some(value) = &cache.value {
            let value = value.clone();
            if cache
                .checked
                .is_some_and(|checked| checked.elapsed() >= CACHE_TTL)
            {
                let factory = factory.clone();
                let instances = instances.clone();
                tokio::spawn(async move {
                    if let Ok(_guard) = instances.catalog_refresh.try_lock() {
                        refresh_catalog(&*factory, &instances, cwd).await;
                    }
                });
            }
            return value;
        }
    }
    let _guard = instances.catalog_refresh.lock().await;
    if !refresh {
        let cache = instances.catalog_cache.lock().await;
        if let Some(value) = &cache.value {
            return value.clone();
        }
    }
    refresh_catalog(&*factory, &instances, cwd).await
}

async fn refresh_catalog(
    factory: &dyn ProviderFactory,
    instances: &InstanceDirectory,
    cwd: Option<PathBuf>,
) -> Value {
    loop {
        let revision = instances.catalog_cache.lock().await.revision;
        let configured = instances.configured();
        let mut entries: Vec<(String, Option<ProviderInstanceConfig>)> = PROVIDERS
            .iter()
            .map(|provider| {
                (
                    provider.to_string(),
                    configured
                        .iter()
                        .find(|instance| instance.provider_instance_id == *provider)
                        .cloned(),
                )
            })
            .collect();
        entries.extend(
            configured
                .into_iter()
                .filter(|instance| !PROVIDERS.contains(&instance.provider_instance_id.as_str()))
                .map(|instance| (instance.provider.clone(), Some(instance))),
        );
        let providers: Vec<Value> = stream::iter(
            entries
                .into_iter()
                .map(|(provider, instance)| entry(factory, provider, instance, cwd.clone())),
        )
        .buffered(MAX_CONCURRENT_PROBES)
        .collect()
        .await;
        let value = json!({"providers":providers,"checkedAt":chrono::Utc::now().to_rfc3339()});
        let mut cache = instances.catalog_cache.lock().await;
        // A settings edit during a probe must not publish the old configuration.
        if cache.revision == revision {
            cache.checked = Some(Instant::now());
            cache.value = Some(value.clone());
            return value;
        }
    }
}

async fn entry(
    factory: &dyn ProviderFactory,
    provider: String,
    instance: Option<ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
) -> Value {
    let traits = provider_traits(&provider);
    let enabled = instance.as_ref().is_none_or(|instance| instance.enabled);
    let mut status = tokio::time::timeout(
        Duration::from_secs(20),
        factory.status(&provider, instance.as_ref()),
    )
    .await
    .unwrap_or_else(|_| super::provider_factory::ProviderStatus {
        available: false,
        setup_required: false,
        installed: None,
        version: None,
        auth_status: "unknown".into(),
        unavailable_reason: Some("Agent status check timed out.".into()),
        setup: json!([]),
    });
    let (models, source, models_error) = models(
        factory,
        &provider,
        instance.as_ref(),
        cwd,
        enabled && status.available,
    )
    .await;
    let mut auth_checked_at = None;
    if status.auth_status == "unknown" {
        if let Some((auth, checked)) = factory
            .cached_verified_auth_status(&provider, instance.as_ref())
            .await
        {
            status.auth_status = auth;
            auth_checked_at = Some(checked);
        }
    }
    let mut capabilities = capabilities_json(&provider, None);
    if provider == "opencode"
        && instance
            .as_ref()
            .is_some_and(|instance| instance.options.contains_key("serverUrl"))
    {
        capabilities["mcpInjection"] = json!({"stdio": false, "http": false});
    }
    let checked_at = chrono::Utc::now().to_rfc3339();
    json!({
        "provider":provider,
        "providerInstanceId":instance.as_ref().map(|instance| instance.provider_instance_id.clone()).unwrap_or_else(|| provider.clone()),
        "label":instance.as_ref().and_then(|instance| instance.label.clone()).or_else(|| traits.as_ref().map(|traits| traits.label.to_string())),
        "custom":instance.as_ref().is_some_and(|instance| !PROVIDERS.contains(&instance.provider_instance_id.as_str())),
        "enabled":enabled,"available":enabled && status.available,"setupRequired":status.setup_required,"installed":status.installed,"version":status.version,
        "unavailableReason":if enabled { status.unavailable_reason } else { Some("This agent is turned off.".into()) },
        "checkedAt":checked_at,"auth":{"status":status.auth_status,"checkedAt":auth_checked_at.unwrap_or_else(|| checked_at.clone())},"setup":status.setup,
        "models":models,"modelsSource":source,"modelsError":models_error,
        "defaultModel":instance.as_ref().and_then(|instance| instance.default_model.clone()),
        "capabilities":capabilities,"capabilitiesSource":"adapterExpected","mcpInjectionSource":mcp_injection_source(&provider),
        "runtimeModes":traits.as_ref().map(|traits| traits.runtime_modes.to_vec()).unwrap_or_default(),
        "interactionModes":traits.as_ref().map(|traits| traits.interaction_modes.to_vec()).unwrap_or_default(),
    })
}

async fn models(
    factory: &dyn ProviderFactory,
    provider: &str,
    instance: Option<&ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
    discover: bool,
) -> (Vec<Value>, &'static str, Option<String>) {
    let default_model = instance.and_then(|instance| instance.default_model.clone());
    let mut models = Vec::new();
    let mut error = None;
    if discover {
        match tokio::time::timeout(
            DISCOVERY_TIMEOUT,
            factory.discover_model_metadata(provider, instance, cwd),
        )
        .await
        {
            Ok(Some(Ok(discovered))) => models = discovered,
            Ok(Some(Err(_))) => error = Some("Model discovery failed. Try Refresh.".into()),
            Err(_) => error = Some("Model discovery timed out.".into()),
            _ => {}
        }
    }
    let discovered = !models.is_empty();
    let mut configured = instance
        .map(|instance| instance.models.clone())
        .unwrap_or_default();
    if let Some(default) = &default_model {
        configured.insert(0, default.clone());
    }
    let has_configured = configured.iter().any(|id| !id.trim().is_empty());
    for id in configured.into_iter().filter(|id| !id.trim().is_empty()) {
        if !models
            .iter()
            .any(|model| model.get("id").and_then(Value::as_str) == Some(&id))
        {
            models.push(json!({"id":id,"label":id,"source":"configured"}));
        }
    }
    let mut seen = std::collections::HashSet::new();
    models.retain(|model| {
        model
            .get("id")
            .and_then(Value::as_str)
            .is_some_and(|id| !id.trim().is_empty() && seen.insert(id.to_owned()))
    });
    for model in &mut models {
        model["isDefault"] =
            json!(model.get("id").and_then(Value::as_str) == default_model.as_deref());
        if !matches!(provider, "codex" | "cursor") {
            if let Some(object) = model.as_object_mut() {
                object.remove("reasoningEfforts");
                object.remove("defaultReasoningEffort");
            }
        }
    }
    if models.is_empty() || (provider == "claudeAgent" && !discovered) {
        models.push(json!({"id":null,"label":"Provider Default","isDefault":true}));
    }
    (
        models,
        if discovered {
            if has_configured {
                "discoveredAndConfigured"
            } else {
                "discovered"
            }
        } else if has_configured {
            "configured"
        } else {
            "providerDefault"
        },
        error,
    )
}
