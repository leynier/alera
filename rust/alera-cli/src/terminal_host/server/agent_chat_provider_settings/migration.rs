use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use alera_core::runtime::{
    set_private_file_permissions, AgentChatProviderInstanceRecord, RuntimeStore,
};
use serde_json::{json, Value};

use super::super::agent_chat_runtime::provider_factory::ProviderInstanceConfig;
use super::credentials::ProviderSecrets;
use super::envelope;
use crate::terminal_host::host_error::{HostError, HostResult};

const LEGACY_FILE: &str = "agent-chat-providers.json";
const MAX_BYTES: u64 = 256 * 1024;

pub(super) async fn import_legacy(
    store: &RuntimeStore,
    secrets: &dyn ProviderSecrets,
    runtime_dir: &Path,
    _runtime_id: &str,
) -> HostResult<()> {
    let path = runtime_dir.join(LEGACY_FILE);
    let metadata = match tokio::fs::metadata(&path).await {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(_) => return Err(error()),
    };
    if metadata.len() > MAX_BYTES {
        return Err(error());
    }
    let stored = store
        .agent_chat_provider_instances()
        .await
        .map_err(|_| error())?;
    if stored.revision != 0 || !stored.instances.is_empty() {
        // A completed import may have crashed before moving its source file.
        // Do not overwrite settings or destroy an ambiguous legacy source.
        return Err(HostError::state(
            "Legacy provider settings were retained because host settings already exist.",
        ));
    }
    let bytes = tokio::fs::read(&path).await.map_err(|_| error())?;
    if bytes.len() as u64 > MAX_BYTES {
        return Err(error());
    }
    let raw: Value = serde_json::from_slice(&bytes).map_err(|_| error())?;
    let entries = raw
        .as_array()
        .or_else(|| raw.get("instances").and_then(Value::as_array))
        .ok_or_else(error)?;
    let mut seen = BTreeSet::new();
    let mut prepared = Vec::new();
    let mut values = Vec::new();
    for entry in entries {
        let instance: ProviderInstanceConfig =
            serde_json::from_value(entry.clone()).map_err(|_| error())?;
        if !seen.insert(instance.provider_instance_id.clone()) {
            return Err(error());
        }
        let mut options = instance.options.clone();
        let sensitive_options: Vec<String> = options
            .keys()
            .filter(|key| envelope::secret_option(key))
            .cloned()
            .collect();
        let mut pending = BTreeMap::new();
        for key in &sensitive_options {
            let value = options
                .remove(key)
                .and_then(|value| value.as_str().map(str::to_owned))
                .ok_or_else(error)?;
            pending.insert(format!("option:{key}"), value);
        }
        pending.extend(instance.env.clone());
        let mut model_ids = BTreeSet::new();
        let models: Vec<String> = instance
            .models
            .into_iter()
            .filter(|model| !model.trim().is_empty() && model_ids.insert(model.clone()))
            .collect();
        let environment: Vec<Value> = instance
            .env
            .keys()
            .map(|name| json!({"name":name,"sensitive":true}))
            .collect();
        let input = json!({"providerInstanceId":instance.provider_instance_id,"provider":instance.provider,"label":instance.label,
            "enabled":instance.enabled,"executable":instance.executable,"args":instance.args.unwrap_or_default(),"environment":environment,
            "options":options,"sensitiveOptions":sensitive_options,"customModels":models,"defaultModel":instance.default_model});
        let envelope = envelope::normalize(&input, None, false).map_err(|_| error())?;
        let mut refs = BTreeMap::new();
        for (name, value) in pending {
            let reference = format!("legacy-provider:{}", uuid::Uuid::new_v4());
            refs.insert(name, reference.clone());
            values.push((reference, value));
        }
        prepared.push(AgentChatProviderInstanceRecord {
            provider_instance_id: instance.provider_instance_id,
            envelope,
            secret_refs: refs,
            revision: 0,
        });
    }
    if prepared.is_empty() {
        return Ok(());
    }
    // Validate the whole source before any credential or SQLite write.
    let mut saved = Vec::new();
    for (reference, value) in &values {
        if secrets.save(reference, value).await.is_err() {
            for reference in saved {
                let _ = secrets.clear(reference).await;
            }
            return Err(error());
        }
        saved.push(reference.as_str());
    }
    match store
        .import_agent_chat_provider_instances_if_empty(&prepared)
        .await
    {
        Ok(true) => {}
        Ok(false) => {
            for reference in saved {
                let _ = secrets.clear(reference).await;
            }
            return Err(HostError::state(
                "Legacy provider settings were retained because host settings changed.",
            ));
        }
        Err(_) => {
            // An uncertain commit must not erase credentials it may reference.
            if let Ok(stored) = store.agent_chat_provider_instances().await {
                for reference in saved {
                    if !stored
                        .instances
                        .iter()
                        .any(|record| record.secret_refs.values().any(|value| value == reference))
                    {
                        let _ = secrets.clear(reference).await;
                    }
                }
            }
            return Err(error());
        }
    }
    let imported = runtime_dir.join(format!("{LEGACY_FILE}.imported"));
    if tokio::fs::try_exists(&imported)
        .await
        .map_err(|_| error())?
    {
        return Err(HostError::state("Provider settings imported; the legacy file was retained because a backup already exists."));
    }
    // The retained original is the lossless backup and may contain old keys.
    set_private_file_permissions(&path).map_err(|_| error())?;
    tokio::fs::rename(&path, &imported).await.map_err(|_| {
        HostError::state("Provider settings imported; the legacy backup could not be moved.")
    })?;
    Ok(())
}

fn error() -> HostError {
    HostError::state(
        "Legacy provider settings could not be imported. The original file was retained.",
    )
}
