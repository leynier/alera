//! `webhook.*`: signed webhooks that receive this runtime's event journal.
//!
//! The cloud stores and delivers them for the signed-in account; the runtime
//! only manages them on the account's behalf. Local clients only: a phone
//! cannot add an outbound destination for the runtime's events.

use serde_json::{json, Value};

use super::account_requests::AccountOperation;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

const EVENT_KINDS_FIELD: &str = "kinds";

impl ServerActor {
    pub(super) fn try_start_webhook_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !matches!(
            request_type,
            "webhook.list" | "webhook.create" | "webhook.delete" | "webhook.test"
        ) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        let service = self.account_push.service.clone();
        match request_type {
            "webhook.list" => self.start_account_operation(
                client_id,
                request_id,
                AccountOperation::McpGrants,
                async move { service.list_webhooks().await.map_err(cloud_error) },
            ),
            "webhook.create" => {
                let url = text(payload, "url")?;
                let kinds = kinds(payload)?;
                let runtime_ids = payload
                    .get("runtimeIds")
                    .and_then(Value::as_array)
                    .map(|ids| {
                        ids.iter()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect::<Vec<_>>()
                    });
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpGrants,
                    async move {
                        let created = service
                            .create_webhook(&url, &kinds, runtime_ids.as_deref())
                            .await
                            .map_err(cloud_error)?;
                        // The forwarder skips events while it believes nothing is
                        // subscribed; let it see the new webhook right away.
                        super::runtime_event_forwarder::request_subscription_refresh();
                        Ok(created)
                    },
                );
            }
            "webhook.delete" => {
                let id = text(payload, "id")?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpGrants,
                    async move {
                        service.delete_webhook(&id).await.map_err(cloud_error)?;
                        Ok(json!({ "deleted": true, "id": id }))
                    },
                );
            }
            _ => {
                let id = text(payload, "id")?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpGrants,
                    async move { service.test_webhook(&id).await.map_err(cloud_error) },
                );
            }
        }
        Ok(true)
    }
}

fn text(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

/// Event kinds the webhook receives; every kind the journal knows by default.
fn kinds(payload: &Value) -> HostResult<Vec<String>> {
    let known = super::runtime_event_requests::EVENT_KINDS;
    let Some(requested) = payload.get(EVENT_KINDS_FIELD).and_then(Value::as_array) else {
        return Ok(known.iter().map(|(kind, _)| (*kind).to_owned()).collect());
    };
    requested
        .iter()
        .map(|kind| {
            kind.as_str()
                .filter(|kind| known.iter().any(|(name, _)| name == kind))
                .map(str::to_owned)
                .ok_or_else(|| HostError::format(format!("Unknown event kind: {kind}")))
        })
        .collect()
}

fn cloud_error(error: anyhow::Error) -> HostError {
    match error.downcast_ref::<crate::terminal_host::alera_account::CloudRequestError>() {
        Some(request) => HostError::state(request.message().to_owned()),
        None => HostError::state(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::kinds;

    #[test]
    fn webhooks_receive_every_kind_unless_they_choose() {
        assert!(kinds(&json!({}))
            .unwrap()
            .contains(&"inbox.reply".to_owned()));
        assert_eq!(
            kinds(&json!({ "kinds": ["agent.status"] })).unwrap(),
            ["agent.status"]
        );
        assert!(kinds(&json!({ "kinds": ["made.up"] })).is_err());
    }
}
