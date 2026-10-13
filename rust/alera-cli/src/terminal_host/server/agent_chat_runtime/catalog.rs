//! `agentChat.providers`: every provider instance with its availability and
//! models. Model lists come from configuration or a provider's own cheap
//! discovery; when neither exists the list says so instead of guessing.

use std::path::PathBuf;
use std::time::Duration;

use futures_util::future::join_all;
use serde_json::{json, Value};

use super::provider_factory::{ProviderFactory, ProviderInstanceConfig};
use super::provider_traits::{capabilities_json, mcp_injection_source, provider_traits, PROVIDERS};
use super::InstanceDirectory;

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(15);

#[cfg(test)]
#[path = "provider_catalog_tests.rs"]
mod tests;

pub(crate) async fn provider_catalog(
    factory: &dyn ProviderFactory,
    instances: &InstanceDirectory,
    cwd: Option<PathBuf>,
    refresh_models: bool,
) -> Value {
    instances.reload();
    let mut entries: Vec<(String, Option<ProviderInstanceConfig>)> = PROVIDERS
        .iter()
        .map(|provider| (provider.to_string(), None))
        .collect();
    for instance in instances.configured() {
        entries.push((instance.provider.clone(), Some(instance)));
    }
    let providers = join_all(entries.into_iter().map(|(provider, instance)| {
        let cwd = cwd.clone();
        async move { entry(factory, provider, instance, cwd, refresh_models).await }
    }))
    .await;
    json!({ "providers": providers })
}

async fn entry(
    factory: &dyn ProviderFactory,
    provider: String,
    instance: Option<ProviderInstanceConfig>,
    cwd: Option<PathBuf>,
    refresh_models: bool,
) -> Value {
    let traits = provider_traits(&provider);
    let availability = factory.availability(&provider, instance.as_ref()).await;
    let (models, source, models_error) = models(
        factory,
        &provider,
        instance.as_ref(),
        cwd,
        refresh_models && availability.is_ok(),
    )
    .await;
    let mut capabilities = capabilities_json(&provider, None);
    if provider == "opencode"
        && instance
            .as_ref()
            .is_some_and(|instance| instance.options.contains_key("serverUrl"))
    {
        capabilities["mcpInjection"] = json!({"stdio": false, "http": false});
    }
    json!({
        "provider": provider,
        "providerInstanceId": instance
            .as_ref()
            .map(|instance| instance.provider_instance_id.clone())
            .unwrap_or_else(|| provider.clone()),
        "label": instance
            .as_ref()
            .and_then(|instance| instance.label.clone())
            .or_else(|| traits.as_ref().map(|traits| traits.label.to_string())),
        "custom": instance.is_some(),
        "available": availability.is_ok(),
        "unavailableReason": availability.err(),
        "models": models,
        "modelsSource": source,
        "modelsError": models_error,
        "capabilities": capabilities,
        "capabilitiesSource": "adapterExpected",
        "mcpInjectionSource": mcp_injection_source(&provider),
        "runtimeModes": traits.as_ref().map(|traits| traits.runtime_modes.to_vec()).unwrap_or_default(),
        "interactionModes": traits.as_ref().map(|traits| traits.interaction_modes.to_vec()).unwrap_or_default(),
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
    let model_entry = |id: &str| json!({"id": id, "label": id, "isDefault": default_model.as_deref() == Some(id)});
    let mut configured: Vec<String> = instance
        .map(|instance| instance.models.clone())
        .unwrap_or_default();
    if let Some(default_model) = &default_model {
        if !configured.contains(default_model) {
            configured.insert(0, default_model.clone());
        }
    }
    configured.retain(|model| !model.trim().is_empty());
    let mut seen = std::collections::HashSet::new();
    configured.retain(|model| seen.insert(model.clone()));
    if !configured.is_empty() {
        return (
            configured.iter().map(|id| model_entry(id)).collect(),
            "configured",
            None,
        );
    }
    let mut error = None;
    if discover {
        match tokio::time::timeout(
            DISCOVERY_TIMEOUT,
            factory.discover_models(provider, instance, cwd),
        )
        .await
        {
            Ok(Some(Ok(models))) if !models.is_empty() => {
                return (
                    models.iter().map(|id| model_entry(id)).collect(),
                    "discovered",
                    None,
                )
            }
            Ok(Some(Err(message))) => error = Some(message),
            Err(_) => error = Some("Model discovery timed out.".into()),
            _ => {}
        }
    }
    (
        vec![json!({"id": null, "label": "Provider default", "isDefault": true})],
        "providerDefault",
        error,
    )
}
