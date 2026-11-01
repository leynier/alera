//! Where an ACP session keeps its model choice, after T3 Code's
//! `findModelConfigOption` and `sessionSetupResult.models`.

use serde_json::Value;

/// A `models` state from `session/new`, `session/load` or `session/resume`
/// (`{availableModels: [{modelId, name}], currentModelId}`), the pre-config
/// option way ACP v1 agents such as Grok report their models.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct LegacyModelState {
    pub(crate) available: Vec<(String, String)>,
    pub(crate) current: Option<String>,
}

/// How the live session selects a model.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ModelInventory {
    /// A select config option, written with `session/set_config_option`.
    Option { id: String, values: Vec<String> },
    /// The legacy `models` state, written with `session/set_model`.
    Legacy(LegacyModelState),
    /// An ACP v1 `setModel` capability without any list.
    Capability,
    /// Nothing says the agent can change its model.
    Unknown,
}

impl ModelInventory {
    /// The model ids the session offers; empty when it lists none.
    pub(crate) fn offered(&self) -> Vec<String> {
        match self {
            Self::Option { values, .. } => values.clone(),
            Self::Legacy(state) => state.available.iter().map(|(id, _)| id.clone()).collect(),
            Self::Capability | Self::Unknown => Vec::new(),
        }
    }
}

/// Whether `model` may be written to a session that offers `offered`. An
/// empty list defers to the agent. With `family_variants`, an unlisted id
/// that extends a listed one with `-suffix` passes too: Antigravity runtime
/// 1.3 lists `gemini-3.8-flash` and takes `gemini-3.8-flash-high`.
pub(crate) fn offers_model(offered: &[String], model: &str, family_variants: bool) -> bool {
    offered.is_empty()
        || offered.iter().any(|offered| offered == model)
        || (family_variants
            && offered.iter().any(|family| {
                model
                    .strip_prefix(family.as_str())
                    .and_then(|rest| rest.strip_prefix('-'))
                    .is_some_and(|variant| !variant.is_empty())
            }))
}

/// The `id` (or `configId`) of a config option.
pub(crate) fn option_id(option: &Value) -> Option<&str> {
    option
        .get("id")
        .or_else(|| option.get("configId"))
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())
}

/// The values of a select option, flattening groups, without duplicates.
pub(crate) fn select_values(option: &Value) -> Vec<String> {
    select_choices(option)
        .into_iter()
        .map(|(value, _)| value)
        .collect()
}

/// The `(value, name)` choices of a select option, flattening groups.
pub(crate) fn select_choices(option: &Value) -> Vec<(String, String)> {
    fn collect(options: &[Value], choices: &mut Vec<(String, String)>) {
        for option in options {
            if let Some(value) = option
                .get("value")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
            {
                if !choices.iter().any(|(existing, _)| existing == value) {
                    let name = option
                        .get("name")
                        .and_then(Value::as_str)
                        .filter(|name| !name.trim().is_empty())
                        .unwrap_or(value);
                    choices.push((value.into(), name.into()));
                }
            }
            if let Some(group) = option.get("options").and_then(Value::as_array) {
                collect(group, choices);
            }
        }
    }
    let mut choices = Vec::new();
    if let Some(options) = option.get("options").and_then(Value::as_array) {
        collect(options, &mut choices);
    }
    choices
}

fn is_select(option: &Value) -> bool {
    option.get("type").and_then(Value::as_str) == Some("select")
}

/// The session's model option: the select option whose id is `model`, else
/// the first select option in the `model` category. Preferring the id goes
/// beyond T3 Code because Vercel's fx also files its `provider` option under
/// the model category.
pub(crate) fn model_option(options: &[Value]) -> Option<&Value> {
    options
        .iter()
        .find(|option| is_select(option) && option_id(option) == Some("model"))
        .or_else(|| {
            options.iter().find(|option| {
                is_select(option)
                    && option.get("category").and_then(Value::as_str) == Some("model")
                    && option_id(option).is_some()
            })
        })
}

/// The `models` state of a session setup result.
pub(crate) fn legacy_model_state(raw: &Value) -> Option<LegacyModelState> {
    let models = raw.get("models").filter(|models| models.is_object())?;
    let available = models
        .get("availableModels")
        .and_then(Value::as_array)
        .map(|models| {
            let mut available: Vec<(String, String)> = Vec::new();
            for model in models {
                let Some(id) = model
                    .get("modelId")
                    .and_then(Value::as_str)
                    .filter(|id| !id.trim().is_empty())
                else {
                    continue;
                };
                if available.iter().any(|(existing, _)| existing == id) {
                    continue;
                }
                let name = model
                    .get("name")
                    .and_then(Value::as_str)
                    .filter(|name| !name.trim().is_empty())
                    .unwrap_or(id);
                available.push((id.into(), name.into()));
            }
            available
        })
        .unwrap_or_default();
    let current = models
        .get("currentModelId")
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())
        .map(str::to_owned);
    Some(LegacyModelState { available, current })
}

/// The live session's model inventory. `prefer_legacy` keeps Grok's ACP v1
/// `session/set_model` when it reports a legacy state next to a model option;
/// `set_model_capability` is ACP v1's `setModel` capability.
pub(crate) fn inventory(
    options: &[Value],
    legacy: Option<&LegacyModelState>,
    prefer_legacy: bool,
    set_model_capability: bool,
) -> ModelInventory {
    if let (true, Some(state)) = (prefer_legacy, legacy) {
        return ModelInventory::Legacy(state.clone());
    }
    if let Some(option) = model_option(options) {
        return ModelInventory::Option {
            id: option_id(option).unwrap_or("model").to_owned(),
            values: select_values(option),
        };
    }
    if let Some(state) = legacy {
        return ModelInventory::Legacy(state.clone());
    }
    if set_model_capability {
        ModelInventory::Capability
    } else {
        ModelInventory::Unknown
    }
}

/// The `(id, label)` models the session offers, from its model option or
/// else its legacy state.
pub(crate) fn session_model_choices(
    options: &[Value],
    legacy: Option<&LegacyModelState>,
) -> Vec<(String, String)> {
    if let Some(option) = model_option(options) {
        return select_choices(option);
    }
    legacy
        .map(|state| state.available.clone())
        .unwrap_or_default()
}

/// The session's current model, from its model option or legacy state.
pub(crate) fn current_model(
    options: &[Value],
    legacy: Option<&LegacyModelState>,
) -> Option<String> {
    if let Some(option) = model_option(options) {
        return option
            .get("currentValue")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_owned);
    }
    legacy.and_then(|state| state.current.clone())
}

#[cfg(test)]
#[path = "model_inventory_tests.rs"]
mod tests;
