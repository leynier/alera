//! OpenCode 2.x schedules a retry after a retryable provider error and says
//! nothing when it goes through. As T3 Code shows the retry instead of a
//! silently running turn, the adapter reports it as a notice.

use crate::provider::{opencode_kind, OpenCodeProvider};
use crate::request_events::refs;
use alera_provider_protocol::{EventKind, ProviderEvent, RawEvent};
use opencode_agent_sdk::HttpTransport;
use serde_json::{json, Value};

pub(crate) fn map_retry<T: HttpTransport>(
    provider: &OpenCodeProvider<T>,
    envelope: &Value,
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> ProviderEvent {
    // OpenCode counts the first request as attempt 1, so its first retry is 2.
    let retry = props
        .get("attempt")
        .and_then(Value::as_u64)
        .map(|attempt| attempt.saturating_sub(1).max(1));
    let delay_ms = props
        .get("at")
        .and_then(Value::as_i64)
        .zip(envelope.get("created").and_then(Value::as_i64))
        .map(|(at, created)| (at - created).max(0));
    let error = props.get("error").cloned().unwrap_or(Value::Null);
    let reason = error
        .get("message")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .unwrap_or("a provider error");
    let mut message = format!("OpenCode is retrying after {reason}");
    match (retry, delay_ms) {
        (Some(retry), Some(delay)) => {
            message.push_str(&format!(" (retry {retry}, in {}s)", seconds(delay)))
        }
        (Some(retry), None) => message.push_str(&format!(" (retry {retry})")),
        (None, Some(delay)) => message.push_str(&format!(" (in {}s)", seconds(delay))),
        (None, None) => {}
    }
    message.push('.');
    let mut payload = json!({ "message": message, "retryable": true, "error": error });
    if let Some(retry) = retry {
        payload["attempt"] = json!(retry);
    }
    if let Some(delay) = delay_ms {
        payload["retryDelayMs"] = json!(delay);
    }
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::RuntimeWarning,
        payload,
        raw,
    );
    event.turn_id = turn_id;
    event.provider_refs = Some(refs(None, None, None));
    event
}

fn seconds(delay_ms: i64) -> i64 {
    (delay_ms + 999) / 1000
}
