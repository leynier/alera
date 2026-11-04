//! Claude system frames that only inform: `informational` lines (such as a
//! hook dropping the prompt, T3 Code e51c0d6777) and `api_retry`, which
//! becomes one live `error` item while the CLI retries a request.

use super::canonical_payload::*;
use super::*;
use alera_provider_protocol::FailureClass;

#[derive(Debug)]
pub(crate) struct ApiRetry {
    item_id: String,
    data: Value,
}

impl ClaudeProvider {
    /// A non-info `informational` line becomes a notice; info lines, such
    /// as "Started in the background", are dropped.
    pub(super) fn map_informational(&self, payload: &Value) -> Vec<ProviderEvent> {
        let level = payload
            .get("level")
            .and_then(Value::as_str)
            .unwrap_or("info");
        let Some(content) = text_field(payload, &["content"]) else {
            return Vec::new();
        };
        if level == "info" {
            return Vec::new();
        }
        let prevent = payload
            .get("prevent_continuation")
            .filter(|value| value.as_bool() == Some(true))
            .cloned();
        vec![self.event(
            EventKind::RuntimeWarning,
            compact_nulls(json!({
                "message": content.trim(),
                "level": level,
                "preventContinuation": prevent,
                "detail": payload,
            })),
            self.raw("informational", payload.clone()),
        )]
    }

    /// The first retry starts the item; later attempts update it.
    pub(super) fn map_api_retry(&mut self, payload: &Value) -> Vec<ProviderEvent> {
        let attempt = payload.get("attempt").and_then(Value::as_u64);
        let max_attempts = payload.get("max_retries").and_then(Value::as_u64);
        let status = payload.get("error_status").and_then(Value::as_u64);
        let error = text_field(payload, &["error"]).unwrap_or_else(|| "api_error".into());
        let code = status.map_or_else(|| error.clone(), |status| format!("api_error_{status}"));
        let mut detail = format!("Claude API {}.", error.replace('_', " "));
        if let (Some(attempt), Some(max)) = (attempt, max_attempts) {
            detail.push_str(&format!(" Retrying, attempt {attempt} of {max}."));
        }
        let started_at = self
            .turn_signals
            .api_retry
            .as_ref()
            .and_then(|retry| retry.data.get("startedAt").cloned())
            .unwrap_or_else(|| json!(chrono::Utc::now().to_rfc3339()));
        let data = compact_nulls(json!({
            "attempt": attempt,
            "maxAttempts": max_attempts,
            "retryDelayMs": payload.get("retry_delay_ms").filter(|value| value.is_u64()),
            "errorStatus": status,
            "error": error,
            "code": code,
            "startedAt": started_at,
        }));
        let kind = if self.turn_signals.api_retry.is_some() {
            EventKind::ItemUpdated
        } else {
            EventKind::ItemStarted
        };
        let item_id = match &self.turn_signals.api_retry {
            Some(retry) => retry.item_id.clone(),
            None => {
                let scope = self
                    .active_turn_id
                    .try_lock()
                    .ok()
                    .and_then(|turn| turn.clone())
                    .or_else(|| text_field(payload, &["uuid"]))
                    .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
                format!("api-retry:{scope}")
            }
        };
        let retry = ApiRetry { item_id, data };
        let event = self.retry_event(
            &retry,
            kind,
            "inProgress",
            "Provider retry",
            &detail,
            self.raw("api_retry", payload.clone()),
        );
        self.turn_signals.api_retry = Some(retry);
        vec![event]
    }

    /// Assistant activity after a retry means the request went through.
    pub(super) fn recover_api_retry(&mut self) -> Vec<ProviderEvent> {
        let Some(retry) = self.turn_signals.api_retry.take() else {
            return Vec::new();
        };
        vec![self.retry_event(
            &retry,
            EventKind::ItemCompleted,
            "completed",
            "Provider recovered",
            "Claude API recovered.",
            self.raw("api_retry", Value::Null),
        )]
    }

    /// Settles a retry the turn ended during.
    pub(super) fn settle_api_retry(
        &mut self,
        interrupted: bool,
        failed: Option<FailureClass>,
    ) -> Option<ProviderEvent> {
        let retry = self.turn_signals.api_retry.take()?;
        let (status, title, detail) = match (interrupted, failed) {
            (true, _) => (
                "failed",
                "Provider retry stopped",
                "Claude API retry stopped.",
            ),
            (false, Some(FailureClass::UsageLimit)) => (
                "failed",
                "Usage limit reached",
                "Claude API retries ended at a usage limit.",
            ),
            (false, Some(_)) => ("failed", "Provider error", "Claude API retries failed."),
            (false, None) => ("completed", "Provider recovered", "Claude API recovered."),
        };
        Some(self.retry_event(
            &retry,
            EventKind::ItemCompleted,
            status,
            title,
            detail,
            self.raw("api_retry", Value::Null),
        ))
    }

    fn retry_event(
        &self,
        retry: &ApiRetry,
        kind: EventKind,
        status: &str,
        title: &str,
        detail: &str,
        raw: RawEvent,
    ) -> ProviderEvent {
        let mut data = retry.data.clone();
        if kind == EventKind::ItemCompleted {
            data["completedAt"] = json!(chrono::Utc::now().to_rfc3339());
        }
        let mut event = self.event(
            kind,
            json!({
                "itemType": "error",
                "status": status,
                "title": title,
                "detail": detail,
                "data": data,
            }),
            raw,
        );
        event.item_id = Some(retry.item_id.clone());
        event.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: None,
        });
        event
    }
}
