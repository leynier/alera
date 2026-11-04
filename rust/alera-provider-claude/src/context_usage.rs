//! Live context fill of the main agent, as T3 Code 66cae3d756 and
//! 15c927899d. Claude reports per-request usage on root assistant snapshots
//! and, with partial messages on, on stream `message_start` and
//! `message_delta`. The model's window comes from the result's `modelUsage`.
//!
//! `autoCompactTokens` is reported only when `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
//! is set, as the window minus Claude Code's 33,000-token reserve.

use super::*;
use claude_agent_sdk::AssistantMessage;

const AUTO_COMPACT_WINDOW_ENV: &str = "CLAUDE_CODE_AUTO_COMPACT_WINDOW";
const AUTO_COMPACT_RESERVE_TOKENS: u64 = 33_000;

#[derive(Debug, Clone, Copy, Default)]
struct RequestUsage {
    input: u64,
    cache_creation: u64,
    cache_read: u64,
    output: u64,
}

impl RequestUsage {
    fn from_value(usage: &Value) -> Option<Self> {
        let number = |key: &str| usage.get(key).and_then(Value::as_u64).unwrap_or(0);
        Some(Self {
            input: usage.get("input_tokens")?.as_u64()?,
            cache_creation: number("cache_creation_input_tokens"),
            cache_read: number("cache_read_input_tokens"),
            output: number("output_tokens"),
        })
    }

    fn input_total(self) -> u64 {
        self.input
            .saturating_add(self.cache_creation)
            .saturating_add(self.cache_read)
    }

    fn context(self) -> u64 {
        self.input_total().saturating_add(self.output)
    }

    /// A `message_delta` keeps the start's input counts unless it names
    /// them; its output count replaces the start's.
    fn merge_delta(self, usage: &Value) -> Self {
        let pick =
            |key: &str, current: u64| usage.get(key).and_then(Value::as_u64).unwrap_or(current);
        Self {
            input: pick("input_tokens", self.input),
            cache_creation: pick("cache_creation_input_tokens", self.cache_creation),
            cache_read: pick("cache_read_input_tokens", self.cache_read),
            output: pick("output_tokens", self.output),
        }
    }
}

#[derive(Debug, Default)]
pub(crate) struct ContextUsage {
    message_id: Option<String>,
    /// None after a compaction made the tracked request stale.
    request: Option<RequestUsage>,
    context: Option<u64>,
    model: Option<String>,
    window: Option<u64>,
    auto_compact_window: Option<u64>,
}

impl ContextUsage {
    pub(crate) fn from_env(lookup: impl Fn(&str) -> Option<String>) -> Self {
        let disabled = |key: &str| {
            lookup(key).is_some_and(|value| {
                let value = value.trim().to_ascii_lowercase();
                !value.is_empty() && value != "0" && value != "false"
            })
        };
        let auto_compact_window = lookup(AUTO_COMPACT_WINDOW_ENV)
            .and_then(|value| value.trim().parse::<u64>().ok())
            .filter(|window| *window > AUTO_COMPACT_RESERVE_TOKENS)
            .filter(|_| !disabled("DISABLE_AUTO_COMPACT") && !disabled("DISABLE_COMPACT"));
        Self {
            auto_compact_window,
            ..Self::default()
        }
    }

    fn threshold(&self) -> Option<u64> {
        self.auto_compact_window
            .filter(|window| self.window.is_none_or(|max| *window < max))
            .map(|window| window - AUTO_COMPACT_RESERVE_TOKENS)
    }

    fn fields(&self) -> Option<Value> {
        let context = self.context?;
        let mut fields = json!({ "contextTokens": context });
        if let Some(window) = self.window {
            fields["contextWindow"] = json!(window);
        }
        if let Some(threshold) = self.threshold() {
            fields["autoCompactTokens"] = json!(threshold);
        }
        Some(fields)
    }
}

impl ClaudeProvider {
    pub(super) fn assistant_context_usage(
        &mut self,
        message: &AssistantMessage,
    ) -> Option<ProviderEvent> {
        if message.parent_tool_use_id.is_some() || message.model == "<synthetic>" {
            return None;
        }
        let usage = RequestUsage::from_value(message.usage.as_ref()?)?;
        let state = &mut self.context_usage;
        if !message.model.is_empty() {
            state.model = Some(message.model.clone());
        }
        let same = message.message_id.is_some() && state.message_id == message.message_id;
        if same {
            // A snapshot of a tracked request only fills a start that
            // reported no input yet.
            match state.request {
                Some(current) if current.input == 0 && usage.input > 0 => {
                    state.request = Some(RequestUsage {
                        output: current.output.max(usage.output),
                        ..usage
                    });
                }
                _ => return None,
            }
        } else {
            state.message_id = message.message_id.clone();
            state.request = Some(usage);
        }
        self.report_context(json!({ "usage": message.usage }), "assistant")
    }

    pub(super) fn stream_context_usage(
        &mut self,
        event: &Value,
        parent_tool_use_id: Option<&str>,
    ) -> Option<ProviderEvent> {
        if parent_tool_use_id.is_some() {
            return None;
        }
        let state = &mut self.context_usage;
        match event.get("type").and_then(Value::as_str)? {
            "message_start" => {
                let message = event.get("message")?;
                let usage = RequestUsage::from_value(message.get("usage")?)?;
                state.message_id = message.get("id").and_then(Value::as_str).map(str::to_owned);
                state.request = Some(usage);
                if let Some(model) = message.get("model").and_then(Value::as_str) {
                    state.model = Some(model.to_owned());
                }
            }
            "message_delta" => {
                let usage = event.get("usage")?;
                state.request = Some(state.request?.merge_delta(usage));
            }
            _ => return None,
        }
        self.report_context(event.clone(), "stream_event")
    }

    /// A compaction makes the tracked request stale and reports the
    /// compacted size.
    pub(super) fn compaction_context_usage(&mut self, payload: &Value) -> Option<ProviderEvent> {
        self.context_usage.request = None;
        let post = payload
            .get("compact_metadata")?
            .get("post_tokens")?
            .as_u64()
            .filter(|tokens| *tokens > 0)?;
        self.context_usage.context = Some(post);
        let fields = self.context_usage.fields()?;
        Some(self.context_event(fields, "compact_boundary", payload.clone()))
    }

    /// Adds the context fields to the turn's `tokenUsage` and learns the
    /// model's window from `modelUsage`.
    pub(super) fn attach_context_usage(
        &mut self,
        terminal: &mut Value,
        model_usage: Option<&Value>,
    ) {
        let state = &mut self.context_usage;
        if let Some(window) =
            model_usage.and_then(|usage| model_window(usage, state.model.as_deref()))
        {
            state.window = Some(window);
        }
        state.message_id = None;
        state.request = None;
        let Some(fields) = state.fields() else {
            return;
        };
        let usage = terminal
            .as_object_mut()
            .expect("terminal payload is an object")
            .entry("tokenUsage")
            .or_insert_with(|| {
                json!({ "usageStatus": "partial", "usageScope": "main_agent", "hasSubagents": false })
            });
        if let (Some(usage), Some(fields)) = (usage.as_object_mut(), fields.as_object()) {
            usage.extend(fields.clone());
        }
    }

    fn report_context(&mut self, raw: Value, message_type: &str) -> Option<ProviderEvent> {
        let request = self.context_usage.request?;
        if request.input_total() == 0 {
            return None;
        }
        self.context_usage.context = Some(request.context());
        let fields = self.context_usage.fields()?;
        Some(self.context_event(fields, message_type, raw))
    }

    fn context_event(&self, fields: Value, message_type: &str, raw: Value) -> ProviderEvent {
        let mut payload =
            json!({ "usageStatus": "partial", "usageScope": "main_agent", "hasSubagents": false });
        if let (Some(payload), Some(fields)) = (payload.as_object_mut(), fields.as_object()) {
            payload.extend(fields.clone());
        }
        self.event(
            EventKind::ThreadTokenUsageUpdated,
            payload,
            self.raw(message_type, raw),
        )
    }
}

/// The model's context window: its own `modelUsage` entry, else the entry
/// that used the most input.
fn model_window(model_usage: &Value, model: Option<&str>) -> Option<u64> {
    let entries = model_usage.as_object()?;
    let window = |entry: &Value| entry.get("contextWindow").and_then(Value::as_u64);
    if let Some(window) = model.and_then(|model| entries.get(model)).and_then(window) {
        return Some(window).filter(|window| *window > 0);
    }
    let input = |entry: &Value| {
        [
            "inputTokens",
            "cacheReadInputTokens",
            "cacheCreationInputTokens",
        ]
        .iter()
        .filter_map(|key| entry.get(*key).and_then(Value::as_u64))
        .sum::<u64>()
    };
    entries
        .values()
        .filter(|entry| input(entry) > 0)
        .max_by_key(|entry| input(entry))
        .and_then(window)
        .filter(|window| *window > 0)
}

#[cfg(test)]
mod tests {
    use super::ContextUsage;

    #[test]
    fn the_auto_compact_point_needs_a_window_above_the_reserve() {
        let usage = |value: &str| {
            ContextUsage::from_env(|key| {
                (key == "CLAUDE_CODE_AUTO_COMPACT_WINDOW").then(|| value.to_owned())
            })
        };
        assert_eq!(usage("150000").threshold(), Some(117_000));
        assert_eq!(usage("33000").threshold(), None);
        assert_eq!(usage("x").threshold(), None);
        let mut known = usage("200000");
        known.window = Some(200_000);
        assert_eq!(known.threshold(), None);
        let disabled = ContextUsage::from_env(|key| match key {
            "CLAUDE_CODE_AUTO_COMPACT_WINDOW" => Some("150000".into()),
            "DISABLE_AUTO_COMPACT" => Some("1".into()),
            _ => None,
        });
        assert_eq!(disabled.threshold(), None);
    }
}
