use crate::provider::PiProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, RawEvent, RequestId};
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

pub(crate) fn session_exited<T: JsonTransport>(provider: &PiProvider<T>) -> ProviderEvent {
    let thread_id = provider
        .session
        .as_ref()
        .map(|session| session.thread_id.clone())
        .unwrap_or_else(|| "pi-pending-thread".into());
    ProviderEvent::new(
        provider.kind(),
        provider.config.instance_id.clone(),
        thread_id,
        EventKind::SessionExited,
        json!({
            "reason": "Pi process exited",
            "recoverable": false,
            "exitKind": "error"
        }),
        Some(RawEvent {
            source: "pi.rpc".into(),
            method: Some("eof".into()),
            message_type: Some("session_exit".into()),
            payload: Value::Null,
        }),
    )
}
