//! Reject sensitive values before a provider envelope reaches SQLite.

use std::collections::BTreeSet;

use anyhow::Result;
use serde_json::Value;

use super::agent_chat_secrets::reject_secret_fields;
use super::agent_chat_settings_store::bounded_json;
use super::agent_chat_validation::require_id;
use super::{AgentChatStoreError, AGENT_CHAT_SETTINGS_MAX_ENTRIES};

fn invalid(message: &str) -> anyhow::Error {
    AgentChatStoreError::Invalid(message.into()).into()
}

pub(super) fn declared_secrets(envelope: &Value) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    for entry in envelope
        .get("environment")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if entry.get("sensitive").and_then(Value::as_bool) == Some(true) {
            if let Some(name) = entry.get("name").and_then(Value::as_str) {
                names.insert(name.to_string());
            }
        }
    }
    for name in envelope
        .get("sensitiveOptions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let Some(name) = name.as_str() {
            names.insert(format!("option:{name}"));
        }
    }
    names
}

pub(super) fn require_provider_envelope(instance_id: &str, envelope: &Value) -> Result<()> {
    require_id("providerInstanceId", instance_id)?;
    bounded_json(envelope)?;
    let object = envelope
        .as_object()
        .ok_or_else(|| invalid("provider envelope must be an object"))?;
    if object.keys().any(|key| {
        !matches!(
            key.as_str(),
            "providerInstanceId"
                | "provider"
                | "label"
                | "enabled"
                | "executable"
                | "args"
                | "environment"
                | "options"
                | "customModels"
                | "defaultModel"
                | "sensitiveOptions"
        )
    }) {
        return Err(invalid("unknown provider envelope field"));
    }
    if object.get("providerInstanceId").and_then(Value::as_str) != Some(instance_id) {
        return Err(invalid("provider envelope identity mismatch"));
    }
    require_id(
        "provider",
        object.get("provider").and_then(Value::as_str).unwrap_or(""),
    )?;
    if object.get("enabled").and_then(Value::as_bool).is_none() {
        return Err(invalid("provider enabled must be a boolean"));
    }
    for key in ["label", "executable", "defaultModel"] {
        if let Some(value) = object.get(key).filter(|value| !value.is_null()) {
            if !value.is_string() || value.as_str().is_some_and(|value| value.len() > 4096) {
                return Err(invalid("provider text field is invalid"));
            }
        }
    }
    for key in ["args", "customModels", "environment", "sensitiveOptions"] {
        if let Some(value) = object.get(key) {
            let list = value
                .as_array()
                .ok_or_else(|| invalid("provider field must be a list"))?;
            if list.len() > AGENT_CHAT_SETTINGS_MAX_ENTRIES {
                return Err(invalid("too many provider entries"));
            }
            if key == "args" && list.iter().any(|value| !value.is_string()) {
                return Err(invalid("provider args must be strings"));
            }
        }
    }
    let mut names = BTreeSet::new();
    for entry in object
        .get("environment")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let entry = entry
            .as_object()
            .ok_or_else(|| invalid("environment declaration must be an object"))?;
        if entry
            .keys()
            .any(|key| !matches!(key.as_str(), "name" | "sensitive" | "value"))
        {
            return Err(invalid("unknown environment declaration field"));
        }
        let name = entry.get("name").and_then(Value::as_str).unwrap_or("");
        require_id("environment name", name)?;
        if name.contains(['=', '\0']) || !names.insert(name) {
            return Err(invalid("invalid or duplicate environment name"));
        }
        let sensitive = entry
            .get("sensitive")
            .and_then(Value::as_bool)
            .ok_or_else(|| invalid("environment sensitivity must be declared"))?;
        if let Some(value) = entry.get("value").filter(|value| !value.is_null()) {
            if sensitive {
                return Err(invalid(
                    "sensitive environment values belong in the credential store",
                ));
            }
            if !value.is_string() {
                return Err(invalid("environment value must be a string"));
            }
            // Secret-shaped names cannot opt out of credential storage.
            reject_secret_fields("environment", &serde_json::json!({name: value}))?;
        }
    }
    let mut option_names = BTreeSet::new();
    for name in object
        .get("sensitiveOptions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let name = name.as_str().unwrap_or("");
        require_id("sensitive option name", name)?;
        if !option_names.insert(name)
            || object
                .get("options")
                .and_then(|value| value.get(name))
                .is_some()
        {
            return Err(invalid(
                "sensitive options must be unique and have no plaintext value",
            ));
        }
    }
    if let Some(options) = object.get("options") {
        if !options.is_object() {
            return Err(invalid("provider options must be an object"));
        }
        reject_secret_fields("provider options", options)?;
    }
    if let Some(models) = object.get("customModels") {
        reject_secret_fields("custom models", models)?;
    }
    Ok(())
}
