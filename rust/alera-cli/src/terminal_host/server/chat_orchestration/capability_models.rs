//! The model list `chat_capabilities` shows an agent: per provider, the
//! models the person did not hide, in their order, cut to a few, with the
//! ones that matter always kept. `search` finds the rest.

use serde_json::{json, Value};

/// How many models a provider lists for an agent, besides pinned ones.
pub(super) const CAPABILITY_MODEL_LIMIT: usize = 8;
/// The longest `search` a caller may send.
pub(crate) const CAPABILITY_SEARCH_MAX_CHARS: usize = 200;
/// Providers whose catalogs are short and curated, so every model is listed.
const FULL_LIST_PROVIDERS: &[&str] = &["codex", "claudeAgent", "grok", "muse"];

/// The calling chat's own selection, which stays listed.
pub(super) struct CallerModel<'a> {
    pub provider_instance_id: &'a str,
    pub model: Option<&'a str>,
}

fn id(model: &Value) -> Option<&str> {
    model.get("id").and_then(Value::as_str)
}

fn configured(model: &Value) -> bool {
    model["source"] == "configured"
}

fn placeholder(model: &Value) -> bool {
    model.get("id").is_none_or(Value::is_null)
}

/// Shortens every provider's `models` in a capabilities response.
pub(super) fn shorten_models(
    providers: &mut [Value],
    preferences: &Value,
    caller: Option<&CallerModel<'_>>,
    search: Option<&str>,
) {
    for provider in providers {
        shorten_provider(provider, preferences, caller, search);
    }
}

fn shorten_provider(
    provider: &mut Value,
    preferences: &Value,
    caller: Option<&CallerModel<'_>>,
    search: Option<&str>,
) {
    let instance = provider["providerInstanceId"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let kind = provider["provider"].as_str().unwrap_or_default().to_owned();
    let Some(models) = provider.get("models").and_then(Value::as_array).cloned() else {
        return;
    };
    let prefs = &preferences["models"][instance.as_str()];
    let listed = |key: &str| -> Vec<String> {
        prefs[key]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(ToOwned::to_owned)
            .collect()
    };
    let hidden = listed("hidden");
    let order = listed("order");
    let mut visible: Vec<Value> = models
        .into_iter()
        .filter(|model| {
            configured(model)
                || placeholder(model)
                || !id(model).is_some_and(|id| hidden.iter().any(|hidden| hidden == id))
        })
        .collect();
    visible.sort_by_key(|model| {
        id(model)
            .and_then(|id| order.iter().position(|ordered| ordered == id))
            .unwrap_or(usize::MAX)
    });
    let favorite = |model: &Value| {
        preferences["favorites"]
            .as_array()
            .into_iter()
            .flatten()
            .any(|favorite| {
                favorite["providerInstanceId"] == instance.as_str()
                    && favorite.get("model").and_then(Value::as_str) == id(model)
            })
    };
    let own = |model: &Value| {
        caller.is_some_and(|caller| {
            caller.provider_instance_id == instance
                && caller.model.is_some()
                && caller.model == id(model)
        })
    };
    let pinned = |model: &Value| {
        configured(model)
            || placeholder(model)
            || model["isDefault"] == true
            || favorite(model)
            || own(model)
    };
    let total = visible.len();
    let search = search.map(str::trim).filter(|search| !search.is_empty());
    let kept: Vec<Value> = match search {
        Some(search) => {
            let terms: Vec<String> = search.split_whitespace().map(str::to_lowercase).collect();
            let matches: Vec<Value> = visible
                .into_iter()
                .filter(|model| {
                    let haystack = format!(
                        "{} {}",
                        id(model).unwrap_or_default(),
                        model["label"].as_str().unwrap_or_default()
                    )
                    .to_lowercase();
                    terms.iter().all(|term| haystack.contains(term))
                })
                .collect();
            let shown = matches
                .iter()
                .take(CAPABILITY_MODEL_LIMIT)
                .cloned()
                .collect();
            provider["omittedModels"] = json!(matches.len().saturating_sub(CAPABILITY_MODEL_LIMIT));
            shown
        }
        None if FULL_LIST_PROVIDERS.contains(&kind.as_str()) => visible,
        None => visible
            .into_iter()
            .enumerate()
            .filter(|(index, model)| *index < CAPABILITY_MODEL_LIMIT || pinned(model))
            .map(|(_, model)| model)
            .collect(),
    };
    if search.is_none() {
        provider["omittedModels"] = json!(total - kept.len());
    }
    if provider["omittedModels"] == 0 {
        if let Some(object) = provider.as_object_mut() {
            object.remove("omittedModels");
        }
    }
    provider["models"] = Value::Array(kept);
}

#[cfg(test)]
#[path = "capability_models_tests.rs"]
mod tests;
