//! Token usage of ACP turns and sessions, after T3 Code's
//! `acpPerTurnPromptUsage` and its `usage_update` handling.

use crate::AcpProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{EventKind, ProviderEvent};
use serde_json::{json, Map, Value};

/// The `tokenUsage` of one prompt whose response's `usage` covers exactly
/// that prompt. Counters that exceed their parent are clamped and unset ones
/// dropped; without input and output counters the usage is unavailable.
pub(crate) fn per_turn_prompt_usage(
    usage: Option<&Value>,
    has_subagents: bool,
    completed: bool,
) -> Value {
    let counter = |key: &str| {
        usage
            .and_then(|usage| usage.get(key))
            .and_then(Value::as_u64)
    };
    let (Some(input), Some(output)) = (counter("inputTokens"), counter("outputTokens")) else {
        return json!({"usageScope":"main_agent","usageStatus":"unavailable","hasSubagents":has_subagents});
    };
    let mut payload = json!({
        "usageScope": "main_agent",
        "usageStatus": if completed { "complete" } else { "partial" },
        "hasSubagents": has_subagents,
        "inputTokens": input,
        "outputTokens": output,
    });
    let cached = counter("cachedReadTokens").map(|value| value.min(input));
    if let Some(cached) = cached {
        payload["cachedInputTokens"] = json!(cached);
    }
    if let Some(written) = counter("cachedWriteTokens") {
        payload["cacheCreationTokens"] = json!(written.min(input - cached.unwrap_or(0)));
    }
    if let Some(reasoning) = counter("thoughtTokens") {
        payload["reasoningTokens"] = json!(reasoning.min(output));
    }
    payload
}

/// The `thread.token-usage.updated` payload of a `usage_update`: the
/// context in use, the window when the agent knows it, and the cost.
pub(crate) fn context_usage(update: &Value) -> Option<Value> {
    let used = update.get("used").and_then(Value::as_u64)?;
    let mut payload = json!({"contextTokens": used});
    if let Some(size) = update
        .get("size")
        .and_then(Value::as_u64)
        .filter(|size| *size > 0)
    {
        payload["contextWindow"] = json!(size);
    }
    let cost = update.get("cost");
    let amount = cost
        .and_then(|cost| cost.get("amount"))
        .filter(|amount| amount.is_number());
    let currency = cost
        .and_then(|cost| cost.get("currency"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|currency| !currency.is_empty())
        .map(|currency| currency.chars().take(32).collect::<String>());
    if let (Some(amount), Some(currency)) = (amount, currency) {
        payload["cost"] = json!({"amount": amount, "currency": currency});
    }
    Some(payload)
}

const CONTEXT_FIELDS: [&str; 2] = ["contextTokens", "contextWindow"];

/// What the adapter knows of the session's usage between events.
#[derive(Debug, Default)]
pub(crate) struct AcpUsageState {
    prompt_usage: Option<Value>,
    context: Map<String, Value>,
}

impl AcpUsageState {
    pub(crate) fn reset(&mut self) {
        *self = Self::default();
    }
}

fn from_prompt_response(event: &ProviderEvent) -> bool {
    event.raw.as_ref().and_then(|raw| raw.method.as_deref()) == Some("session/prompt")
}

impl<T: JsonTransport> AcpProvider<T> {
    /// Records usage from a root event and fills a completed turn's
    /// `tokenUsage`: the prompt response's usage when the agent reports
    /// per-turn usage, with the latest context counters, which the turn
    /// repeats.
    pub(crate) fn settle_usage(&mut self, event: &mut ProviderEvent) {
        let state = &mut self.usage;
        match &event.kind {
            EventKind::ThreadTokenUsageUpdated => {
                for field in CONTEXT_FIELDS {
                    if let Some(value) = event.payload.get(field) {
                        state.context.insert(field.into(), value.clone());
                    }
                }
            }
            EventKind::Unknown(name) if name == "acp.prompt.accepted" => {
                state.prompt_usage = event
                    .payload
                    .get("usage")
                    .filter(|usage| usage.is_object())
                    .cloned();
            }
            EventKind::TurnCompleted => {
                if from_prompt_response(event) {
                    if let Some(usage) =
                        event.payload.get("usage").filter(|usage| usage.is_object())
                    {
                        state.prompt_usage = Some(usage.clone());
                    }
                }
                let prompt_usage = state.prompt_usage.take();
                if !self.config.reports_per_turn_prompt_usage {
                    return;
                }
                let completed = event.payload["state"] == "completed";
                let mut usage = per_turn_prompt_usage(
                    prompt_usage.as_ref(),
                    self.children.any_linked(),
                    completed,
                );
                for (field, value) in &state.context {
                    usage[field] = value.clone();
                }
                event.payload["tokenUsage"] = usage;
            }
            _ => {}
        }
    }
}

#[cfg(test)]
#[path = "usage_tests.rs"]
mod tests;
