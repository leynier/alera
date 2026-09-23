use super::{account_requests::AccountOperation, requests::require_string_key, ServerActor};
use crate::terminal_host::{
    host_error::{HostError, HostResult},
    protocol::event,
};
use serde_json::{json, Value};

impl ServerActor {
    pub(super) fn try_start_configuration_cloud(
        &mut self,
        client_id: u64,
        request_id: i64,
        request: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !request.starts_with("configuration.cloud.") {
            return Ok(false);
        }
        self.require_authenticated_local_request(client_id, request)?;
        let account = require_string_key(payload, "accountId")?;
        let action = request
            .trim_start_matches("configuration.cloud.")
            .to_owned();
        let body = payload
            .get("operation")
            .cloned()
            .unwrap_or_else(|| payload.clone());
        let service = self.account_push.service.clone();
        self.start_account_operation(
            client_id,
            request_id,
            AccountOperation::Configuration,
            async move {
                service
                    .configuration_request(&account, &action, body)
                    .await
                    .map_err(|e| HostError::state(e.to_string()))
            },
        );
        Ok(true)
    }

    pub(super) async fn handle_configuration_request(
        &mut self,
        client_id: u64,
        request: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        let mut request = request.to_owned();
        let mut payload = payload.clone();
        if request.starts_with("configuration.transfer.") {
            let account = require_string_key(&payload, "accountId")?;
            let result = self
                .configuration_transfer(client_id, &request, &account, &payload)
                .await?;
            if request != "configuration.transfer.commit" {
                return Ok(result);
            }
            request = format!("configuration.{}", require_string_key(&result, "action")?);
            payload = result["payload"].clone();
            if payload["accountId"] != account {
                return Err(HostError::state("Configuration account changed."));
            }
        }
        let store = &self.runtime_store;
        let result: anyhow::Result<Value> = async {
            match request.as_str() {
                "configuration.settings.get" => store.configuration_settings().await,
                "configuration.settings.seed" => {
                    store.configuration_seed(payload["settings"].clone()).await
                }
                "configuration.settings.update" => {
                    let supported: Option<Vec<String>> = payload
                        .get("supportedKeyboardActionIds")
                        .map(|value| serde_json::from_value(value.clone()))
                        .transpose()?;
                    store
                        .configuration_update_settings_for_client(
                            payload["settings"].clone(),
                            supported.as_deref(),
                        )
                        .await?;
                    Ok(json!({}))
                }
                "configuration.snapshot" => {
                    store
                        .configuration_snapshot(&require_string_key(&payload, "accountId")?)
                        .await
                }
                "configuration.apply" => {
                    if let Some(items) = payload["document"]
                        .pointer("/shared/agentProfiles/items")
                        .and_then(Value::as_object)
                    {
                        for item in items.values() {
                            super::declared_catalog_requests::profile_from_payload(item)?;
                        }
                    }
                    store
                        .configuration_apply(
                            &require_string_key(&payload, "accountId")?,
                            &require_string_key(&payload, "expectedFingerprint")?,
                            &payload["document"],
                            &payload["base"],
                            &payload["pending"],
                        )
                        .await?;
                    Ok(json!({}))
                }
                "configuration.published" => {
                    store
                        .configuration_published(
                            &require_string_key(&payload, "accountId")?,
                            &require_string_key(&payload, "operationId")?,
                            &payload["revision"],
                        )
                        .await?;
                    Ok(json!({}))
                }
                _ => anyhow::bail!("Unknown configuration request."),
            }
        }
        .await;
        let value = result.map_err(|e| HostError::state(e.to_string()))?;
        if matches!(
            request.as_str(),
            "configuration.apply" | "configuration.settings.update"
        ) {
            for name in ["runtimeSettingsChanged", "agentProfilesChanged"] {
                self.broadcast_authenticated(event(name, json!({})));
            }
        }
        Ok(value)
    }

    async fn configuration_transfer(
        &mut self,
        client: u64,
        request: &str,
        account: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        let result: anyhow::Result<Value> = async {
            let current = self.runtime_store.alera_account().await?;
            if current.as_ref().map(|a| a.account_id.as_str()) != Some(account) {
                anyhow::bail!("The selected account does not own this runtime.");
            }
            if request == "configuration.transfer.start" {
                let action = require_string_key(payload, "action")?;
                if action == "snapshot" {
                    let snapshot = self.runtime_store.configuration_snapshot(account).await?;
                    let bytes = serde_json::to_vec(&snapshot)?;
                    return self.configuration_transfers.start(
                        client,
                        account,
                        &action,
                        bytes.len(),
                        bytes,
                    );
                }
                if !matches!(action.as_str(), "apply" | "published") {
                    anyhow::bail!("Invalid configuration transfer action.");
                }
                let size = transfer_number(payload, "size")?;
                return self
                    .configuration_transfers
                    .start(client, account, &action, size, vec![]);
            }
            let id = require_string_key(payload, "transferId")?;
            match request {
                "configuration.transfer.read" => self.configuration_transfers.read(
                    client,
                    account,
                    &id,
                    transfer_number(payload, "offset")?,
                ),
                "configuration.transfer.chunk" => self.configuration_transfers.chunk(
                    client,
                    account,
                    &id,
                    transfer_number(payload, "offset")?,
                    &require_string_key(payload, "data")?,
                ),
                "configuration.transfer.cancel" => {
                    self.configuration_transfers.cancel(client, account, &id)
                }
                "configuration.transfer.commit" => {
                    let (action, bytes) =
                        self.configuration_transfers.take(client, account, &id)?;
                    let payload: Value = serde_json::from_slice(&bytes)?;
                    Ok(json!({"action": action, "payload": payload}))
                }
                _ => anyhow::bail!("Unknown configuration transfer request."),
            }
        }
        .await;
        result.map_err(|e| HostError::state(e.to_string()))
    }
}

fn transfer_number(payload: &Value, key: &str) -> anyhow::Result<usize> {
    payload[key]
        .as_u64()
        .and_then(|v| usize::try_from(v).ok())
        .ok_or_else(|| anyhow::anyhow!("Invalid configuration transfer {key}."))
}
