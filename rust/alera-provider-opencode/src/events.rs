use crate::provider::{opencode_kind, OpenCodeProvider};
use crate::request_events::{
    item_id, map_form, map_permission, map_question, map_request_resolved, refs,
};
use alera_provider_protocol::{
    CanonicalItemType, ContentDeltaPayload, EventKind, ItemLifecyclePayload, ItemStatus,
    ProviderError, ProviderEvent, RawEvent, StreamKind, TurnStatus,
};
use opencode_agent_sdk::{Generation, HttpTransport, OpenCodeEvent};
use serde_json::{json, Value};
pub(crate) fn map_event<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    event: OpenCodeEvent,
) -> Result<ProviderEvent, ProviderError> {
    let thread_id = provider.thread_id()?;
    let props = event
        .payload
        .get("properties")
        .or_else(|| event.payload.get("data"))
        .cloned()
        .unwrap_or_else(|| event.payload.clone());
    let app_turn_id = provider.active_turn.as_ref().map(|turn| turn.id.clone());
    let native_turn_id = provider
        .active_turn
        .as_ref()
        .and_then(|turn| turn.native_message_id.clone());
    let native_item_id = item_id(&props);
    let raw_method = event
        .payload
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or(&event.event_type)
        .to_owned();
    let raw = Some(RawEvent {
        source: match provider.client.config().generation {
            Generation::Legacy1 => opencode_agent_sdk::LEGACY_SOURCE.into(),
            Generation::V2 => opencode_agent_sdk::V2_SOURCE.into(),
        },
        method: Some(raw_method),
        message_type: None,
        payload: event.raw.clone(),
    });
    let mut mapped = match event.event_type.as_str() {
        "message.part.delta" => map_delta(
            &props,
            &thread_id,
            app_turn_id.clone(),
            native_item_id.clone(),
            raw,
            provider.native_parts.stream_kind(&props),
            provider.native_parts.is_user_part(&props),
        )?,
        "session.text.delta" => map_delta(
            &props,
            &thread_id,
            app_turn_id.clone(),
            native_item_id.clone(),
            raw,
            Some(StreamKind::AssistantText),
            false,
        )?,
        "session.reasoning.delta" => map_delta(
            &props,
            &thread_id,
            app_turn_id.clone(),
            native_item_id.clone(),
            raw,
            Some(StreamKind::ReasoningText),
            false,
        )?,
        "message.part.updated" => {
            provider.native_parts.record_part(&props);
            crate::part_events::map_part_updated(
                provider,
                &props,
                &thread_id,
                app_turn_id.clone(),
                native_item_id.clone(),
                raw,
            )?
        }
        "session.tool.input.started"
        | "session.tool.input.delta"
        | "session.tool.input.ended"
        | "session.tool.called"
        | "session.tool.progress"
        | "session.tool.success"
        | "session.tool.failed" => crate::tool_events::map_tool(
            provider,
            &event.event_type,
            &props,
            &thread_id,
            app_turn_id.clone(),
            native_item_id.clone(),
            raw,
        )?,
        "message.updated" => {
            provider.native_parts.record_message(&props);
            crate::part_events::map_message_updated(&props, &thread_id, app_turn_id.clone(), raw)?
        }
        "permission.asked" => {
            map_permission(provider, &props, &thread_id, app_turn_id.clone(), raw)?
        }
        "form.created" => map_form(provider, &props, &thread_id, app_turn_id.clone(), raw)?,
        "question.asked" => map_question(provider, &props, &thread_id, app_turn_id.clone(), raw)?,
        "permission.replied" | "form.replied" | "form.cancelled" | "question.replied"
        | "question.rejected" => {
            map_request_resolved(provider, &props, &thread_id, app_turn_id.clone(), raw)?
        }
        "session.execution.succeeded"
        | "session.execution.failed"
        | "session.execution.interrupted"
        | "unreadable.execution.ended" => {
            let terminal_type = event
                .payload
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or(&event.event_type);
            map_terminal(provider, terminal_type, &props, &thread_id, raw)?
        }
        "session.execution.started" | "unreadable.execution.started" => {
            map_thread_state(&props, &thread_id, "active", raw)?
        }
        "session.idle" => {
            if provider.client.config().generation == Generation::Legacy1 {
                map_terminal(provider, &event.event_type, &props, &thread_id, raw)?
            } else {
                map_thread_state(&props, &thread_id, "idle", raw)?
            }
        }
        "session.status" => {
            let state = props
                .get("status")
                .and_then(|status| status.get("type"))
                .and_then(Value::as_str)
                .unwrap_or("active");
            if provider.client.config().generation == Generation::Legacy1 && state == "idle" {
                map_terminal(provider, &event.event_type, &props, &thread_id, raw)?
            } else {
                map_thread_state(&props, &thread_id, state, raw)?
            }
        }
        "session.error" => map_error(provider, &props, &thread_id, raw)?,
        "session.compacted" => map_compaction(&props, &thread_id, app_turn_id.clone(), raw)?,
        "todo.updated" => map_plan(&props, &thread_id, app_turn_id.clone(), raw)?,
        "session.created" | "session.updated" => map_thread(&props, &thread_id, raw)?,
        "session.deleted" => map_thread_state(&props, &thread_id, "closed", raw)?,
        _ => {
            let mut unknown = ProviderEvent::new(
                opencode_kind(),
                provider.config.provider_instance_id.clone(),
                thread_id.clone(),
                EventKind::Unknown(event.event_type.clone()),
                event.payload.clone(),
                raw,
            );
            unknown.turn_id = app_turn_id;
            unknown.provider_refs = Some(refs(native_turn_id.clone(), native_item_id, None));
            unknown
        }
    };
    if let Some(native_turn_id) = native_turn_id {
        mapped
            .provider_refs
            .get_or_insert_with(Default::default)
            .provider_turn_id = Some(native_turn_id);
    }
    mapped.provider_instance_id = provider.config.provider_instance_id.clone();
    mapped.validate()?;
    Ok(mapped)
}

fn map_delta(
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    item_id: Option<String>,
    raw: Option<RawEvent>,
    forced_kind: Option<StreamKind>,
    is_user_part: bool,
) -> Result<ProviderEvent, ProviderError> {
    let delta = props
        .get("delta")
        .or_else(|| props.get("text"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            ProviderError::Protocol("OpenCode message.part.delta has no delta".into())
        })?;
    let stream_kind = forced_kind.unwrap_or_else(|| {
        match props
            .get("part")
            .and_then(|part| part.get("type"))
            .and_then(Value::as_str)
            .or_else(|| props.get("type").and_then(Value::as_str))
        {
            Some("reasoning") => StreamKind::ReasoningText,
            _ => StreamKind::AssistantText,
        }
    });
    let (kind, payload) = if delta.is_empty() || is_user_part {
        // Empty strings are valid native deltas. User parts are already recorded
        // by the host; retain both envelopes without projecting assistant content.
        (
            EventKind::Unknown(
                raw.as_ref()
                    .and_then(|raw| raw.method.clone())
                    .unwrap_or_else(|| "message.part.delta".into()),
            ),
            props.clone(),
        )
    } else {
        let payload = serde_json::to_value(ContentDeltaPayload {
            stream_kind,
            delta: delta.to_owned(),
            content_index: None,
            summary_index: None,
        })
        .map_err(|error| ProviderError::Protocol(error.to_string()))?;
        (EventKind::ContentDelta, payload)
    };
    let mut event = ProviderEvent::new(opencode_kind(), "opencode", thread_id, kind, payload, raw);
    event.turn_id = turn_id;
    event.item_id = item_id.clone();
    event.provider_refs = Some(refs(None, item_id, None));
    Ok(event)
}

fn map_terminal<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    event_type: &str,
    props: &Value,
    thread_id: &str,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    provider.native_parts.clear();
    let Some(active) = provider.active_turn.take() else {
        return map_thread_state(props, thread_id, "idle", raw);
    };
    let state = if active.interrupted || event_type.ends_with("interrupted") {
        TurnStatus::Interrupted
    } else if event_type.ends_with("failed") {
        TurnStatus::Failed
    } else {
        TurnStatus::Completed
    };
    if let Some(session) = provider.session.as_mut() {
        session.status = if state == TurnStatus::Failed {
            alera_provider_protocol::SessionStatus::Error
        } else {
            alera_provider_protocol::SessionStatus::Ready
        };
        session.active_turn_id = None;
    }
    let mut payload = json!({ "state": state });
    if let Some(error) = props
        .get("error")
        .and_then(|error| error.get("message"))
        .and_then(Value::as_str)
    {
        payload["errorMessage"] = Value::String(error.to_owned());
    }
    let mut event = ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::TurnCompleted,
        payload,
        raw,
    );
    event.turn_id = Some(active.id);
    event.provider_refs = Some(refs(active.native_message_id, None, None));
    Ok(event)
}

fn map_error<T: HttpTransport>(
    provider: &mut OpenCodeProvider<T>,
    props: &Value,
    thread_id: &str,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    if provider.active_turn.is_some() {
        let aborted = props
            .get("error")
            .and_then(|error| {
                error
                    .get("name")
                    .or_else(|| error.get("type"))
                    .and_then(Value::as_str)
            })
            .is_some_and(|kind| kind.eq_ignore_ascii_case("aborted"));
        return map_terminal(
            provider,
            if aborted {
                "session.execution.interrupted"
            } else {
                "session.execution.failed"
            },
            props,
            thread_id,
            raw,
        );
    }
    let message = props
        .get("error")
        .and_then(|error| error.get("data").or(Some(error)))
        .and_then(|error| error.get("message"))
        .and_then(Value::as_str)
        .unwrap_or("OpenCode session error")
        .to_owned();
    Ok(ProviderEvent::new(
        opencode_kind(),
        provider.config.provider_instance_id.clone(),
        thread_id,
        EventKind::RuntimeError,
        json!({ "message": message }),
        raw,
    ))
}

fn map_compaction(
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let payload = serde_json::to_value(ItemLifecyclePayload {
        item_type: CanonicalItemType::ContextCompaction,
        status: Some(ItemStatus::Completed),
        title: Some("Context compacted".into()),
        detail: None,
        data: Some(props.clone()),
        agent_id: None,
        parent_tool_use_id: None,
    })
    .map_err(|error| ProviderError::Protocol(error.to_string()))?;
    let mut event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        EventKind::ItemCompleted,
        payload,
        raw,
    );
    event.turn_id = turn_id;
    Ok(event)
}

fn map_plan(
    props: &Value,
    thread_id: &str,
    turn_id: Option<String>,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let mut event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        EventKind::TurnPlanUpdated,
        json!({ "plan": props.get("todos").cloned().unwrap_or_else(|| props.clone()) }),
        raw,
    );
    event.turn_id = turn_id;
    Ok(event)
}

fn map_thread(
    props: &Value,
    thread_id: &str,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let native = props
        .get("info")
        .and_then(|info| info.get("id"))
        .or_else(|| props.get("id"))
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let mut event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        EventKind::ThreadStarted,
        json!({ "providerThreadId": native }),
        raw,
    );
    event.provider_refs = Some(refs(None, None, None));
    Ok(event)
}

fn map_thread_state(
    props: &Value,
    thread_id: &str,
    state: &str,
    raw: Option<RawEvent>,
) -> Result<ProviderEvent, ProviderError> {
    let state = match state {
        "active" | "running" | "busy" => "active",
        "idle" | "waiting" | "ready" => "idle",
        "archived" => "archived",
        "closed" => "closed",
        "compacted" => "compacted",
        "error" | "failed" => "error",
        _ => "active",
    };
    let event = ProviderEvent::new(
        opencode_kind(),
        "opencode",
        thread_id,
        EventKind::ThreadStateChanged,
        json!({ "state": state, "native": props }),
        raw,
    );
    event.validate()?;
    Ok(event)
}
