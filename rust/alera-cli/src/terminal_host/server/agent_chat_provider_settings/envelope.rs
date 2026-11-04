use std::collections::BTreeMap;

use alera_core::runtime::AgentChatProviderInstanceRecord;
use serde_json::{json, Value};

use super::super::agent_chat_runtime::provider_factory::ProviderInstanceConfig;
use super::super::agent_chat_runtime::provider_traits::{provider_traits, PROVIDERS};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn default_envelope(id: &str) -> Option<Value> {
    let traits = provider_traits(id)?;
    let environment: Vec<Value> = match id {
        "codex" => vec!["OPENAI_API_KEY"],
        "claudeAgent" => vec!["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"],
        "cursor" => vec!["CURSOR_API_KEY"],
        "grok" => vec!["XAI_API_KEY"],
        _ => Vec::new(),
    }
    .into_iter()
    .map(|name| json!({"name":name,"sensitive":true}))
    .collect();
    let sensitive_options = match id {
        "cursor" => vec!["apiKey", "bridgeBearerToken"],
        "opencode" => vec!["serverPassword"],
        _ => Vec::new(),
    };
    Some(
        json!({"providerInstanceId":id,"provider":id,"label":traits.label,"enabled":true,
        "args":[],"environment":environment,"options":{},"sensitiveOptions":sensitive_options,"customModels":[]}),
    )
}

pub(super) fn secret_option(name: &str) -> bool {
    matches!(
        name,
        "bridgeBearerToken" | "bearerToken" | "apiKey" | "serverPassword"
    )
}

pub(super) fn declared(envelope: &Value, name: &str) -> bool {
    if let Some(option) = name.strip_prefix("option:") {
        return envelope["sensitiveOptions"]
            .as_array()
            .is_some_and(|names| names.iter().any(|name| name.as_str() == Some(option)));
    }
    envelope["environment"].as_array().is_some_and(|entries| {
        entries
            .iter()
            .any(|entry| entry["name"].as_str() == Some(name) && entry["sensitive"] == true)
    })
}

pub(super) fn normalize(
    input: &Value,
    existing: Option<&Value>,
    mobile: bool,
) -> HostResult<Value> {
    let object = input
        .as_object()
        .ok_or_else(|| HostError::format("instance must be an object"))?;
    let id = object
        .get("providerInstanceId")
        .and_then(Value::as_str)
        .filter(|id| !id.trim().is_empty())
        .ok_or_else(|| HostError::format("providerInstanceId is required"))?;
    let default = default_envelope(id);
    let base = existing.or(default.as_ref());
    if mobile && base.is_none() {
        return Err(not_allowed());
    }
    let mut result = base.cloned().unwrap_or_else(|| json!({"providerInstanceId":id,"enabled":true,"environment":[],"options":{},"sensitiveOptions":[],"customModels":[],"args":[]}));
    for (key, value) in object {
        if matches!(key.as_str(), "revision" | "secretOptions") {
            continue;
        }
        if !matches!(
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
        ) {
            return Err(HostError::format("Unknown provider instance field."));
        }
        result[key] = value.clone();
    }
    if let Some(environment) = result.get_mut("environment").and_then(Value::as_array_mut) {
        for entry in environment {
            if let Some(object) = entry.as_object_mut() {
                object.remove("secretSaved");
            }
        }
    }
    if let Some(object) = result.as_object_mut() {
        object.remove("revision");
        object.remove("secretOptions");
    }
    for key in ["label", "executable"] {
        if result[key]
            .as_str()
            .is_some_and(|value| value.trim().is_empty())
        {
            result[key] = Value::Null;
        }
    }
    if mobile {
        let base = base.expect("mobile base validated");
        for key in [
            "provider",
            "label",
            "executable",
            "args",
            "environment",
            "options",
            "sensitiveOptions",
        ] {
            if result.get(key) != base.get(key) {
                return Err(not_allowed());
            }
        }
    }
    validate(&result)?;
    Ok(result)
}

fn validate(envelope: &Value) -> HostResult<()> {
    if serde_json::to_vec(envelope)
        .map_err(|_| HostError::format("Invalid provider instance."))?
        .len()
        > 256 * 1024
    {
        return Err(HostError::format("Provider instance is too large."));
    }
    let provider = envelope["provider"]
        .as_str()
        .ok_or_else(|| HostError::format("provider is required"))?;
    let models = envelope["customModels"]
        .as_array()
        .ok_or_else(|| HostError::format("customModels must be a list of model IDs."))?;
    let mut model_ids = std::collections::HashSet::new();
    if models.len() > 500
        || models.iter().any(|model| {
            model.as_str().is_none_or(|model| {
                model.trim().is_empty()
                    || model.len() > 4096
                    || model.contains('\0')
                    || !model_ids.insert(model)
            })
        })
    {
        return Err(HostError::format(
            "Custom model IDs must be nonempty, bounded and unique.",
        ));
    }
    let id = envelope["providerInstanceId"]
        .as_str()
        .expect("identity validated");
    if !PROVIDERS.contains(&provider) || (PROVIDERS.contains(&id) && provider != id) {
        return Err(HostError::format("Provider instance identity is invalid."));
    }
    if let Some(options) = envelope["options"].as_object() {
        if options.keys().any(|key| secret_option(key)) {
            return Err(HostError::format(
                "Sensitive options must be saved through Secrets.",
            ));
        }
        for value in options.values() {
            if let Some(url) = value.as_str().and_then(|value| url::Url::parse(value).ok()) {
                if !url.username().is_empty()
                    || url.password().is_some()
                    || url.query_pairs().any(|(name, _)| {
                        matches!(
                            name.to_ascii_lowercase().as_str(),
                            "token"
                                | "access_token"
                                | "api_key"
                                | "apikey"
                                | "password"
                                | "authorization"
                                | "secret"
                        )
                    })
                {
                    return Err(HostError::format(
                        "Provider URLs cannot contain credentials.",
                    ));
                }
            }
        }
    }
    if envelope["sensitiveOptions"]
        .as_array()
        .is_some_and(|names| {
            names.iter().any(|name| {
                !matches!(
                    (provider, name.as_str()),
                    (
                        "cursor",
                        Some("apiKey" | "bridgeBearerToken" | "bearerToken")
                    ) | ("opencode", Some("serverPassword"))
                )
            })
        })
    {
        return Err(HostError::format("Provider secret option is unsupported."));
    }
    if envelope["environment"].as_array().is_some_and(|entries| {
        entries.iter().any(|entry| {
            entry["sensitive"] == true && entry.get("value").is_some_and(|value| !value.is_null())
        })
    }) {
        return Err(HostError::format(
            "Sensitive environment values must be saved through Secrets.",
        ));
    }
    let config = config(envelope, BTreeMap::new());
    super::super::agent_chat_runtime::production_factory::validate_instance(&config)
        .map_err(|_| HostError::format("Provider launch options are invalid or unsupported."))
}

pub(super) fn config(
    envelope: &Value,
    secret_refs: BTreeMap<String, String>,
) -> ProviderInstanceConfig {
    ProviderInstanceConfig {
        provider_instance_id: envelope["providerInstanceId"]
            .as_str()
            .unwrap_or_default()
            .into(),
        provider: envelope["provider"].as_str().unwrap_or_default().into(),
        label: envelope["label"].as_str().map(str::to_owned),
        executable: envelope["executable"].as_str().map(Into::into),
        args: envelope["args"].as_array().map(|args| {
            args.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        }),
        env: envelope["environment"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|entry| entry["sensitive"] == false)
            .filter_map(|entry| {
                Some((
                    entry["name"].as_str()?.to_owned(),
                    entry["value"].as_str()?.to_owned(),
                ))
            })
            .collect(),
        models: envelope["customModels"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        default_model: envelope["defaultModel"].as_str().map(str::to_owned),
        options: envelope["options"].as_object().cloned().unwrap_or_default(),
        enabled: envelope["enabled"].as_bool().unwrap_or(true),
        secret_refs,
        credential_scope: None,
    }
}

pub(super) fn records_with_defaults(
    mut records: Vec<AgentChatProviderInstanceRecord>,
) -> Vec<AgentChatProviderInstanceRecord> {
    for id in PROVIDERS {
        if !records
            .iter()
            .any(|record| record.provider_instance_id == id)
        {
            records.push(AgentChatProviderInstanceRecord {
                provider_instance_id: id.into(),
                envelope: default_envelope(id).expect("default provider"),
                secret_refs: Default::default(),
                revision: 0,
            });
        }
    }
    records
}

pub(super) fn not_allowed() -> HostError {
    HostError::conflict(
        "notAllowed",
        "This client cannot edit provider launch definitions.",
        json!({}),
    )
}
