use crate::error::{ClaudeSdkError, Result};
use crate::types::{
    ControlRequestContext, HookCallback, HookOutput, PermissionResult, ToolPermissionContext,
};
use serde_json::{Map, Value};
use std::sync::atomic::{AtomicU64, Ordering};

pub(crate) fn next_request_id(counter: &AtomicU64) -> String {
    format!("req_{}", counter.fetch_add(1, Ordering::Relaxed) + 1)
}

pub(crate) fn wrap_control_request(request_id: &str, request: Value) -> Value {
    let mut frame = Map::new();
    frame.insert("type".into(), Value::String("control_request".into()));
    frame.insert("request_id".into(), Value::String(request_id.into()));
    frame.insert("request".into(), request);
    Value::Object(frame)
}

pub(crate) fn control_subtype(request: &Value) -> &str {
    request
        .get("subtype")
        .and_then(Value::as_str)
        .unwrap_or("unknown")
}

pub(crate) fn response_result(value: &Value) -> Result<Value> {
    let response = value.get("response").unwrap_or(value);
    if response.get("subtype").and_then(Value::as_str) == Some("error") {
        return Err(ClaudeSdkError::Control {
            subtype: "response".into(),
            message: response
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("unknown control error")
                .into(),
        });
    }
    Ok(response
        .get("response")
        .cloned()
        .unwrap_or(Value::Object(Map::new())))
}

pub(crate) fn build_initialize_request(
    hooks: &mut serde_json::Map<String, Value>,
    agents: &serde_json::Map<String, Value>,
    exclude_dynamic_sections: Option<bool>,
    system_prompt_snapshot: Option<bool>,
    skills: Option<&Vec<String>>,
    forward_subagent_text: bool,
) -> Value {
    let mut request = Map::new();
    request.insert("subtype".into(), Value::String("initialize".into()));
    request.insert(
        "hooks".into(),
        if hooks.is_empty() {
            Value::Null
        } else {
            Value::Object(std::mem::take(hooks))
        },
    );
    if !agents.is_empty() {
        request.insert("agents".into(), Value::Object(agents.clone()));
    }
    if let Some(value) = exclude_dynamic_sections {
        request.insert("excludeDynamicSections".into(), Value::Bool(value));
    }
    if let Some(value) = system_prompt_snapshot {
        request.insert("systemPromptSnapshot".into(), Value::Bool(value));
    }
    if let Some(skills) = skills {
        request.insert(
            "skills".into(),
            Value::Array(skills.iter().cloned().map(Value::String).collect()),
        );
    }
    if forward_subagent_text {
        request.insert("forwardSubagentText".into(), Value::Bool(true));
    }
    Value::Object(request)
}

pub(crate) fn permission_response(request: &Value, result: &PermissionResult) -> Value {
    let default_input = Value::Object(Map::new());
    let input = request.get("input").unwrap_or(&default_input);
    result.to_wire(input)
}

pub(crate) fn permission_context(
    request_id: &str,
    envelope: &Value,
    request: &Value,
) -> ToolPermissionContext {
    ToolPermissionContext {
        suggestions: request
            .get("permission_suggestions")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| serde_json::from_value(item.clone()).ok())
                    .collect()
            })
            .unwrap_or_default(),
        tool_use_id: request
            .get("tool_use_id")
            .and_then(Value::as_str)
            .map(str::to_owned),
        agent_id: request
            .get("agent_id")
            .and_then(Value::as_str)
            .map(str::to_owned),
        blocked_path: request
            .get("blocked_path")
            .and_then(Value::as_str)
            .map(str::to_owned),
        decision_reason: request
            .get("decision_reason")
            .and_then(Value::as_str)
            .map(str::to_owned),
        matched_ask_rule: request
            .get("matched_ask_rule")
            .filter(|rule| !rule.is_null())
            .cloned(),
        suppress_always_allow_rule: request
            .get("suppress_always_allow_rule")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        title: request
            .get("title")
            .and_then(Value::as_str)
            .map(str::to_owned),
        display_name: request
            .get("display_name")
            .and_then(Value::as_str)
            .map(str::to_owned),
        description: request
            .get("description")
            .and_then(Value::as_str)
            .map(str::to_owned),
        control: ControlRequestContext::from_envelope(request_id, envelope),
    }
}

pub(crate) fn hook_response(output: HookOutput) -> Value {
    serde_json::to_value(output).unwrap_or_else(|_| Value::Object(Map::new()))
}

pub(crate) fn error_control_response(request_id: &str, message: impl Into<String>) -> Value {
    serde_json::json!({
        "type": "control_response",
        "response": { "subtype": "error", "request_id": request_id, "error": message.into() }
    })
}

pub(crate) fn success_control_response(request_id: &str, response: Value) -> Value {
    serde_json::json!({
        "type": "control_response",
        "response": { "subtype": "success", "request_id": request_id, "response": response }
    })
}

pub(crate) fn hook_callback_from_map<'a>(
    map: &'a std::collections::HashMap<String, HookCallback>,
    id: &str,
) -> Result<&'a HookCallback> {
    map.get(id)
        .ok_or_else(|| ClaudeSdkError::Callback(format!("no hook callback found for ID {id}")))
}
