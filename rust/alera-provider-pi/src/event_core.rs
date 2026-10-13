use crate::provider::PiProvider;
use crate::rpc;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{EventKind, ProviderEvent, ProviderRefs, RequestId};
use serde_json::{json, Value};

pub(crate) fn runtime_error<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
) -> Result<ProviderEvent, alera_provider_protocol::ProviderError> {
    let text = message
        .get("error")
        .and_then(Value::as_str)
        .or_else(|| message.get("message").and_then(Value::as_str))
        .unwrap_or("Pi extension error");
    if text.trim().is_empty() {
        return Err(alera_provider_protocol::ProviderError::Protocol(
            "Pi error has no message".into(),
        ));
    }
    Ok(event(
        provider,
        EventKind::RuntimeError,
        json!({ "message": text, "detail": message }),
        &message,
        None,
    ))
}

pub(crate) fn tool_detail(message: &Value) -> Option<String> {
    ["output", "partialOutput", "result"]
        .iter()
        .find_map(|key| message.get(*key).and_then(Value::as_str))
        .or_else(|| {
            message
                .get("result")
                .and_then(|result| result.get("content"))
                .and_then(Value::as_str)
        })
        .map(ToOwned::to_owned)
        .filter(|value| !value.trim().is_empty())
}

pub(crate) fn unknown<T: JsonTransport>(
    provider: &PiProvider<T>,
    message: Value,
    kind: &str,
) -> ProviderEvent {
    event(
        provider,
        EventKind::Unknown(kind.to_owned()),
        message.clone(),
        &message,
        None,
    )
}

pub(crate) fn event<T: JsonTransport>(
    provider: &PiProvider<T>,
    kind: EventKind,
    payload: Value,
    raw: &Value,
    item_id: Option<String>,
) -> ProviderEvent {
    let request_id = RequestId::String("pi-event".into());
    let mut event = provider.event(
        kind,
        payload,
        &request_id,
        rpc::record_type(raw).unwrap_or("event"),
        raw.clone(),
    );
    event.provider_refs = Some(ProviderRefs {
        provider_turn_id: None,
        provider_item_id: item_id.clone(),
        provider_request_id: None,
    });
    event.item_id = item_id;
    event
}

pub(crate) fn event_with_item<T: JsonTransport>(
    provider: &PiProvider<T>,
    kind: EventKind,
    payload: Value,
    raw: &Value,
    item_id: Option<String>,
) -> ProviderEvent {
    event(provider, kind, payload, raw, item_id)
}
