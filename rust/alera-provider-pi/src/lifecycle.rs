use crate::provider::PiProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{EventKind, ProviderEvent, RequestId};
use serde_json::{json, Value};

pub(crate) fn prompt_failed<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
) -> ProviderEvent {
    let error_message = message
        .get("errorMessage")
        .and_then(Value::as_str)
        .or_else(|| message.get("error").and_then(Value::as_str))
        .map(ToOwned::to_owned)
        .or_else(|| {
            message
                .get("error")
                .filter(|value| !value.is_null())
                .and_then(|value| serde_json::to_string(value).ok())
        })
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "Pi rejected the prompt".into());
    provider.event(
        EventKind::TurnCompleted,
        json!({ "state": "failed", "errorMessage": error_message }),
        &RequestId::String("pi-prompt".into()),
        "response",
        message,
    )
}
