use crate::AcpRegistryAgentFlavor;
use alera_provider_protocol::{EventKind, ProviderEvent};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

const COPILOT_SESSION_EVENT: &str = "github.com/copilot/sessionEvent";
const COPILOT_META_KEY: &str = "github.com/copilot";
const DEVIN_META_KEY: &str = "cognition.ai";
const MISTRAL_RATE_LIMIT_CODE: i64 = -31_001;

#[derive(Debug, Default)]
pub(crate) struct RegistryFlavorState {
    copilot: CopilotState,
}

#[derive(Debug, Default)]
struct CopilotState {
    pending_delta: Option<CopilotDelta>,
    task_by_agent: HashMap<String, String>,
}

#[derive(Debug)]
struct CopilotDelta {
    kind: &'static str,
    text: String,
    task_tool_call_id: Option<String>,
}

pub(crate) fn normalize_event(
    mut event: ProviderEvent,
    flavor: AcpRegistryAgentFlavor,
    state: &mut RegistryFlavorState,
) -> ProviderEvent {
    match flavor {
        AcpRegistryAgentFlavor::Devin => normalize_devin(&mut event),
        AcpRegistryAgentFlavor::Copilot => normalize_copilot(&mut event, &mut state.copilot),
        AcpRegistryAgentFlavor::MistralVibe => normalize_mistral(&mut event),
        AcpRegistryAgentFlavor::ClaudeAgent | AcpRegistryAgentFlavor::Generic => {}
    }
    event
}

fn normalize_devin(event: &mut ProviderEvent) {
    let Some(update) = session_update(event).cloned() else {
        return;
    };
    let Some(meta) = record(update.get("_meta")) else {
        return;
    };
    if let Some(parent_agent_id) =
        nested_object_string(meta, DEVIN_META_KEY, "subagent_context", "parentAgentId")
    {
        if !parent_agent_id.is_empty() {
            event.payload["agentId"] = Value::String(parent_agent_id.clone());
            event.payload["childSessionId"] = Value::String(parent_agent_id);
        }
    }
    if matches!(
        event.kind,
        EventKind::ContentDelta
            | EventKind::ItemStarted
            | EventKind::ItemUpdated
            | EventKind::ItemCompleted
    ) {
        if let Some(message_id) = nested_string(meta, DEVIN_META_KEY, "streamingMessageId") {
            if event.item_id.is_none() {
                event.item_id = Some(message_id.clone());
            }
            set_provider_item_ref(event, message_id);
        }
    }
    if let Some(tool_name) = nested_string(meta, DEVIN_META_KEY, "inferenceToolName") {
        if matches!(event.kind, EventKind::ItemStarted | EventKind::ItemUpdated)
            && event
                .payload
                .get("title")
                .and_then(Value::as_str)
                .is_none_or(|title| title.is_empty() || title.eq_ignore_ascii_case("tool"))
        {
            event.payload["title"] = Value::String(tool_name);
        }
    }
    if let Some(started) = nested_object(meta, DEVIN_META_KEY, "subagent_started") {
        if matches!(event.kind, EventKind::ItemStarted | EventKind::ItemUpdated) {
            let agent_id = string_field(started, "agentId");
            if let Some(agent_id) = agent_id {
                let task_id = devin_task_id(&agent_id);
                let mut payload = task_payload(&task_id, started);
                payload["agentId"] = Value::String(agent_id.clone());
                payload["childSessionId"] = Value::String(agent_id);
                event.kind = if matches!(event.kind, EventKind::ItemStarted) {
                    EventKind::TaskStarted
                } else {
                    EventKind::TaskUpdated
                };
                event.payload = payload;
            }
        }
    }
    if let Some(completed) = nested_object(meta, DEVIN_META_KEY, "subagent_completed") {
        if matches!(
            event.kind,
            EventKind::ItemCompleted | EventKind::ItemUpdated
        ) {
            let Some(agent_id) = string_field(completed, "agentId") else {
                return;
            };
            let task_id = devin_task_id(&agent_id);
            let status = if completed.get("success").and_then(Value::as_bool) == Some(false) {
                "failed"
            } else {
                "completed"
            };
            let mut payload = json!({
                "taskId": task_id,
                "status": status,
                "agentId": agent_id,
                "childSessionId": completed.get("agentId"),
            });
            if let Some(summary) = string_field(completed, "summary") {
                payload["summary"] = Value::String(summary);
            }
            event.kind = EventKind::TaskCompleted;
            event.payload = payload;
        }
    }
}

fn normalize_copilot(event: &mut ProviderEvent, state: &mut CopilotState) {
    if event.raw.as_ref().and_then(|raw| raw.method.as_deref()) == Some(COPILOT_SESSION_EVENT) {
        normalize_copilot_session_event(event, state);
        return;
    }
    let Some(update) = session_update(event).cloned() else {
        return;
    };
    if matches!(event.kind, EventKind::ContentDelta) {
        if let Some(delta) = state.pending_delta.take() {
            let expected_kind = match event.payload.get("streamKind").and_then(Value::as_str) {
                Some("assistant_text") => "assistant.message_delta",
                Some("reasoning_text") => "assistant.reasoning_delta",
                _ => "",
            };
            let actual_text = event
                .payload
                .get("delta")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if delta.kind == expected_kind && delta.text == actual_text {
                if let Some(task) = delta.task_tool_call_id {
                    attach_child_attribution(event, &task);
                }
            }
        }
    }
    if matches!(
        event.kind,
        EventKind::ItemStarted | EventKind::ItemUpdated | EventKind::ItemCompleted
    ) {
        if let Some(agent_id) = copilot_agent_id(&update) {
            if let Some(task) = state.task_by_agent.get(&agent_id).cloned() {
                attach_child_attribution(event, &task);
            }
        }
        if let Some(input) = update
            .get("rawInput")
            .or_else(|| update.get("raw_input"))
            .and_then(|value| record(Some(value)))
        {
            if input.get("agent_type").and_then(Value::as_str).is_some()
                && input.get("prompt").and_then(Value::as_str).is_some()
            {
                normalize_copilot_task_tool(event, &update, input);
            }
        }
    }
}

fn normalize_copilot_session_event(event: &mut ProviderEvent, state: &mut CopilotState) {
    let Some(params) = raw_params(event).cloned() else {
        return;
    };
    let event_type = params
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let Some(data) = params.get("data").and_then(|value| record(Some(value))) else {
        return;
    };
    match event_type.as_str() {
        "assistant.message_delta" | "assistant.reasoning_delta" => {
            if let Some(text) = data.get("deltaContent").and_then(Value::as_str) {
                state.pending_delta = Some(CopilotDelta {
                    kind: if event_type == "assistant.message_delta" {
                        "assistant.message_delta"
                    } else {
                        "assistant.reasoning_delta"
                    },
                    text: text.to_owned(),
                    task_tool_call_id: data
                        .get("parentToolCallId")
                        .and_then(Value::as_str)
                        .map(ToOwned::to_owned),
                });
            }
        }
        "subagent.started" => {
            let Some(agent_id) = params.get("agentId").and_then(Value::as_str) else {
                return;
            };
            let Some(tool_call_id) = data.get("toolCallId").and_then(Value::as_str) else {
                return;
            };
            state
                .task_by_agent
                .insert(agent_id.to_owned(), tool_call_id.to_owned());
            event.kind = EventKind::TaskStarted;
            event.payload = json!({
                "taskId": copilot_task_id(tool_call_id),
                "agentId": agent_id,
                "childSessionId": copilot_task_id(tool_call_id),
                "description": data.get("description").or_else(|| data.get("prompt")),
            });
        }
        "subagent.completed" | "subagent.failed" => {
            let agent_id = params.get("agentId").and_then(Value::as_str);
            let tool_call_id = data
                .get("toolCallId")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
                .or_else(|| agent_id.and_then(|id| state.task_by_agent.get(id).cloned()));
            if let Some(agent_id) = agent_id {
                state.task_by_agent.remove(agent_id);
            }
            let Some(tool_call_id) = tool_call_id else {
                return;
            };
            event.kind = EventKind::TaskCompleted;
            event.payload = json!({
                "taskId": copilot_task_id(&tool_call_id),
                "status": if event_type == "subagent.failed" { "failed" } else { "completed" },
                "agentId": agent_id,
                "childSessionId": copilot_task_id(&tool_call_id),
                "summary": data.get("error"),
            });
        }
        _ => {}
    }
}

fn normalize_copilot_task_tool(
    event: &mut ProviderEvent,
    update: &Value,
    input: &Map<String, Value>,
) {
    let Some(tool_id) = update
        .get("toolCallId")
        .or_else(|| update.get("tool_call_id"))
        .and_then(Value::as_str)
    else {
        return;
    };
    let task_id = copilot_task_id(tool_id);
    let status = update
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("running");
    let terminal = matches!(status, "completed" | "failed" | "cancelled" | "stopped");
    event.kind = if terminal {
        EventKind::TaskCompleted
    } else if matches!(event.kind, EventKind::ItemStarted) {
        EventKind::TaskStarted
    } else {
        EventKind::TaskUpdated
    };
    let mut payload = json!({
        "taskId": task_id,
        "description": input.get("description").or_else(|| input.get("prompt")),
        "title": input.get("description"),
        "model": input.get("model"),
        "childSessionId": copilot_task_id(tool_id),
        "agentId": tool_id,
    });
    if terminal {
        payload["status"] = Value::String(
            if status == "failed" {
                "failed"
            } else {
                "completed"
            }
            .into(),
        );
        if let Some(result) = update.get("rawOutput").or_else(|| update.get("raw_output")) {
            payload["summary"] = result.clone();
        }
    } else {
        payload["status"] = Value::String("running".into());
    }
    event.payload = payload;
}

fn normalize_mistral(event: &mut ProviderEvent) {
    let method = event.raw.as_ref().and_then(|raw| raw.method.as_deref());
    if method == Some("_session/retrying") {
        let params = raw_params(event);
        let category = params
            .and_then(|value| value.get("category"))
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        let detail = params
            .and_then(|value| value.get("detail"))
            .and_then(Value::as_str)
            .unwrap_or("provider retry requested");
        let mut payload = json!({
            "message": detail,
            "category": category,
            "retryable": true,
        });
        if category == "rate_limited" {
            payload["appCode"] = Value::from(MISTRAL_RATE_LIMIT_CODE);
            payload["failureClass"] = Value::String("usage_limit".into());
        }
        event.kind = EventKind::RuntimeWarning;
        event.payload = payload;
        return;
    }
    if !matches!(
        event.kind,
        EventKind::TurnCompleted | EventKind::RuntimeError
    ) {
        return;
    }
    let Some(code) = event
        .raw
        .as_ref()
        .and_then(|raw| raw.payload.get("error"))
        .and_then(|error| error.get("code"))
        .and_then(Value::as_i64)
    else {
        return;
    };
    if code == MISTRAL_RATE_LIMIT_CODE {
        event.payload["appCode"] = Value::from(code);
        event.payload["failureClass"] = Value::String("usage_limit".into());
        event.payload["rateLimited"] = Value::Bool(true);
    }
}

fn session_update(event: &ProviderEvent) -> Option<&Value> {
    let params = raw_params(event)?;
    params.get("update").or(Some(params))
}

fn raw_params(event: &ProviderEvent) -> Option<&Value> {
    event.raw.as_ref()?.payload.get("params")
}

fn record(value: Option<&Value>) -> Option<&Map<String, Value>> {
    value?.as_object()
}

fn nested_object<'a>(
    meta: &'a Map<String, Value>,
    namespace: &str,
    key: &str,
) -> Option<&'a Map<String, Value>> {
    meta.get(namespace)?.get(key)?.as_object()
}

fn nested_string(meta: &Map<String, Value>, namespace: &str, key: &str) -> Option<String> {
    meta.get(namespace)?
        .get(key)?
        .as_str()
        .map(ToOwned::to_owned)
}

fn nested_object_string(
    meta: &Map<String, Value>,
    namespace: &str,
    key: &str,
    nested: &str,
) -> Option<String> {
    meta.get(namespace)?
        .get(key)?
        .get(nested)?
        .as_str()
        .map(ToOwned::to_owned)
}

fn string_field(object: &Map<String, Value>, key: &str) -> Option<String> {
    object
        .get(key)?
        .as_str()
        .map(ToOwned::to_owned)
        .filter(|value| !value.is_empty())
}

fn task_payload(task_id: &str, source: &Map<String, Value>) -> Value {
    let mut payload = json!({"taskId": task_id});
    if let Some(title) = string_field(source, "title").or_else(|| string_field(source, "task")) {
        payload["description"] = Value::String(title);
    }
    if let Some(model) = string_field(source, "model") {
        payload["model"] = Value::String(model);
    }
    payload
}

fn devin_task_id(agent_id: &str) -> String {
    format!("devin-task:{agent_id}")
}

fn copilot_task_id(tool_call_id: &str) -> String {
    format!("copilot-task:{tool_call_id}")
}

fn set_provider_item_ref(event: &mut ProviderEvent, item_id: String) {
    let refs = event.provider_refs.get_or_insert_with(Default::default);
    refs.provider_item_id = Some(item_id);
}

fn attach_child_attribution(event: &mut ProviderEvent, task_tool_call_id: &str) {
    let child = copilot_task_id(task_tool_call_id);
    event.payload["agentId"] = Value::String(task_tool_call_id.to_owned());
    event.payload["childSessionId"] = Value::String(child.clone());
    if matches!(
        event.kind,
        EventKind::ItemStarted | EventKind::ItemUpdated | EventKind::ItemCompleted
    ) {
        event.payload["parentToolUseId"] = Value::String(task_tool_call_id.to_owned());
    }
}

fn copilot_agent_id(update: &Value) -> Option<String> {
    let meta = record(update.get("_meta"))?;
    record(meta.get(COPILOT_META_KEY))?
        .get("agentId")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}
