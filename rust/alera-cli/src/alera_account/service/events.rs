//! Account calls for runtime events: forwarding the journal to the cloud, and
//! the webhooks that receive it. Events carry identifiers and states only.

use alera_core::runtime::RuntimeEvent;
use anyhow::Result;
use reqwest::Method;
use serde::Deserialize;
use serde_json::{json, Value};

use super::super::cloud_client::CloudRequestError;
use super::AleraAccountService;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ForwardResponse {
    #[serde(default)]
    active_subscriptions: usize,
    #[serde(default)]
    rejected: Vec<RejectedEvent>,
}

/// An event the cloud refused by its payload policy while it stored the rest.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct RejectedEvent {
    #[serde(default)]
    event_id: String,
    #[serde(default)]
    code: String,
}

impl AleraAccountService {
    /// Sends a batch of journal events and returns how many subscriptions
    /// still want this runtime's events. Events the cloud rejected one by one
    /// are logged. `Ok(None)` means the cloud refused the whole batch with a
    /// client error that resending it cannot fix (an older cloud refuses every
    /// batch with one bad event), so the caller should move past it. Transient,
    /// authorization, and rate-limit failures stay errors, and the caller
    /// retries the batch.
    pub(crate) async fn forward_domain_events(
        &self,
        events: &[RuntimeEvent],
    ) -> Result<Option<usize>> {
        let token = self.access_token().await?;
        let events = events
            .iter()
            .map(|event| {
                json!({
                    "eventId": event.event_id,
                    "seq": event.seq,
                    "kind": event.kind,
                    "workspaceId": event.workspace_id,
                    "projectId": event.project_id,
                    "data": event.data,
                    "occurredAt": event.occurred_at,
                })
            })
            .collect::<Vec<_>>();
        let response = self
            .cloud
            .json::<ForwardResponse>(
                Method::POST,
                "/v1/runtime/domain-events",
                Some(&token),
                Some(json!({ "runtimeId": self.runtime_id, "events": events })),
            )
            .await;
        match response {
            Ok(response) => {
                for event in &response.rejected {
                    tracing::warn!(
                        event_id = %event.event_id,
                        code = %event.code,
                        "the cloud rejected a runtime event"
                    );
                }
                Ok(Some(response.active_subscriptions))
            }
            Err(error) => match refusal(&error) {
                Some(reason) => {
                    tracing::warn!(
                        events = events.len(),
                        "the cloud refused a runtime event batch: {reason}"
                    );
                    Ok(None)
                }
                None => Err(error),
            },
        }
    }

    /// Webhook and MCP Events subscriptions that target this runtime.
    pub(crate) async fn event_subscription_count(&self) -> Result<usize> {
        let token = self.access_token().await?;
        let response: ForwardResponse = self
            .cloud
            .json(
                Method::GET,
                "/v1/runtime/event-subscriptions",
                Some(&token),
                None,
            )
            .await?;
        Ok(response.active_subscriptions)
    }

    pub(crate) async fn list_webhooks(&self) -> Result<Value> {
        let token = self.access_token().await?;
        self.cloud
            .json(Method::GET, "/v1/webhooks", Some(&token), None)
            .await
    }

    /// Creates a webhook for this runtime unless `runtime_ids` names others.
    /// The signing secret is returned once.
    pub(crate) async fn create_webhook(
        &self,
        url: &str,
        kinds: &[String],
        runtime_ids: Option<&[String]>,
    ) -> Result<Value> {
        let token = self.access_token().await?;
        let runtime_ids = runtime_ids
            .map(<[String]>::to_vec)
            .unwrap_or_else(|| vec![self.runtime_id.clone()]);
        self.cloud
            .json(
                Method::POST,
                "/v1/webhooks",
                Some(&token),
                Some(json!({ "url": url, "kinds": kinds, "runtimeIds": runtime_ids })),
            )
            .await
    }

    pub(crate) async fn delete_webhook(&self, id: &str) -> Result<()> {
        let token = self.access_token().await?;
        self.cloud
            .empty(
                Method::DELETE,
                &format!("/v1/webhooks/{}", encode_segment(id)),
                Some(&token),
                None,
            )
            .await
    }

    pub(crate) async fn test_webhook(&self, id: &str) -> Result<Value> {
        let token = self.access_token().await?;
        self.cloud
            .json(
                Method::POST,
                &format!("/v1/webhooks/{}/test", encode_segment(id)),
                Some(&token),
                None,
            )
            .await
    }
}

/// A client error other than authorization, timeout, or rate limiting: the same
/// batch would be refused again.
fn refusal(error: &anyhow::Error) -> Option<String> {
    let request = error.downcast_ref::<CloudRequestError>()?;
    (request.is_permanent_failure() && !request.is_permanent_authorization_failure()).then(|| {
        format!(
            "{}: {}",
            request.code().unwrap_or("rejected"),
            request.message()
        )
    })
}

/// Webhook ids are cloud-issued; this keeps a pasted value from changing
/// the path.
fn encode_segment(id: &str) -> String {
    id.chars()
        .filter(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{encode_segment, refusal, ForwardResponse, RejectedEvent};

    #[test]
    fn webhook_ids_cannot_change_the_path() {
        assert_eq!(encode_segment("wh_123-abc"), "wh_123-abc");
        assert_eq!(encode_segment("../admin?x=1"), "adminx1");
    }

    #[test]
    fn runtime_event_forward_responses_carry_rejected_events() {
        let older: ForwardResponse =
            serde_json::from_value(serde_json::json!({ "activeSubscriptions": 2 })).unwrap();
        assert_eq!(older.active_subscriptions, 2);
        assert!(older.rejected.is_empty());
        let newer: ForwardResponse = serde_json::from_value(serde_json::json!({
            "accepted": 1,
            "activeSubscriptions": 1,
            "rejected": [{ "eventId": "e1", "code": "invalid_event_time" }],
        }))
        .unwrap();
        assert_eq!(
            newer.rejected,
            [RejectedEvent {
                event_id: "e1".to_owned(),
                code: "invalid_event_time".to_owned(),
            }]
        );
    }

    #[test]
    fn runtime_event_batches_are_refused_only_by_cloud_client_errors() {
        assert!(refusal(&anyhow::anyhow!("connection reset")).is_none());
    }
}
